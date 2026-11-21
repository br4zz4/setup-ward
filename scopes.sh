#!/usr/bin/env bash
# scopes.sh — export every scope of $SCOPES (one per line) to the job. A scope
# that does not exist or has no values is a notice; any other ward error fails.
set -euo pipefail

key_name() {
  printf 'WARD_KEY_%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_' | tr 'a-z' 'A-Z')"
}

KEYENV=()
if [ -n "${VAULT:-}" ] && [ -n "${KEY:-}" ]; then
  KEYENV+=("$(key_name "${VAULT}")=${KEY}")
  if [ -n "${RESTRICTED_KEY:-}" ]; then
    KEYENV+=("$(key_name "${VAULT}")_RESTRICTED=${RESTRICTED_KEY}")
  fi
fi

ERRORS="$(mktemp)"
trap 'rm -f "${ERRORS}"' EXIT

while IFS= read -r scope; do
  scope="$(printf '%s' "${scope}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "${scope}" ] || continue
  if ! env ${KEYENV[@]+"${KEYENV[@]}"} ward secrets --json "${scope}" 2>"${ERRORS}" | python3 "${EXPORT}" "${scope}"; then
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
