#!/usr/bin/env bash
# scopes.sh — export every scope of $SCOPES (one per line) to the job. A scope
# that does not exist or has no values is a notice; any other ward error fails.
set -euo pipefail

ERRORS="$(mktemp)"
trap 'rm -f "${ERRORS}"' EXIT

while IFS= read -r scope; do
  scope="$(printf '%s' "${scope}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "${scope}" ] || continue
  if ! ward secrets --json "${scope}" 2>"${ERRORS}" | python3 "${EXPORT}" "${scope}"; then
    if grep -q "key not found" "${ERRORS}"; then
      echo "::notice::${scope} does not exist in the vault"
      continue
    fi
    cat "${ERRORS}" >&2
    exit 1
  fi
done <<EOF
${SCOPES:-}
EOF
