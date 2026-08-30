import sys
from pathlib import Path

import tomlkit
from tomlkit.items import AoT, Table


def load(path: Path):
    return tomlkit.parse(path.read_text())


def merge(installed, declared, path: tuple[str, ...] = ()) -> None:
    for key, declared_value in declared.items():
        current_path = (*path, key)
        location = ".".join(current_path)

        if isinstance(declared_value, AoT):
            raise ValueError(f"managed arrays of tables are not supported: {location}")
        if key not in installed:
            installed.add(key, declared_value)
            continue

        installed_value = installed[key]
        if isinstance(declared_value, Table):
            if not isinstance(installed_value, Table):
                raise ValueError(f"managed table conflicts with a value: {location}")
            merge(installed_value, declared_value, current_path)
            continue
        if isinstance(installed_value, (Table, AoT)):
            raise ValueError(f"managed value conflicts with a table: {location}")
        installed[key] = declared_value


def main() -> None:
    installed_path, declared_path = map(Path, sys.argv[1:])
    installed = load(installed_path)
    declared = load(declared_path)
    merge(installed, declared)
    merged = tomlkit.dumps(installed)
    tomlkit.parse(merged)
    sys.stdout.write(merged)


if __name__ == "__main__":
    main()
