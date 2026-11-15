#!/bin/sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
ko() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }

check() {
  if [ "$2" = "$3" ]; then ok "$1"; else ko "$1" "expected [$2] got [$3]"; fi
}

contains() {
  case "$3" in *"$2"*) ok "$1" ;; *) ko "$1" "missing [$2] in [$3]" ;; esac
}

lacks() {
  case "$3" in *"$2"*) ko "$1" "unexpected [$2] in [$3]" ;; *) ok "$1" ;; esac
}

PARSE="$TMP/parse.py"
cat > "$PARSE" <<'PY'
import json
import sys

lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
if lines and lines[-1] == "":
    lines.pop()
result = {}
delimiters = []
i = 0
while i < len(lines):
    head, sep, delim = lines[i].partition("<<")
    if not sep:
        print("MALFORMED:" + lines[i])
        sys.exit(2)
    i += 1
    body = []
    while i < len(lines) and lines[i] != delim:
        body.append(lines[i])
        i += 1
    if i >= len(lines):
        print("UNTERMINATED:" + head)
        sys.exit(2)
    i += 1
    result[head] = "\n".join(body)
    delimiters.append(delim)
print(json.dumps({"vars": result, "delims": delimiters}, sort_keys=True))
PY

field() {
  python3 -c '
import json, sys
d = json.loads(sys.argv[1])
print(json.dumps(d[sys.argv[2]], sort_keys=True))
' "$1" "$2"
}

run_export() {
  ENVF="$TMP/env"
  : > "$ENVF"
  OUT="$(printf '%s' "$2" | GITHUB_ENV="$ENVF" python3 "$ROOT/export.py" "$1" 2>&1)"
  RC=$?
}

parsed() { python3 "$PARSE" "$ENVF"; }

run_export acme '{"A":"one","B":"two"}'
check "export: exit 0" 0 "$RC"
P="$(parsed)"
check "export: variables written" '{"A": "one", "B": "two"}' "$(field "$P" vars)"
contains "export: summary" "exported 2 values from acme" "$OUT"
contains "export: masks A" "::add-mask::one" "$OUT"
contains "export: masks B" "::add-mask::two" "$OUT"
check "export: delimiters differ" 2 "$(python3 -c 'import json,sys; print(len(set(json.loads(sys.argv[1]))))' "$(field "$P" delims)")"
check "export: delimiter prefix" 2 "$(python3 -c 'import json,sys; print(sum(d.startswith("ward_") for d in json.loads(sys.argv[1])))' "$(field "$P" delims)")"

run_export acme '{"M":"l1\nl2\n\nl4"}'
P="$(parsed)"
check "export: multiline preserved" '{"M": "l1\nl2\n\nl4"}' "$(field "$P" vars)"
contains "export: masks line 1" "::add-mask::l1" "$OUT"
contains "export: masks line 2" "::add-mask::l2" "$OUT"
contains "export: masks line 4" "::add-mask::l4" "$OUT"
lacks "export: skips empty line mask" "::add-mask::
" "$OUT"

run_export acme '{}'
check "export: empty object exit" 0 "$RC"
contains "export: empty object notice" "::notice::acme has no values" "$OUT"
check "export: empty object leaves env" 0 "$(wc -c < "$ENVF" | tr -d ' ')"

run_export acme ''
check "export: empty stdin exit" 0 "$RC"
contains "export: empty stdin notice" "::notice::acme has no values" "$OUT"
check "export: empty stdin leaves env" 0 "$(wc -c < "$ENVF" | tr -d ' ')"

run_export acme '{"BAD-NAME":"secretvalue"}'
check "export: hyphen name exit" 1 "$RC"
contains "export: hyphen name error" "::error::" "$OUT"
check "export: hyphen name not written" 0 "$(wc -c < "$ENVF" | tr -d ' ')"

run_export acme '{"1X":"secretvalue"}'
check "export: digit name exit" 1 "$RC"
contains "export: digit name error" "::error::" "$OUT"
check "export: digit name not written" 0 "$(wc -c < "$ENVF" | tr -d ' ')"

run_export acme '["a","b"]'
check "export: list exit" 1 "$RC"

OUT="$(printf '{"A":"1"}' | env -u GITHUB_ENV python3 "$ROOT/export.py" acme 2>&1)"
check "export: missing GITHUB_ENV exit" 1 "$?"

