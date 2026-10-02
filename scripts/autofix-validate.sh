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
#   apply ART REPO  for each path in ART/changed: the destination in the git work
#                   tree REPO must be a TRACKED REGULAR FILE (git mode 100644) at
#                   exactly that path — never a symlink, never under a symlinked
#                   directory — and the artifact entry must be a regular file too;
#                   then the png/pom check above runs, the file is copied in and
#                   staged. (A symlink destination would let cp write through to
#                   any file, e.g. this script; see the self-test.)
#
# Anything else exits non-zero and nothing is pushed. Deleting such a line cannot
# reintroduce a CVE on its own (prepare only removes overrides Boot has caught up
# to), and the PR's CI (check-boot-overrides + trivy-fs) still re-gates the result.
#
# Usage: autofix-validate.sh png FILE
#        autofix-validate.sh pom OLD NEW
#        autofix-validate.sh apply ARTIFACT_DIR REPO_DIR
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

# Is REPO/F a tracked, regular (100644), non-symlinked file at exactly that path?
tracked_regular_file() {
  local repo="$1" f="$2" mode top real
  mode="$(git -C "$repo" ls-files -s -- "$f" | awk '{ m = $1; n++ } END { print (n == 1 ? m : "x") }')"
  [ "$mode" = 100644 ] || { fail "$f is not a tracked regular file in the PR tree (mode '$mode')"; return 1; }
  if [ -L "$repo/$f" ] || [ ! -f "$repo/$f" ]; then fail "$f is a symlink or not a regular file"; return 1; fi
  top="$(cd "$repo" && pwd -P)"
  real="$(realpath -e -- "$repo/$f")" || { fail "$f does not resolve"; return 1; }
  [ "$real" = "$top/$f" ] || { fail "$f resolves outside its own path ($real)"; return 1; }
}

apply_artifact() {
  local art="$1" repo="$2" f name src n=0
  [ -f "$art/changed" ] || { fail "$art/changed missing"; return 1; }
  git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1 || { fail "$repo is not a git work tree"; return 1; }
  while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    case "$f" in
      pom.xml) ;;
      docs/diagrams/out/*.png)
        name="${f#docs/diagrams/out/}"
        case "$name" in */*|.*|'') fail "refusing path $f"; return 1 ;; esac ;;
      *) fail "not an allowlisted autofix path: $f"; return 1 ;;
    esac
    tracked_regular_file "$repo" "$f" || return 1
    src="$art/files/$f"
    if [ -L "$src" ] || [ ! -f "$src" ]; then fail "artifact entry $f is a symlink or missing"; return 1; fi
    case "$f" in
      pom.xml) validate_pom "$repo/pom.xml" "$src" || return 1 ;;
      *)       validate_png "$src" || return 1 ;;
    esac
    cp -- "$src" "$repo/$f"
    git -C "$repo" add -- "$f"
    n=$((n + 1))
  done < "$art/changed"
  echo "autofix-validate: applied $n file(s)"
}

