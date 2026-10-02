#!/usr/bin/env bash
# autofix-validate.sh — the trust boundary of the Renovate autofix.
#
# The `prepare` workflow renders diagrams and runs `check-boot-overrides.sh --fix`
# using code from the PR branch, with no write token. Its output is therefore
# UNTRUSTED. The privileged `commit` workflow (renovate-autofix-commit.yml, which
# always runs main's definition) runs THIS script from a checkout of main before
# pushing anything. It accepts exactly two kinds of change:
#
#   png FILE        FILE is a real PNG (signature) of at most MAX_PNG_BYTES.
#   pom OLD NEW     NEW is OLD minus >= 0 lines, where every removed line
#                     * lies strictly between the boot-overrides markers in OLD,
#                     * is a bare single-line `<x.version>1.2.3</x.version>`
#                       (no comment, so a waived hold-back can never be removed),
#                   no line is added, and both markers survive exactly once.
#
# Anything else exits non-zero and nothing is pushed. Deleting such a line cannot
# reintroduce a CVE on its own (prepare only removes overrides Boot has caught up
# to), and the PR's CI (check-boot-overrides + trivy-fs) still re-gates the result.
#
# Usage: autofix-validate.sh png FILE
#        autofix-validate.sh pom OLD NEW
#        autofix-validate.sh --self-test
set -euo pipefail

BEGIN_MARK='boot-overrides:begin'
END_MARK='boot-overrides:end'
MAX_PNG_BYTES="${MAX_PNG_BYTES:-2097152}"   # 2 MiB; the committed diagrams are ~35-60 KB
PNG_SIGNATURE='89504e470d0a1a0a'

fail() { echo "autofix-validate: REJECT: $*" >&2; return 1; }

validate_png() {
  local f="$1" size sig
  [ -f "$f" ] || { fail "$f: not a regular file"; return 1; }
  size="$(wc -c < "$f" | tr -d ' ')"
  [ "$size" -gt 0 ] && [ "$size" -le "$MAX_PNG_BYTES" ] \
    || { fail "$f: size $size bytes outside (0, $MAX_PNG_BYTES]"; return 1; }
  sig="$(head -c 8 "$f" | od -An -tx1 | tr -d ' \n')"
  [ "$sig" = "$PNG_SIGNATURE" ] || { fail "$f: not a PNG (signature $sig)"; return 1; }
  echo "autofix-validate: ok png $f ($size bytes)"
}

# Line number of the single line containing $2 in $1; fails unless exactly one.
marker_line() {
  awk -v m="$2" 'index($0, m) { n++; l = NR } END { if (n != 1) exit 1; print l }' "$1"
}

validate_pom() {
  local old="$1" new="$2" b e diffout rc=0 sign num text removed=0
  local re='^[[:space:]]*<([A-Za-z0-9.-]+\.version)>[0-9.]+</([A-Za-z0-9.-]+)>[[:space:]]*$'
  [ -f "$old" ] && [ -f "$new" ] || { fail "missing pom input"; return 1; }
  b="$(marker_line "$old" "$BEGIN_MARK")" || { fail "OLD: '$BEGIN_MARK' marker not exactly once"; return 1; }
  e="$(marker_line "$old" "$END_MARK")"   || { fail "OLD: '$END_MARK' marker not exactly once"; return 1; }
  marker_line "$new" "$BEGIN_MARK" >/dev/null || { fail "NEW: '$BEGIN_MARK' marker removed or duplicated"; return 1; }
  marker_line "$new" "$END_MARK" >/dev/null   || { fail "NEW: '$END_MARK' marker removed or duplicated"; return 1; }
  [ "$b" -lt "$e" ] || { fail "OLD: markers out of order"; return 1; }

  diffout="$(diff --unchanged-line-format='' --old-line-format='-%dn %L' \
                  --new-line-format='+%dn %L' "$old" "$new")" || rc=$?
  [ "$rc" -le 1 ] || { fail "diff failed (rc=$rc)"; return 1; }

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    sign="${line:0:1}"
    num="${line%% *}"; num="${num:1}"
    text="${line#* }"
    if [ "$sign" = "+" ]; then fail "NEW adds line $num: $text"; return 1; fi
    if [ "$num" -le "$b" ] || [ "$num" -ge "$e" ]; then
      fail "removes line $num outside the override block: $text"; return 1
    fi
    if ! [[ $text =~ $re ]] || [ "${BASH_REMATCH[1]}" != "${BASH_REMATCH[2]}" ]; then
      fail "removes line $num that is not a bare <x.version>N.N.N</x.version> override: $text"; return 1
    fi
    removed=$((removed + 1))
  done <<< "$diffout"
  echo "autofix-validate: ok pom (removed $removed override line(s), added 0)"
}