run_export acme '{"A":"x\nX=1\nward_abc\nY=2","B":"ward_deadbeef\nZ=3"}'
P="$(parsed)"
check "export: injection yields only declared keys" '["A", "B"]' "$(python3 -c 'import json,sys; print(json.dumps(sorted(json.loads(sys.argv[1]))))' "$(field "$P" vars)")"
check "export: injected value intact" '{"A": "x\nX=1\nward_abc\nY=2", "B": "ward_deadbeef\nZ=3"}' "$(field "$P" vars)"

run_export acme '{"N":null}'
P="$(parsed)"
check "export: null becomes empty" '{"N": ""}' "$(field "$P" vars)"

run_keys() {
  ENVF="$TMP/env"
  : > "$ENVF"
  OUT="$(env -u KEY -u RESTRICTED_KEY -u VAULT GITHUB_ENV="$ENVF" "$@" python3 "$ROOT/keys.py" 2>&1)"
  RC=$?
}

run_keys VAULT=has_warranty KEY=k1
check "keys: exit 0" 0 "$RC"
check "keys: env file" "WARD_KEY_HAS_WARRANTY=k1" "$(cat "$ENVF")"
contains "keys: mask" "::add-mask::k1" "$OUT"

run_keys VAULT=has_warranty KEY=k1 RESTRICTED_KEY=k2
check "keys: restricted env file" "WARD_KEY_HAS_WARRANTY=k1
WARD_KEY_HAS_WARRANTY_RESTRICTED=k2" "$(cat "$ENVF")"
contains "keys: mask k1" "::add-mask::k1" "$OUT"
contains "keys: mask k2" "::add-mask::k2" "$OUT"

run_keys VAULT=my-app.x KEY=k1
check "keys: sanitized dash dot" "WARD_KEY_MY_APP_X=k1" "$(cat "$ENVF")"

run_keys "VAULT=my::app" KEY=k1
check "keys: sanitized colons" "WARD_KEY_MY__APP=k1" "$(cat "$ENVF")"

run_keys VAULT=v KEY=
check "keys: empty key exit" 1 "$RC"
contains "keys: empty key error" "::error::" "$OUT"
check "keys: empty key writes nothing" 0 "$(wc -c < "$ENVF" | tr -d ' ')"

run_keys VAULT= KEY=k1
check "keys: empty vault exit" 1 "$RC"
check "keys: empty vault writes nothing" 0 "$(wc -c < "$ENVF" | tr -d ' ')"

BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/ward" <<'EOF'
#!/bin/sh
echo "$*" >> "$WARD_LOG"
[ "$1" = secrets ] && [ "$2" = --json ] || exit 9
if [ "$3" = "${WARD_FAIL:-}" ]; then
  exit 1
fi
printf '{"V_%s":"val-%s"}' "$3" "$3"
EOF
chmod +x "$BIN/ward"

run_scopes() {
  ENVF="$TMP/env"
  : > "$ENVF"
  WARD_LOG="$TMP/ward.log"
  : > "$WARD_LOG"
  OUT="$(PATH="$BIN:$PATH" WARD_LOG="$WARD_LOG" WARD_FAIL="$2" GITHUB_ENV="$ENVF" EXPORT="$ROOT/export.py" SCOPES="$1" bash "$ROOT/scopes.sh" 2>&1)"
  RC=$?
}

NL='
'
run_scopes "  alpha  ${NL}${NL}beta${NL}   ${NL}gamma" ""
check "scopes: exit 0" 0 "$RC"
check "scopes: ward calls in order" "secrets --json alpha
secrets --json beta
secrets --json gamma" "$(cat "$WARD_LOG")"
P="$(parsed)"
check "scopes: exported values" '{"V_alpha": "val-alpha", "V_beta": "val-beta", "V_gamma": "val-gamma"}' "$(field "$P" vars)"
contains "scopes: summary alpha" "exported 1 values from alpha" "$OUT"
contains "scopes: summary gamma" "exported 1 values from gamma" "$OUT"

run_scopes "alpha${NL}beta${NL}gamma" beta
if [ "$RC" -ne 0 ]; then ok "scopes: ward failure propagates"; else ko "scopes: ward failure propagates" "exit 0"; fi
contains "scopes: reached failing scope" "secrets --json beta" "$(cat "$WARD_LOG")"

run_scopes "" ""
check "scopes: empty SCOPES exit" 0 "$RC"
check "scopes: empty SCOPES no calls" 0 "$(wc -c < "$WARD_LOG" | tr -d ' ')"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
