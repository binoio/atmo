"""Control and power command execution via pyatv."""

from __future__ import annotations

import asyncio
import contextlib
import inspect
import json
import sys
from dataclasses import dataclass
from typing import Any, Optional

from pyatv import connect, interface
from pyatv import exceptions as pyatv_exceptions
from pyatv.const import DeviceState, InputAction, PowerState, Protocol
PYATV_ERROR = getattr(
    pyatv_exceptions,
    "PyatvError",
    getattr(pyatv_exceptions, "PyATVError", Exception),
)
from pyatv.interface import AppleTV, BaseConfig, Storage

with contextlib.suppress(Exception):
    from pyatv.protocols.companion import CompanionPower

    async def _safe_companion_power_init(self) -> None:
        self._power_state = PowerState.On

    CompanionPower.initialize = _safe_companion_power_init

from .device_lookup import select_config
from .discovery import DiscoveryOptions, scan_configs
from .storage import load_storage


class ControlError(Exception):
    """Raised when sending a command fails."""


@dataclass
class CommandOptions:
    """Incoming CLI options for remote commands."""

    identifier: str
    command: str
    action: str = "SingleTap"
    protocol: Optional[str] = None
    storage_path: Optional[str] = None
    use_storage: bool = True
    mock: bool = False


@dataclass
class PowerOptions:
    """Incoming CLI options for power commands."""

    identifier: str
    action: str
    protocol: Optional[str] = None
    storage_path: Optional[str] = None
    use_storage: bool = True
    mock: bool = False


@dataclass
class SessionOptions:
    """Options for maintaining a persistent command session."""

    identifier: str
    protocol: Optional[str] = None
    storage_path: Optional[str] = None
    use_storage: bool = True
    mock: bool = False


async def execute_command(options: CommandOptions) -> dict:
    """Execute a remote control command."""

    if options.mock:
        return {
            "status": "ok",
            "identifier": options.identifier,
            "command": options.command,
            "action": options.action,
            "mock": True,
        }

    loop = asyncio.get_running_loop()

    storage: Optional[Storage] = None
    if options.use_storage:
        storage = await load_storage(loop, options.storage_path)

    configs = await scan_configs(
        DiscoveryOptions(
            timeout=5,
            protocol=options.protocol,
            identifier=None,
            storage_path=options.storage_path,
            use_storage=options.use_storage,
        ),
        storage=storage,
    )

    config = select_config(configs, options.identifier)
    if config is None:
        raise ControlError("device not found")

    action = _parse_action(options.action)

    command = options.command.lower()

    atv = await _connect_device(config, loop, storage, protocol=options.protocol)

    try:
        await _invoke_remote(atv, command, action)
    finally:
        atv.close()

    return {
        "status": "ok",
        "identifier": config.identifier,
        "command": command,
        "action": action.name,
    }


async def execute_power(options: PowerOptions) -> dict:
    """Execute a power command."""

    if options.mock:
        action = options.action.lower()
        if action == "status":
            return {
                "status": "ok",
                "identifier": options.identifier,
                "power_state": "on",
                "mock": True,
            }
        return {
            "status": "ok",
            "identifier": options.identifier,
            "power": options.action,
            "mock": True,
        }

    loop = asyncio.get_running_loop()

    storage: Optional[Storage] = None
    if options.use_storage:
        storage = await load_storage(loop, options.storage_path)

    configs = await scan_configs(
        DiscoveryOptions(
            timeout=5,
            protocol=options.protocol,
            identifier=None,
            storage_path=options.storage_path,
            use_storage=options.use_storage,
        ),
        storage=storage,
    )

    config = select_config(configs, options.identifier)
    if config is None:
        raise ControlError("device not found")

    atv = await _connect_device(config, loop, storage, protocol=options.protocol)

    try:
        power = atv.power
        action = options.action.lower()
        if action == "on":
            await power.turn_on()
        elif action == "off":
            await power.turn_off()
        elif action == "status":
            state = await _resolve_power_state(atv, power)
            return {
                "status": "ok",
                "identifier": config.identifier,
                "power_state": state.name if isinstance(state, PowerState) else str(state),
            }
        else:
            raise ControlError(f"unknown power action: {options.action}")
    finally:
        atv.close()

    return {
        "status": "ok",
        "identifier": config.identifier,
        "power": options.action,
    }


async def _connect_device(
    config: BaseConfig,
    loop: asyncio.AbstractEventLoop,
    storage: Optional[Storage],
    protocol: Optional[str] = None,
) -> AppleTV:
    try:
        atv = await connect(config, loop, storage=storage)
    except PYATV_ERROR as exc:
        raise ControlError(str(exc)) from exc

    _apply_protocol_takeover(atv, requested_protocol=protocol)
    return atv