self_test() {
  local tmp failures=0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # expect NAME WANT(0|1) CMD... — run a validator and compare its pass/fail
  expect() {
    local name="$1" want="$2" got=0; shift 2
    "$@" >/dev/null 2>&1 || got=1
    if [ "$got" -eq "$want" ]; then echo "self-test ok:   $name"
    else echo "self-test FAIL: $name (want $want, got $got)"; failures=$((failures + 1)); fi
  }
  pom() { # pom FILE BODY-LINES...
    local f="$1"; shift
    { echo '<project><properties>'; echo '    <java.version>21</java.version>'
      echo "    <!-- $BEGIN_MARK -->"; printf '%s\n' "$@"; echo "    <!-- $END_MARK -->"
      echo '    <other.version>1.0</other.version>'; echo '</properties></project>'; } > "$f"
  }

  pom "$tmp/old" '    <tomcat.version>11.0.25</tomcat.version>' '    <jackson-bom.version>3.1.7</jackson-bom.version>'
  pom "$tmp/new" '    <jackson-bom.version>3.1.7</jackson-bom.version>'
  expect 'removing one bare override inside the block is accepted' 0 validate_pom "$tmp/old" "$tmp/new"
  expect 'an unchanged pom is accepted' 0 validate_pom "$tmp/old" "$tmp/old"

  pom "$tmp/new" '    <tomcat.version>11.0.25</tomcat.version>' '    <jackson-bom.version>3.1.7</jackson-bom.version>' '    <evil.version>1.0</evil.version>'
  expect 'any ADDED line is rejected' 1 validate_pom "$tmp/old" "$tmp/new"

  grep -v '<other.version>' "$tmp/old" > "$tmp/new"
  expect 'removing a line OUTSIDE the block is rejected' 1 validate_pom "$tmp/old" "$tmp/new"

  grep -vF "$END_MARK" "$tmp/old" > "$tmp/new"
  expect 'removing a marker is rejected' 1 validate_pom "$tmp/old" "$tmp/new"

  pom "$tmp/old" '    <tomcat.version>11.0.20</tomcat.version> <!-- boot-override-ok: regression -->'
  pom "$tmp/new"
  expect 'removing a WAIVED (commented) override is rejected' 1 validate_pom "$tmp/old" "$tmp/new"

  pom "$tmp/old" '    <!-- note -->' '    <tomcat.version>11.0.25</tomcat.version>'
  pom "$tmp/new" '    <tomcat.version>11.0.25</tomcat.version>'
  expect 'removing a non-override line inside the block is rejected' 1 validate_pom "$tmp/old" "$tmp/new"

  pom "$tmp/old" '    <a.version>1.0</b.version>'
  pom "$tmp/new"
  expect 'a mismatched open/close tag is rejected' 1 validate_pom "$tmp/old" "$tmp/new"

  printf '\x89PNG\r\n\x1a\n%s' 'payload' > "$tmp/ok.png"
  expect 'a real PNG signature is accepted' 0 validate_png "$tmp/ok.png"
  printf '#!/bin/sh\necho pwned\n' > "$tmp/bad.png"
  expect 'a non-PNG file with a .png name is rejected' 1 validate_png "$tmp/bad.png"
  : > "$tmp/empty.png"
  expect 'an empty file is rejected' 1 validate_png "$tmp/empty.png"
  head -c 16 "$tmp/ok.png" > "$tmp/big.png"
  expect 'a PNG larger than the cap is rejected' 1 env MAX_PNG_BYTES=8 bash "$0" png "$tmp/big.png"

  if [ "$failures" -ne 0 ]; then
    echo "autofix-validate self-test: $failures case(s) FAILED"; return 1
  fi
  echo "autofix-validate self-test: all cases passed"
}

case "${1:-}" in
  png) [ "$#" -eq 2 ] || { echo "usage: $0 png FILE" >&2; exit 2; }; validate_png "$2" ;;
  pom) [ "$#" -eq 3 ] || { echo "usage: $0 pom OLD NEW" >&2; exit 2; }; validate_pom "$2" "$3" ;;
  --self-test) self_test ;;
  *) echo "usage: $0 {png FILE | pom OLD NEW | --self-test}" >&2; exit 2 ;;
esac
