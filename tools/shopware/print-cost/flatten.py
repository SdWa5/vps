"""Resolve an OrcaSlicer system profile's `inherits` chain into one flat JSON for the CLI.

usage: flatten.py PROFILES_DIR KIND NAME OUT [--printer SYSTEM_PRINTER]

KIND is machine, process or filament, NAME a system preset of that kind. The
CLI refuses a process or filament whose compatible_printers does not name the
machine (error -17), and a machine preset under its own system name clashes
with the system copy. So a machine is written as a user preset that inherits
the system one, and a process or filament is made compatible with the system
printer named by --printer and with that user machine.
"""
import json
import pathlib
import sys

USER_MACHINE = "flat machine"


def index(root, kind):
    presets = {}
    for path in sorted(pathlib.Path(root).rglob("*.json")):
        if path.parent.name != kind:
            continue
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if isinstance(data, dict) and "name" in data:
            presets.setdefault(data["name"], data)
    return presets


def resolve(presets, name):
    data = dict(presets[name])
    parent = data.pop("inherits", None)
    return {**resolve(presets, parent), **data} if parent else data


def flatten(presets, kind, name, printer=None):
    flat = resolve(presets, name)
    flat.pop("instantiation", None)
    flat.update({"from": "User", "type": kind, "version": flat.get("version", "2.4.0.0")})
    if kind == "machine":
        flat.update({"name": USER_MACHINE, "inherits": name})
    else:
        flat["name"] = name
        if printer:
            flat["compatible_printers"] = [printer, USER_MACHINE]
    return flat


def main(argv):
    if len(argv) not in (5, 7) or (len(argv) == 7 and argv[5] != "--printer"):
        sys.exit(__doc__)
    root, kind, name, out = argv[1:5]
    printer = argv[6] if len(argv) == 7 else None
    flat = flatten(index(root, kind), kind, name, printer)
    pathlib.Path(out).write_text(json.dumps(flat, indent=1))
    print(kind, name, len(flat), "keys")


if __name__ == "__main__":
    main(sys.argv)
