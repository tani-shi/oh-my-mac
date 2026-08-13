# /// script
# requires-python = ">=3.11"
# dependencies = ["tomlkit==0.15.1"]
# ///

import sys
from pathlib import Path

import tomlkit
from tomlkit.items import AoT, Table


def load(path: Path):
    return tomlkit.parse(path.read_text())


def main() -> None:
    installed_path, declared_path = map(Path, sys.argv[1:])
    installed = load(installed_path)
    declared = load(declared_path)

    for key, value in declared.items():
        if isinstance(value, (Table, AoT)):
            raise ValueError(f"{declared_path}: tables are not supported: {key}")
        if key in installed:
            if isinstance(installed[key], (Table, AoT)):
                raise ValueError(f"{installed_path}: managed key conflicts with a table: {key}")
            installed.remove(key)

    declared_text = tomlkit.dumps(declared)
    installed_text = tomlkit.dumps(installed)
    merged = declared_text + ("\n" + installed_text if installed_text else "")
    tomlkit.parse(merged)
    sys.stdout.write(merged)


if __name__ == "__main__":
    main()
