"""Command-line interface for the pyatv Swift bridge."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from dataclasses import asdict, is_dataclass
from typing import Any, Callable, Coroutine, List, Optional

from pyatv import exceptions as pyatv_exceptions
from pyatv.const import Protocol
PYATV_ERROR = getattr(
    pyatv_exceptions,
    "PyatvError",
    getattr(pyatv_exceptions, "PyATVError", Exception),
)

from . import discovery
from .control import (
    CommandOptions,
    ControlError,
    PowerOptions,
    SessionOptions,
    execute_command,
    execute_power,
    run_command_session,
)
from .pairing import (
    DEFAULT_PIN,
    PairingError,
    PairingOptions,
    PairingResult,
    PinRequiredResult,
    UnpairOptions,
    create_pairing_session,
    pair_device,
    unpair_device,
)
from .storage import StorageError, clear_storage

CommandHandler = Callable[[argparse.Namespace], Coroutine[Any, Any, int]]


class CLIError(Exception):
    """Base error raised by the bridge CLI."""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pybridge",
        description="Python bridge that exposes pyatv functionality to the Swift macOS app.",
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Use deterministic mock responses instead of contacting devices.",
    )
    parser.add_argument(
        "--storage",
        metavar="PATH",
        help="Optional path to pyatv credential storage (defaults to ~/.pyatv.conf).",
    )
    parser.add_argument(
        "--no-storage",
        action="store_true",
        help="Disable storage loading even if a default is available.",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    scan_parser = subparsers.add_parser("scan", help="Discover Apple TV devices")
    scan_parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="Scan timeout in seconds (default: 5).",
    )
    scan_parser.add_argument(
        "--protocol",
        choices=[name for name in Protocol.__members__.keys()],
        help="Filter scan to a specific protocol.",
    )
    scan_parser.add_argument(
        "--identifier",
        help="Only return a device matching a specific identifier.",
    )
    scan_parser.set_defaults(handler=_handle_scan)

    pair_parser = subparsers.add_parser("pair", help="Pair a device")
    pair_parser.add_argument(
        "--identifier",
        required=True,
        help="Identifier (id/name/address) of the device to pair.",
    )
    pair_parser.add_argument(
        "--protocol",
        required=True,
        choices=[name for name in Protocol.__members__.keys()],
        help="Protocol to pair (e.g. Companion, AirPlay).",
    )
    pair_parser.add_argument(
        "--pin",
        help="PIN code to complete pairing when required.",
    )
    pair_parser.add_argument(
        "--display-name",
        default="pyatv-bridge",
        help="Friendly name presented during pairing.",
    )
    pair_parser.add_argument(
        "--interactive",
        action="store_true",
        help="Enable interactive pairing flow waiting for a PIN on stdin.",
    )
    pair_parser.set_defaults(handler=_handle_pair)

    unpair_parser = subparsers.add_parser("unpair", help="Remove stored credentials for a device")
    unpair_parser.add_argument(
        "--identifier",
        required=True,
        help="Identifier (id/name/address) of the device to unpair.",
    )
    unpair_parser.add_argument(
        "--protocol",
        required=True,
        choices=[name for name in Protocol.__members__.keys()],
        help="Protocol to unpair (e.g. Companion, AirPlay).",
    )
    unpair_parser.set_defaults(handler=_handle_unpair)

    command_parser = subparsers.add_parser(
        "command", help="Send a remote control command"
    )
    command_parser.add_argument(
        "--identifier",
        required=True,
        help="Identifier (id/name/address) of the device to control.",
    )
    command_parser.add_argument(
        "--command",
        required=True,
        help="Remote command (home/menu/select/play_pause/up/down/left/right).",
    )
    command_parser.add_argument(
        "--action",
        default="SingleTap",
        help="Input action for directional/menu/home/select commands (SingleTap, DoubleTap, Hold).",
    )
    command_parser.add_argument(
        "--protocol",
        choices=[name for name in Protocol.__members__.keys()],
        help="Filter control to a specific protocol (e.g. Companion).",
    )
    command_parser.set_defaults(handler=_handle_command)

    power_parser = subparsers.add_parser("power", help="Send a power action")
    power_parser.add_argument(
        "--identifier",
        required=True,
        help="Identifier (id/name/address) of the device to control.",
    )
    power_parser.add_argument(
        "--action",
        required=True,
        choices=["on", "off", "status"],
        help="Power action to perform.",
    )
    power_parser.add_argument(
        "--protocol",
        choices=[name for name in Protocol.__members__.keys()],
        help="Filter power action to a specific protocol (e.g. Companion).",
    )
    power_parser.set_defaults(handler=_handle_power)

    clear_parser = subparsers.add_parser(
        "clear-storage", help="Remove stored pyatv credentials"
    )
    clear_parser.set_defaults(handler=_handle_clear_storage)

    session_parser = subparsers.add_parser(
        "session",
        help="Maintain a persistent connection for commands and power",
    )
    session_parser.add_argument(
        "--identifier",
        required=True,
        help="Identifier (id/name/address) of the device to control.",
    )
    session_parser.add_argument(
        "--protocol",
        choices=[name for name in Protocol.__members__.keys()],
        help="Filter session control to a specific protocol (e.g. Companion).",
    )
    session_parser.set_defaults(handler=_handle_session)

    return parser


async def _handle_scan(args: argparse.Namespace) -> int:
    if args.mock:
        devices = discovery.mock_devices()
    else:
        options = discovery.DiscoveryOptions(
            timeout=args.timeout,
            protocol=args.protocol,
            identifier=args.identifier,
            storage_path=args.storage,
            use_storage=not args.no_storage,
        )
        try:
            devices = await discovery.discover_devices(options)
        except StorageError as exc:
            raise CLIError(str(exc)) from exc
        except ValueError as exc:
            raise CLIError(str(exc)) from exc

    print(json.dumps({"devices": devices}, separators=(",", ":")))
    return 0


async def _handle_pair(args: argparse.Namespace) -> int:
    options = PairingOptions(
        identifier=args.identifier,
        protocol=args.protocol,
        pin=args.pin,
        display_name=args.display_name,
        storage_path=args.storage,
        use_storage=not args.no_storage,
        mock=args.mock,
        interactive=args.interactive,
    )

    if options.interactive and options.pin is None and not options.mock:
        return await _handle_pair_interactive(options)

    try:
        result = await pair_device(options)
    except StorageError as exc:
        raise CLIError(str(exc)) from exc
    except PairingError as exc:
        raise CLIError(str(exc)) from exc

    payload = asdict(result) if is_dataclass(result) else result
    print(json.dumps(payload, separators=(",", ":")))
    return 0


async def _handle_pair_interactive(options: PairingOptions) -> int:
    try:
        session = await create_pairing_session(options)
    except StorageError as exc:
        raise CLIError(str(exc)) from exc
    except PairingError as exc:
        raise CLIError(str(exc)) from exc

    pairing = session.pairing
    config = session.config
    protocol = session.protocol
    storage = session.storage

    try:
        await pairing.begin()

        pin_code: Optional[str] = None
        if pairing.device_provides_pin:
            payload = PinRequiredResult(
                status="pin_required",
                identifier=config.identifier,
                protocol=protocol.name,
                message="Enter the PIN shown on the Apple TV screen.",
            )
            print(json.dumps(asdict(payload), separators=(",", ":")), flush=True)
            pin_code = await _read_pin_from_stdin()
            if pin_code is None:
                raise PairingError("pin entry aborted")
        else:
            pin_code = DEFAULT_PIN

        pairing.pin(pin_code)
        await pairing.finish()

        if not pairing.has_paired:
            raise PairingError("pairing failed")

        if storage is not None:
            await storage.save()

        payload = PairingResult(
            status="paired",
            identifier=config.identifier,
            protocol=protocol.name,
            credentials_saved=True,
            credentials=pairing.service.credentials,
        )
        print(json.dumps(asdict(payload), separators=(",", ":")), flush=True)
        return 0
    except PYATV_ERROR as exc:
        raise CLIError(str(exc)) from exc
    except PairingError as exc:
        raise CLIError(str(exc)) from exc
    finally:
        await pairing.close()


async def _read_pin_from_stdin() -> Optional[str]:
    loop = asyncio.get_running_loop()
    try:
        line = await loop.run_in_executor(None, sys.stdin.readline)
    except Exception:  # pragma: no cover - defensive
        return None

    if not line:
        return None

    pin = line.strip()
    return pin or None


async def _handle_unpair(args: argparse.Namespace) -> int:
    options = UnpairOptions(
        identifier=args.identifier,
        protocol=args.protocol,
        storage_path=args.storage,
        use_storage=not args.no_storage,
        mock=args.mock,
    )

    try:
        result = await unpair_device(options)
    except StorageError as exc:
        raise CLIError(str(exc)) from exc
    except PairingError as exc:
        raise CLIError(str(exc)) from exc

    payload = asdict(result) if is_dataclass(result) else result
    print(json.dumps(payload, separators=(",", ":")))
    return 0


async def _handle_command(args: argparse.Namespace) -> int:
    options = CommandOptions(
        identifier=args.identifier,
        command=args.command,
        action=args.action,
        protocol=args.protocol,
        storage_path=args.storage,
        use_storage=not args.no_storage,
        mock=args.mock,
    )

    try:
        result = await execute_command(options)
    except (StorageError, ControlError) as exc:
        raise CLIError(str(exc)) from exc

    print(json.dumps(result, separators=(",", ":")))
    return 0


async def _handle_power(args: argparse.Namespace) -> int:
    options = PowerOptions(
        identifier=args.identifier,
        action=args.action,
        protocol=args.protocol,
        storage_path=args.storage,
        use_storage=not args.no_storage,
        mock=args.mock,
    )

    try:
        result = await execute_power(options)
    except (StorageError, ControlError) as exc:
        raise CLIError(str(exc)) from exc

    print(json.dumps(result, separators=(",", ":")))
    return 0


async def _handle_session(args: argparse.Namespace) -> int:
    options = SessionOptions(
        identifier=args.identifier,
        protocol=args.protocol,
        storage_path=args.storage,
        use_storage=not args.no_storage,
        mock=args.mock,
    )

    try:
        return await run_command_session(options)
    except (StorageError, ControlError) as exc:
        raise CLIError(str(exc)) from exc


async def _handle_clear_storage(args: argparse.Namespace) -> int:
    if args.mock:
        payload = {
            "status": "cleared",
            "cleared": True,
            "path": args.storage or "mock-storage",
        }
    else:
        loop = asyncio.get_running_loop()
        try:
            result = await clear_storage(loop, args.storage)
        except StorageError as exc:
            raise CLIError(str(exc)) from exc

        payload = asdict(result)

    print(json.dumps(payload, separators=(",", ":")))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    handler: CommandHandler = getattr(args, "handler", None)
    if handler is None:
        parser.print_help(sys.stderr)
        return 1

    try:
        return asyncio.run(handler(args))
    except CLIError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("aborted", file=sys.stderr)
        return 130


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