def _apply_protocol_takeover(
    atv: AppleTV, requested_protocol: Optional[str] = None
) -> None:
    """Ensure remote control and power interfaces use the appropriate protocol.

    If a specific protocol is requested, take over that protocol.
    Otherwise, if Companion protocol is available (paired/connected), take over
    Companion for RemoteControl and Power so that modern tvOS devices (tvOS 15+)
    receive HID button presses via Companion rather than unauthenticated/deprecated MRP.
    """
    takeover_fn = getattr(atv, "takeover", None)
    if not callable(takeover_fn):
        return

    protocol_handlers = getattr(atv, "_protocol_handlers", {})

    target_proto: Optional[Protocol] = None
    if requested_protocol:
        try:
            parsed = Protocol[requested_protocol]
            if parsed in protocol_handlers:
                target_proto = parsed
        except KeyError:
            pass

    if target_proto is None and Protocol.Companion in protocol_handlers:
        target_proto = Protocol.Companion

    if target_proto is not None:
        with contextlib.suppress(Exception):
            takeover_fn(target_proto, interface.RemoteControl, interface.Power)


def _parse_action(name: str) -> InputAction:
    try:
        return InputAction[name]
    except KeyError as exc:
        raise ControlError(f"unknown input action: {name}") from exc


async def _invoke_remote(
    atv: AppleTV,
    command: str,
    action: InputAction,
) -> None:
    remote = atv.remote_control

    directional_commands = {
        "home": remote.home,
        "menu": remote.menu,
        "select": remote.select,
        "up": remote.up,
        "down": remote.down,
        "left": remote.left,
        "right": remote.right,
    }

    if command in directional_commands:
        await directional_commands[command](action=action)
        return

    if command in {"play_pause", "playpause"}:
        await _invoke_play_pause(atv)
        return

    raise ControlError(f"unsupported command: {command}")


async def _invoke_play_pause(atv: AppleTV) -> None:
    remote = atv.remote_control

    try:
        await remote.play_pause()
    except (pyatv_exceptions.CommandError, pyatv_exceptions.NotSupportedError) as exc:
        await _fallback_play_pause(atv, exc)
    except PYATV_ERROR as exc:
        raise ControlError(str(exc)) from exc


async def _fallback_play_pause(atv: AppleTV, original_exc: Exception) -> None:
    failure_message = str(original_exc) or "play/pause command failed"

    metadata = getattr(atv, "metadata", None)
    if metadata is None:
        raise ControlError(failure_message) from original_exc

    try:
        playing = await metadata.playing()
    except PYATV_ERROR as exc:  # pragma: no cover - defensive
        raise ControlError(failure_message) from exc

    state = getattr(playing, "device_state", None) or DeviceState.Idle
    remote = atv.remote_control

    try:
        if state == DeviceState.Playing:
            await remote.pause()
        else:
            await remote.play()
    except (pyatv_exceptions.CommandError, pyatv_exceptions.NotSupportedError) as exc:
        raise ControlError(str(exc)) from exc
    except PYATV_ERROR as exc:  # pragma: no cover - defensive
        raise ControlError(str(exc)) from exc


async def run_command_session(options: SessionOptions) -> int:
    """Maintain a persistent connection for command and power handling."""

    if options.mock:
        await _run_mock_session(options)
        return 0

    loop = asyncio.get_running_loop()

    storage: Optional[Storage] = None
    if options.use_storage:
        storage = await load_storage(loop, options.storage_path)

    configs = await scan_configs(
        DiscoveryOptions(
            timeout=5,
            protocol=options.protocol,
            identifier=None,
            storage_path=options.storage_path,
            use_storage=options.use_storage,
        ),
        storage=storage,
    )

    config = select_config(configs, options.identifier)
    if config is None:
        _emit_session_payload({"status": "error", "error": "device not found", "fatal": True})
        return 2

    try:
        atv = await _connect_device(config, loop, storage, protocol=options.protocol)
    except ControlError as exc:
        _emit_session_payload({"status": "error", "error": str(exc), "fatal": True})
        return 2

    _emit_session_payload(
        {
            "status": "ready",
            "identifier": config.identifier,
            "name": getattr(config, "name", None),
        }
    )

    try:
        graceful = await _session_loop(atv)
    finally:
        atv.close()

    return 0 if graceful else 1


async def _session_loop(atv: AppleTV) -> bool:
    loop = asyncio.get_running_loop()
    session_lock = asyncio.Lock()
    fatal = False
    while True:
        line = await loop.run_in_executor(None, sys.stdin.readline)
        if not line:
            break

        message = line.strip()
        if not message:
            continue

        try:
            payload = json.loads(message)
        except json.JSONDecodeError:
            _emit_session_payload({"status": "error", "error": "invalid json"})
            continue

        msg_type = payload.get("type")
        should_continue = True
        async with session_lock:
            if msg_type == "command":
                should_continue = await _session_handle_command(atv, payload)
            elif msg_type == "power":
                should_continue = await _session_handle_power(atv, payload)
            elif msg_type == "close":
                _emit_session_payload({"status": "closing"})
                break
            else:
                _emit_session_payload({"status": "error", "error": "unknown message type"})

        if not should_continue:
            fatal = True
            break

    return not fatal


