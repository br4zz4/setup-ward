#!/usr/bin/env bash
# scopes.sh — export every scope of $SCOPES (one per line) to the job. A scope
# without values is a notice; a scope ward cannot read is an error.
set -euo pipefail

while IFS= read -r scope; do
  scope="$(printf '%s' "${scope}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "${scope}" ] || continue
  ward secrets --json "${scope}" | python3 "${EXPORT}" "${scope}"
done <<EOF
${SCOPES:-}
EOF