self_test() {
  local tmp failures=0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # expect NAME WANT(0|1) NEEDLE CMD... — run a validator; compare pass/fail AND
  # require NEEDLE in its output, so a case cannot pass because a different
  # (earlier) guard fired.
  expect() {
    local name="$1" want="$2" needle="$3" got=0 out; shift 3
    out="$("$@" 2>&1)" || got=1
    if [ "$got" -eq "$want" ] && [ "${out#*"$needle"}" != "$out" ]; then echo "self-test ok:   $name"
    else echo "self-test FAIL: $name (want $want containing '$needle', got $got: $out)"; failures=$((failures + 1)); fi
  }
  pom() { # pom FILE BODY-LINES...
    local f="$1"; shift
    { echo '<project><properties>'; echo '    <java.version>21</java.version>'
      echo "    <!-- $BEGIN_MARK -->"; [ "$#" -eq 0 ] || printf '%s\n' "$@"; echo "    <!-- $END_MARK -->"
      echo '    <other.version>1.0</other.version>'; echo '</properties></project>'; } > "$f"
  }

  pom "$tmp/old" '    <tomcat.version>11.0.25</tomcat.version>' '    <jackson-bom.version>3.1.7</jackson-bom.version>'
  pom "$tmp/new" '    <jackson-bom.version>3.1.7</jackson-bom.version>'
  expect 'removing one bare override inside the block is accepted' 0 'removed 1 override' validate_pom "$tmp/old" "$tmp/new"
  expect 'an unchanged pom is accepted' 0 'removed 0 override' validate_pom "$tmp/old" "$tmp/old"

  pom "$tmp/new" '    <tomcat.version>11.0.25</tomcat.version>' '    <jackson-bom.version>3.1.7</jackson-bom.version>' '    <evil.version>1.0</evil.version>'
  expect 'any ADDED line is rejected' 1 'NEW adds line' validate_pom "$tmp/old" "$tmp/new"

  grep -v '<other.version>' "$tmp/old" > "$tmp/new"
  expect 'removing a line OUTSIDE the block is rejected' 1 'outside the override block' validate_pom "$tmp/old" "$tmp/new"

  grep -vF "$END_MARK" "$tmp/old" > "$tmp/new"
  expect 'removing a marker is rejected' 1 'marker removed or duplicated' validate_pom "$tmp/old" "$tmp/new"

  pom "$tmp/old" '    <tomcat.version>11.0.20</tomcat.version> <!-- boot-override-ok: regression -->'
  pom "$tmp/new"
  expect 'removing a WAIVED (commented) override is rejected' 1 'not a bare' validate_pom "$tmp/old" "$tmp/new"

  pom "$tmp/old" '    <!-- note -->' '    <tomcat.version>11.0.25</tomcat.version>'
  pom "$tmp/new" '    <tomcat.version>11.0.25</tomcat.version>'
  expect 'removing a non-override line inside the block is rejected' 1 'not a bare' validate_pom "$tmp/old" "$tmp/new"

  pom "$tmp/old" '    <a.version>1.0</b.version>'
  pom "$tmp/new"
  expect 'a mismatched open/close tag is rejected' 1 'not a bare' validate_pom "$tmp/old" "$tmp/new"

  printf '\x89PNG\r\n\x1a\n%s' 'payload' > "$tmp/ok.png"
  expect 'a real PNG signature is accepted' 0 'ok png' validate_png "$tmp/ok.png"
  printf '#!/bin/sh\necho pwned\n' > "$tmp/bad.png"
  expect 'a non-PNG file with a .png name is rejected' 1 'not a PNG' validate_png "$tmp/bad.png"
  : > "$tmp/empty.png"
  expect 'an empty file is rejected' 1 'outside (0,' validate_png "$tmp/empty.png"
  head -c 16 "$tmp/ok.png" > "$tmp/big.png"
  expect 'a PNG larger than the cap is rejected' 1 'outside (0, 8]' env MAX_PNG_BYTES=8 bash "$0" png "$tmp/big.png"

  # --- apply: destination must be a tracked regular file (symlink write-through) ---
  local repo="$tmp/repo" art="$tmp/art" victim="$tmp/victim"
  mkrepo() {
    rm -rf "$repo" "$art"; mkdir -p "$repo/docs/diagrams/out" "$art/files/docs/diagrams/out"
    printf '\x89PNG\r\n\x1a\n%s' 'old' > "$repo/docs/diagrams/out/a.png"
    pom "$repo/pom.xml" '    <tomcat.version>11.0.25</tomcat.version>'
    printf 'precious\n' > "$victim"
    ln -s "$victim" "$repo/docs/diagrams/out/evil.png"
    git -C "$repo" init -q && git -C "$repo" add -A \
      && git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -qm init
    printf '\x89PNG\r\n\x1a\n%s' 'new' > "$art/files/docs/diagrams/out/a.png"
    printf '\x89PNG\r\n\x1a\n%s' 'ATTACKER' > "$art/files/docs/diagrams/out/evil.png"
    mkdir -p "$art/files"; pom "$art/files/pom.xml"
  }
  mkrepo; printf '%s\n' docs/diagrams/out/a.png pom.xml > "$art/changed"
  expect 'apply copies + stages a valid PNG and pom deletion' 0 'applied 2 file(s)' apply_artifact "$art" "$repo"

  mkrepo; printf '%s\n' docs/diagrams/out/evil.png > "$art/changed"
  expect 'apply REFUSES a symlinked destination (write-through)' 1 'not a tracked regular file' apply_artifact "$art" "$repo"
  if [ "$(cat "$victim")" = precious ]; then echo "self-test ok:   symlink target left untouched"
  else echo "self-test FAIL: symlink target was overwritten"; failures=$((failures + 1)); fi

  mkrepo; printf 'x' > "$repo/docs/diagrams/out/new.png"; cp "$art/files/docs/diagrams/out/a.png" "$art/files/docs/diagrams/out/new.png"
  printf '%s\n' docs/diagrams/out/new.png > "$art/changed"
  expect 'apply refuses an untracked destination' 1 'not a tracked regular file' apply_artifact "$art" "$repo"

  mkrepo; printf '%s\n' 'docs/diagrams/out/../../pom.png' > "$art/changed"
  expect 'apply refuses a traversal path' 1 'refusing path' apply_artifact "$art" "$repo"

  mkrepo; rm -f "$art/files/docs/diagrams/out/a.png"; ln -s "$victim" "$art/files/docs/diagrams/out/a.png"
  printf '%s\n' docs/diagrams/out/a.png > "$art/changed"
  expect 'apply refuses a symlink INSIDE the artifact' 1 'artifact entry' apply_artifact "$art" "$repo"

  mkrepo; printf '%s\n' .github/workflows/ci.yml > "$art/changed"
  expect 'apply refuses a non-allowlisted path' 1 'not an allowlisted' apply_artifact "$art" "$repo"

  if [ "$failures" -ne 0 ]; then
    echo "autofix-validate self-test: $failures case(s) FAILED"; return 1
  fi
  echo "autofix-validate self-test: all cases passed"
}

case "${1:-}" in
  png) [ "$#" -eq 2 ] || { echo "usage: $0 png FILE" >&2; exit 2; }; validate_png "$2" ;;
  pom) [ "$#" -eq 3 ] || { echo "usage: $0 pom OLD NEW" >&2; exit 2; }; validate_pom "$2" "$3" ;;
  apply) [ "$#" -eq 3 ] || { echo "usage: $0 apply ARTIFACT_DIR REPO_DIR" >&2; exit 2; }; apply_artifact "$2" "$3" ;;
  --self-test) self_test ;;
  *) echo "usage: $0 {png FILE | pom OLD NEW | apply ART REPO | --self-test}" >&2; exit 2 ;;
esac