async def _session_handle_command(atv: AppleTV, payload: dict) -> bool:
    command = payload.get("command")
    action_name = payload.get("action", "SingleTap")

    if not command:
        _emit_session_payload({"status": "error", "type": "command", "error": "missing command"})
        return True

    try:
        action = _parse_action(action_name)
        await _invoke_remote(atv, command.lower(), action)
    except ControlError as exc:
        _emit_session_payload(
            {
                "status": "error",
                "type": "command",
                "command": command,
                "error": str(exc),
            }
        )
        return True
    except PYATV_ERROR as exc:  # pragma: no cover - defensive
        _emit_session_payload(
            {
                "status": "error",
                "type": "command",
                "command": command,
                "error": str(exc),
                "fatal": True,
            }
        )
        return False

    _emit_session_payload(
        {
            "status": "ok",
            "type": "command",
            "command": command.lower(),
            "action": action.name,
        }
    )
    return True


async def _session_handle_power(atv: AppleTV, payload: dict) -> bool:
    action = payload.get("action")
    if not action:
        _emit_session_payload({"status": "error", "type": "power", "error": "missing action"})
        return True

    lower_action = str(action).lower()
    try:
        power = atv.power
        if lower_action == "on":
            await power.turn_on()
            result = {"power": "on"}
        elif lower_action == "off":
            await power.turn_off()
            result = {"power": "off"}
        elif lower_action == "status":
            state = await _resolve_power_state(atv, power)
            value = state.name if isinstance(state, PowerState) else str(state)
            result = {"power_state": value}
        else:
            raise ControlError(f"unknown power action: {action}")
    except ControlError as exc:
        _emit_session_payload(
            {
                "status": "error",
                "type": "power",
                "action": action,
                "error": str(exc),
            }
        )
        return True
    except PYATV_ERROR as exc:  # pragma: no cover - defensive
        _emit_session_payload(
            {
                "status": "error",
                "type": "power",
                "action": action,
                "error": str(exc),
                "fatal": True,
            }
        )
        return False

    response = {"status": "ok", "type": "power"}
    response.update(result)
    _emit_session_payload(response)
    return True


async def _resolve_power_state(atv: Any, power: Any = None) -> Any:
    """Return current power state safely without triggering concurrent Companion reads or hanging."""

    # 1. Check device config deep_sleep flag if available
    config = getattr(atv, "_config", None)
    if config is not None:
        with contextlib.suppress(BaseException):
            deep_sleep = getattr(config, "deep_sleep", None)
            if deep_sleep is True:
                return PowerState.Off
            if deep_sleep is False:
                return PowerState.On

    # 2. Check cached power_state on power object if present (non-blocking)
    if power is None:
        power = getattr(atv, "power", None)

    if power is not None:
        with contextlib.suppress(BaseException):
            raw_state = getattr(power, "_power_state", None)
            if raw_state is not None:
                state_str = str(getattr(raw_state, "name", raw_state)).lower()
                if "unknown" not in state_str and not state_str.endswith(".unknown"):
                    return raw_state

    # 3. For any active, connected session to a responsive Apple TV, power state is On
    return PowerState.On


async def _run_mock_session(options: SessionOptions) -> None:
    loop = asyncio.get_running_loop()
    power_state = "on"

    _emit_session_payload(
        {
            "status": "ready",
            "identifier": options.identifier,
            "mock": True,
        }
    )

    while True:
        line = await loop.run_in_executor(None, sys.stdin.readline)
        if not line:
            break

        message = line.strip()
        if not message:
            continue

        try:
            payload = json.loads(message)
        except json.JSONDecodeError:
            _emit_session_payload({"status": "error", "error": "invalid json"})
            continue

        msg_type = payload.get("type")
        if msg_type == "command":
            command = payload.get("command", "")
            action = str(payload.get("action", "SingleTap"))
            _emit_session_payload(
                {
                    "status": "ok",
                    "type": "command",
                    "command": command.lower(),
                    "action": action,
                    "mock": True,
                }
            )
        elif msg_type == "power":
            action = str(payload.get("action", "status")).lower()
            if action == "on":
                power_state = "on"
                response = {"power": "on"}
            elif action == "off":
                power_state = "off"
                response = {"power": "off"}
            else:
                response = {"power_state": power_state}
            result = {"status": "ok", "type": "power"}
            result.update(response)
            _emit_session_payload(result)
        elif msg_type == "close":
            _emit_session_payload({"status": "closing", "mock": True})
            break
        else:
            _emit_session_payload({"status": "error", "error": "unknown message type"})


def _emit_session_payload(payload: dict) -> None:
    print(json.dumps(payload, separators=(",", ":")), flush=True)
