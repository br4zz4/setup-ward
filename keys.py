#!/usr/bin/env python3
"""keys — export the ward keys of a project as WARD_KEY_<NAMESPACE>[_RESTRICTED].

The env name follows ward's own derivation: every character outside [A-Za-z0-9]
becomes an underscore and the result is upper-cased. Keys are masked before they
are written. Environment: VAULT, KEY, RESTRICTED_KEY (optional), GITHUB_ENV.
"""

import os
import re
import sys

VAULT = os.environ.get("VAULT", "")
KEY = os.environ.get("KEY", "")
RESTRICTED = os.environ.get("RESTRICTED_KEY", "")


def env_name(vault, restricted=False):
    base = "WARD_KEY_" + re.sub(r"[^A-Za-z0-9]", "_", vault).upper()
    return base + "_RESTRICTED" if restricted else base


def main():
    if not VAULT:
        print("::error::vault is empty")
        return 1
    if not KEY:
        print("::error::key is empty: set the WARD_KEY_<NAMESPACE> secret of the repository")
        return 1
    path = os.environ.get("GITHUB_ENV")
    if not path:
        print("::error::GITHUB_ENV is not set")
        return 1
    entries = [(env_name(VAULT), KEY)]
    if RESTRICTED:
        entries.append((env_name(VAULT, True), RESTRICTED))
    with open(path, "a", encoding="utf-8") as handle:
        for name, value in entries:
            print(f"::add-mask::{value}")
            handle.write(f"{name}={value}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
