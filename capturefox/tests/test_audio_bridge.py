"""Test the virtual input lifecycle without changing desktop audio."""
# FILE: capturefox/tests/test_audio_bridge.py

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "audio_bridge", ROOT / "tools" / "audio-bridge.py"
)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class FakePactl:
    def __init__(self):
        self.entries = {}
        self.default = "speaker"
        self.next_id = 10
        self.unloaded = []
        self.fail_load = False

    def __call__(self, *args):
        if args == ("get-default-sink",):
            return self.default
        if args == ("list", "short", "modules"):
            return "\n".join(
                f"{key}\t{name}\t{arguments}\t"
                for key, (name, arguments) in self.entries.items()
            )
        if args[0] == "load-module":
            if self.fail_load:
                raise bridge.BridgeError("Mock loading failure.")
            identifier = self.next_id
            self.next_id += 1
            self.entries[identifier] = (args[1], " ".join(args[2:]))
            return str(identifier)
        if args[0] == "unload-module":
            identifier = int(args[1])
            self.unloaded.append(identifier)
            del self.entries[identifier]
            return ""
        raise AssertionError(args)


class AudioBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="audio-test-", dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.fake = FakePactl()
        self.mock = patch.object(bridge, "pactl", self.fake)
        self.mock.start()
        self.addCleanup(self.mock.stop)

    def test_start_and_stop_are_idempotent(self):
        self.assertEqual(bridge.operate("start", self.directory)["action"], "started")
        self.assertEqual(bridge.operate("start", self.directory)["action"],
                         "already_started")
        self.assertEqual(len(self.fake.entries), 1)
        self.assertTrue(bridge.operate("status", self.directory)["active"])
        self.assertEqual(bridge.operate("stop", self.directory)["action"], "stopped")
        self.assertEqual(bridge.operate("stop", self.directory)["action"],
                         "already_stopped")
        self.assertEqual(self.fake.unloaded, [10])

    def test_reused_id_does_not_unload_another_module(self):
        bridge.operate("start", self.directory)
        self.fake.entries[10] = ("module-null-sink", "sink_name=other")
        self.assertFalse(bridge.operate("status", self.directory)["active"])
        bridge.operate("stop", self.directory)
        self.assertEqual(self.fake.unloaded, [])
        self.assertIn(10, self.fake.entries)

    def test_exact_source_name_required(self):
        bridge.operate("start", self.directory)
        self.fake.entries[10] = (
            bridge.MODULE, "master=speaker.monitor source_name=captura_system_audio_extra"
        )
        bridge.operate("stop", self.directory)
        self.assertEqual(self.fake.unloaded, [])

    def test_default_change_reconnects_only_owned_module(self):
        bridge.operate("start", self.directory)
        self.fake.entries[4] = ("module-null-sink", "sink_name=unrelated")
        self.fake.default = "headset"
        self.assertTrue(bridge.operate("status", self.directory)["needs_reconnect"])
        result = bridge.operate("start", self.directory)
        self.assertEqual(result["action"], "reconnected")
        self.assertEqual(result["master"], "headset.monitor")
        self.assertEqual(self.fake.unloaded, [10])
        self.assertIn(4, self.fake.entries)
        self.assertEqual(self.fake.default, "headset")

    def test_load_failure_retains_state_for_recovery(self):
        bridge.operate("start", self.directory)
        previous = bridge.read_state(self.directory)
        self.fake.default = "headset"
        self.fake.fail_load = True
        with self.assertRaises(bridge.BridgeError):
            bridge.operate("start", self.directory)
        self.assertEqual(bridge.read_state(self.directory), previous)
        self.assertFalse(bridge.operate("status", self.directory)["active"])
        self.fake.fail_load = False
        self.assertTrue(bridge.operate("start", self.directory)["active"])

    def test_state_write_failure_removes_new_module(self):
        with patch.object(bridge, "write_state", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                bridge.operate("start", self.directory)
        self.assertEqual(self.fake.entries, {})
        self.assertEqual(self.fake.unloaded, [10])

    def test_unknown_same_name_module_is_not_adopted(self):
        self.fake.entries[7] = (
            bridge.MODULE, "master=speaker.monitor source_name=captura_system_audio"
        )
        with self.assertRaises(bridge.BridgeError):
            bridge.operate("start", self.directory)
        self.assertEqual(self.fake.unloaded, [])

    def test_symlink_state_rejected(self):
        target = self.directory / "other.json"
        target.write_text("{}")
        (self.directory / "state.json").symlink_to(target)
        with self.assertRaises(bridge.BridgeError):
            bridge.read_state(self.directory)

    def test_atomic_state_is_private(self):
        bridge.operate("start", self.directory)
        self.assertEqual((self.directory / "state.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.directory.glob("state-*")), [])

    def test_subprocess_is_argv_only(self):
        with patch.object(bridge.subprocess, "run") as run:
            run.return_value.stdout = "ok\n"
            self.mock.stop()
            self.assertEqual(bridge.pactl("get-default-sink"), "ok")
            self.mock.start()
            run.assert_called_once_with(
                ["pactl", "get-default-sink"], capture_output=True,
                text=True, check=True, timeout=15,
            )


if __name__ == "__main__":
    unittest.main()
