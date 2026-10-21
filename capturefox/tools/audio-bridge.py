#!/usr/bin/env python3
"""Manage an owned virtual system-audio input without changing defaults.
FILE: capturefox/tools/audio-bridge.py

Usage: python3 audio-bridge.py {--start|--status|--stop} [--json]
"""

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import tempfile

SOURCE = "captura_system_audio"
MODULE = "module-remap-source"


class BridgeError(Exception):
    """An operation could not be completed safely."""


def pactl(*arguments):
    try:
        result = subprocess.run(
            ["pactl", *arguments], capture_output=True, text=True,
            check=True, timeout=15,
        )
    except (OSError, subprocess.SubprocessError) as error:
        detail = getattr(error, "stderr", None) or str(error)
        raise BridgeError(f"pactl failed: {detail.strip()}") from error
    return result.stdout.strip()


def modules():
    entries = {}
    for line in pactl("list", "short", "modules").splitlines():
        fields = line.split("\t")
        if len(fields) >= 3 and fields[0].isdigit():
            entries[int(fields[0])] = (fields[1], fields[2])
    return entries


def arguments_for(entry):
    try:
        return dict(
            item.split("=", 1) for item in shlex.split(entry[1])
            if "=" in item
        )
    except ValueError as error:
        raise BridgeError("Invalid module arguments.") from error


def owned(entry, state):
    if entry is None or entry[0] != MODULE:
        return False
    args = arguments_for(entry)
    return (args.get("source_name") == SOURCE
            and args.get("master") == state["master"])


def secure_directory(path, uid):
    info = path.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != uid
            or info.st_mode & 0o022):
        raise BridgeError(f"Unsafe runtime directory: {path}")


def runtime_directory():
    uid = os.getuid()
    if uid == 0:
        raise BridgeError("Run this tool as your desktop user, not root.")
    supplied = os.environ.get("XDG_RUNTIME_DIR")
    base = Path(supplied) if supplied else Path(f"/run/user/{uid}")
    if not base.is_absolute():
        raise BridgeError("XDG_RUNTIME_DIR must be absolute.")
    secure_directory(base, uid)
    directory = base / "captura-audio"
    try:
        directory.mkdir(mode=0o700)
    except FileExistsError:
        pass
    secure_directory(directory, uid)
    return directory


def secure_file(path):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o077):
        raise BridgeError(f"Unsafe runtime file: {path.name}")


@contextlib.contextmanager
def locked(directory):
    path = directory / "lock"
    secure_file(path)
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077):
            raise BridgeError("Unsafe lock file.")
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        os.close(descriptor)


def read_state(directory):
    path = directory / "state.json"
    secure_file(path)
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return None
    try:
        with os.fdopen(descriptor) as stream:
            state = json.load(stream)
    except (ValueError, TypeError) as error:
        raise BridgeError("Invalid state file.") from error
    if (not isinstance(state, dict) or state.get("uid") != os.getuid()
            or type(state.get("module_id")) is not int
            or not isinstance(state.get("master"), str)
            or not state["master"].endswith(".monitor")):
        raise BridgeError("Invalid state ownership or module information.")
    return state


def write_state(directory, state):
    secure_file(directory / "state.json")
    descriptor, name = tempfile.mkstemp(prefix="state-", dir=directory)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(state, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, directory / "state.json")
    finally:
        if os.path.exists(name):
            os.unlink(name)


def clear_state(directory):
    path = directory / "state.json"
    secure_file(path)
    path.unlink(missing_ok=True)


def unload_owned(state):
    # Re-read immediately before unloading; an old module ID may be reused.
    current = modules().get(state["module_id"])
    if not owned(current, state):
        return False
    pactl("unload-module", str(state["module_id"]))
    return True


def describe(state, inventory, default):
    active = bool(state and owned(inventory.get(state["module_id"]), state))
    return {
        "active": active,
        "source_name": SOURCE,
        "device_label": "CaptureFox_System_Audio",
        "module_id": state["module_id"] if active else None,
        "master": state["master"] if active else None,
        "default_sink": default,
        "needs_reconnect": bool(active and state["master"] != default + ".monitor"),
    }


def operate(command, directory):
    with locked(directory):
        state = read_state(directory)
        inventory = modules()
        default = pactl("get-default-sink")
        if not default or "\n" in default:
            raise BridgeError("No valid default output device was found.")
        result = describe(state, inventory, default)
        if command == "status":
            return {"action": "status", **result}
        if command == "stop":
            removed = bool(state and unload_owned(state))
            clear_state(directory)
            return {"action": "stopped" if removed else "already_stopped",
                    **describe(None, {}, default)}
        if result["active"] and not result["needs_reconnect"]:
            return {"action": "already_started", **result}
        # Refuse same-name modules not represented by our validated state.
        for identifier, entry in inventory.items():
            if arguments_for(entry).get("source_name") == SOURCE:
                if not (state and identifier == state["module_id"]
                        and owned(entry, state)):
                    raise BridgeError("The virtual input name is already in use.")
        reconnect = result["active"]
        if reconnect and not unload_owned(state):
            raise BridgeError("The previous module changed; retry start.")
        master = default + ".monitor"
        identifier = pactl(
            "load-module", MODULE, f"master={master}",
            f"source_name={SOURCE}",
            "source_properties=device.description=CaptureFox_System_Audio",
        )
        if not identifier.isdigit():
            raise BridgeError("pactl returned an invalid module ID.")
        new_state = {"uid": os.getuid(), "module_id": int(identifier),
                     "master": master}
        try:
            new_inventory = modules()
            if not owned(new_inventory.get(int(identifier)), new_state):
                raise BridgeError("The new module could not be verified.")
            write_state(directory, new_state)
        except (BridgeError, OSError):
            unload_owned(new_state)
            raise
        return {"action": "reconnected" if reconnect else "started",
                **describe(new_state, new_inventory, default)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    for command in ("start", "status", "stop"):
        actions.add_argument(f"--{command}", action="store_const",
                             dest="command", const=command)
    parser.add_argument("--json", action="store_true", dest="as_json")
    options = parser.parse_args()
    try:
        result = operate(options.command, runtime_directory())
    except (BridgeError, OSError) as error:
        if options.as_json:
            print(json.dumps({"ok": False, "error": str(error)}))
        else:
            print(f"ERROR: {error} -abort", file=sys.stderr)
        return 1
    result = {"ok": True, **result}
    print(json.dumps(result) if options.as_json else
          f"{result['action']}: {SOURCE}; active={result['active']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
