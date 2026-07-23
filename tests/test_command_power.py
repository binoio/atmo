"""Tests for remote command and power CLI handlers."""

from __future__ import annotations

import contextlib
import io
import json
import unittest
from unittest.mock import AsyncMock, patch
from typing import Optional

from pyatv import exceptions as pyatv_exceptions
from pyatv.const import DeviceState, InputAction, PowerState, Protocol

from pybridge import cli


class FakeRemote:
    def __init__(self):
        self.calls = []
        self.play_pause_side_effect: Optional[Exception] = None

    async def home(self, action: InputAction) -> None:
        self.calls.append(("home", action))

    async def menu(self, action: InputAction) -> None:
        self.calls.append(("menu", action))

    async def select(self, action: InputAction) -> None:
        self.calls.append(("select", action))

    async def up(self, action: InputAction) -> None:
        self.calls.append(("up", action))

    async def down(self, action: InputAction) -> None:
        self.calls.append(("down", action))

    async def left(self, action: InputAction) -> None:
        self.calls.append(("left", action))

    async def right(self, action: InputAction) -> None:
        self.calls.append(("right", action))

    async def play_pause(self) -> None:
        if self.play_pause_side_effect is not None:
            raise self.play_pause_side_effect
        self.calls.append(("play_pause", None))

    async def play(self) -> None:
        self.calls.append(("play", None))

    async def pause(self) -> None:
        self.calls.append(("pause", None))


class FakePower:
    def __init__(self, property_style: bool = False):
        self.turn_on_called = False
        self.turn_off_called = False
        self.state = PowerState.On
        self.property_style = property_style

    async def turn_on(self) -> None:
        self.turn_on_called = True

    async def turn_off(self) -> None:
        self.turn_off_called = True

    async def _power_state_async(self) -> PowerState:
        return self.state

    @property
    def power_state(self):  # type: ignore[override]
        if self.property_style:
            return self.state
        return self._power_state_async


class FakeConfig:
    def __init__(self):
        self.identifier = "11223344-5566-7788-9900-112233445566"
        self.all_identifiers = [self.identifier, "00:11:22:33:44:55"]
        self.name = "Living Room"
        self.address = "10.0.0.10"


class FakeMetadata:
    def __init__(self) -> None:
        self.state = DeviceState.Paused

    async def playing(self):
        class _FakePlaying:
            def __init__(self, device_state: DeviceState) -> None:
                self.device_state = device_state

        return _FakePlaying(self.state)


class FakeAppleTV:
    def __init__(self, power: FakePower | None = None):
        self.remote_control = FakeRemote()
        self.power = power or FakePower()
        self.metadata = FakeMetadata()
        self.closed = False

    def close(self) -> None:
        self.closed = True


class CommandPowerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = FakeConfig()
        self.apple_tv = FakeAppleTV()

        self.scan_patch = patch(
            "pybridge.control.scan_configs",
            AsyncMock(return_value=[self.config]),
        )
        self.storage_patch = patch(
            "pybridge.control.load_storage",
            AsyncMock(return_value=None),
        )
        self.connect_patch = patch(
            "pybridge.control.connect",
            AsyncMock(return_value=self.apple_tv),
        )

    def test_home_command_invokes_remote(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            stack.enter_context(self.connect_patch)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = cli.main(
                    [
                        "command",
                        "--identifier",
                        "Living Room",
                        "--command",
                        "home",
                    ]
                )

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["status"], "ok")
        self.assertTrue(self.apple_tv.closed)
        self.assertEqual(self.apple_tv.remote_control.calls[0][0], "home")
        self.assertEqual(
            self.apple_tv.remote_control.calls[0][1], InputAction.SingleTap
        )

    def test_invalid_command_returns_error(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            stack.enter_context(self.connect_patch)

            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                exit_code = cli.main(
                    [
                        "command",
                        "--identifier",
                        "Living Room",
                        "--command",
                        "volume_up",
                    ]
                )

        self.assertEqual(exit_code, 2)
        self.assertIn("unsupported command", stderr.getvalue())

    def test_power_on_calls_turn_on(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            stack.enter_context(self.connect_patch)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = cli.main(
                    [
                        "power",
                        "--identifier",
                        "Living Room",
                        "--action",
                        "on",
                    ]
                )

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertTrue(self.apple_tv.power.turn_on_called)
        self.assertTrue(self.apple_tv.closed)
        self.assertEqual(payload["status"], "ok")

    def test_power_status_returns_state(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            stack.enter_context(self.connect_patch)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = cli.main(
                    [
                        "power",
                        "--identifier",
                        "Living Room",
                        "--action",
                        "status",
                    ]
                )

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["power_state"], PowerState.On.name)
        self.assertTrue(self.apple_tv.closed)

    def test_power_status_property_returns_state(self) -> None:
        self.apple_tv = FakeAppleTV(power=FakePower(property_style=True))

        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            connect_mock = stack.enter_context(self.connect_patch)
            connect_mock.return_value = self.apple_tv

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = cli.main(
                    [
                        "power",
                        "--identifier",
                        "Living Room",
                        "--action",
                        "status",
                    ]
                )

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["power_state"], PowerState.On.name)
        self.assertTrue(self.apple_tv.closed)

    def test_session_handles_multiple_requests(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            stack.enter_context(self.connect_patch)

            commands = "\n".join(
                [
                    json.dumps({"type": "command", "command": "home"}),
                    json.dumps({"type": "power", "action": "status"}),
                    json.dumps({"type": "close"}),
                    "",
                ]
            )

            stdin_buffer = io.StringIO(commands)
            stdout = io.StringIO()
            with patch("sys.stdin", stdin_buffer), contextlib.redirect_stdout(stdout):
                exit_code = cli.main(
                    [
                        "session",
                        "--identifier",
                        "Living Room",
                    ]
                )

        self.assertEqual(exit_code, 0)
        responses = [json.loads(line) for line in stdout.getvalue().splitlines()]
        self.assertGreaterEqual(len(responses), 3)
        self.assertEqual(responses[0]["status"], "ready")
        self.assertEqual(responses[1]["status"], "ok")
        self.assertEqual(responses[1]["command"], "home")
        self.assertEqual(responses[2]["power_state"], PowerState.On.name)
        self.assertTrue(self.apple_tv.closed)
        self.assertEqual(self.apple_tv.remote_control.calls[0][0], "home")

    def test_session_play_pause_falls_back_to_play(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            stack.enter_context(self.connect_patch)

            self.apple_tv.remote_control.play_pause_side_effect = pyatv_exceptions.CommandError(
                "Toggle not available"
            )
            self.apple_tv.metadata.state = DeviceState.Paused

            commands = "\n".join(
                [
                    json.dumps({"type": "command", "command": "play_pause"}),
                    json.dumps({"type": "close"}),
                    "",
                ]
            )

            stdin_buffer = io.StringIO(commands)
            stdout = io.StringIO()
            with patch("sys.stdin", stdin_buffer), contextlib.redirect_stdout(stdout):
                exit_code = cli.main(
                    [
                        "session",
                        "--identifier",
                        "Living Room",
                    ]
                )

        self.assertEqual(exit_code, 0)
        responses = [json.loads(line) for line in stdout.getvalue().splitlines()]
        self.assertGreaterEqual(len(responses), 2)
        self.assertEqual(responses[1]["status"], "ok")
        self.assertEqual(self.apple_tv.remote_control.calls[-1][0], "play")

    def test_session_play_pause_falls_back_to_pause(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            stack.enter_context(self.connect_patch)

            self.apple_tv.remote_control.play_pause_side_effect = pyatv_exceptions.CommandError(
                "Toggle not available"
            )
            self.apple_tv.metadata.state = DeviceState.Playing

            commands = "\n".join(
                [
                    json.dumps({"type": "command", "command": "play_pause"}),
                    json.dumps({"type": "close"}),
                    "",
                ]
            )

            stdin_buffer = io.StringIO(commands)
            stdout = io.StringIO()
            with patch("sys.stdin", stdin_buffer), contextlib.redirect_stdout(stdout):
                exit_code = cli.main(
                    [
                        "session",
                        "--identifier",
                        "Living Room",
                    ]
                )

        self.assertEqual(exit_code, 0)
        responses = [json.loads(line) for line in stdout.getvalue().splitlines()]
        self.assertGreaterEqual(len(responses), 2)
        self.assertEqual(responses[1]["status"], "ok")
        self.assertEqual(self.apple_tv.remote_control.calls[-1][0], "pause")

    def test_apply_protocol_takeover_prioritizes_companion(self) -> None:
        class MockAppleTV:
            def __init__(self) -> None:
                self._protocol_handlers = {
                    Protocol.MRP: "mrp_handler",
                    Protocol.Companion: "companion_handler",
                }
                self.takeover_calls = []

            def takeover(self, protocol, *interfaces) -> None:
                self.takeover_calls.append((protocol, interfaces))

        mock_atv = MockAppleTV()
        from pybridge.control import _apply_protocol_takeover
        from pyatv import interface

        _apply_protocol_takeover(mock_atv)
        self.assertEqual(len(mock_atv.takeover_calls), 1)
        self.assertEqual(mock_atv.takeover_calls[0][0], Protocol.Companion)
        self.assertIn(interface.RemoteControl, mock_atv.takeover_calls[0][1])

    def test_apply_protocol_takeover_uses_requested_protocol(self) -> None:
        class MockAppleTV:
            def __init__(self) -> None:
                self._protocol_handlers = {
                    Protocol.MRP: "mrp_handler",
                    Protocol.Companion: "companion_handler",
                    Protocol.AirPlay: "airplay_handler",
                }
                self.takeover_calls = []

            def takeover(self, protocol, *interfaces) -> None:
                self.takeover_calls.append((protocol, interfaces))

        mock_atv = MockAppleTV()
        from pybridge.control import _apply_protocol_takeover
        from pyatv import interface

        _apply_protocol_takeover(mock_atv, requested_protocol="AirPlay")
        self.assertEqual(len(mock_atv.takeover_calls), 1)
        self.assertEqual(mock_atv.takeover_calls[0][0], Protocol.AirPlay)
        self.assertIn(interface.RemoteControl, mock_atv.takeover_calls[0][1])

    def test_command_with_protocol_option(self) -> None:
        with contextlib.ExitStack() as stack:
            stack.enter_context(self.scan_patch)
            stack.enter_context(self.storage_patch)
            stack.enter_context(self.connect_patch)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                exit_code = cli.main(
                    [
                        "command",
                        "--identifier",
                        "Living Room",
                        "--command",
                        "up",
                        "--protocol",
                        "Companion",
                    ]
                )

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["status"], "ok")


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
