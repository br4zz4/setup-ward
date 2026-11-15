#!/usr/bin/env python3
"""export — write the values of a ward scope to GITHUB_ENV, masked.

Reads the JSON object `ward secrets --json <scope>` prints on stdin. Every value
is masked line by line before it is written, and written with a random heredoc
delimiter so a multi-line value cannot inject another variable.

Usage: ward secrets --json <scope> | export.py <scope>
"""

import json
import os
import re
import secrets
import sys

NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def main(argv):
    scope = argv[1] if len(argv) > 1 else "scope"
    path = os.environ.get("GITHUB_ENV")
    if not path:
        print("::error::GITHUB_ENV is not set")
        return 1
    text = sys.stdin.read().strip()
    values = json.loads(text) if text else {}
    if not isinstance(values, dict):
        print(f"::error::{scope}: expected a JSON object")
        return 1
    if not values:
        print(f"::notice::{scope} has no values")
        return 0
    with open(path, "a", encoding="utf-8") as handle:
        for name in sorted(values):
            if not NAME.match(name):
                print(f"::error::{scope}: '{name}' is not a valid environment variable name")
                return 1
            value = "" if values[name] is None else str(values[name])
            for line in value.splitlines():
                if line.strip():
                    print(f"::add-mask::{line}")
            delimiter = "ward_" + secrets.token_hex(16)
            handle.write(f"{name}<<{delimiter}\n{value}\n{delimiter}\n")
    print(f"exported {len(values)} values from {scope}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
