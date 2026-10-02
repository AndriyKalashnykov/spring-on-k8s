#!/usr/bin/env bash
# check-boot-overrides.sh — fail when a pom.xml override of a Spring Boot-managed
# version property has been caught up (or overtaken) by Spring Boot itself.
#
# WHY: a CVE in a Boot-managed dependency is fixed here by overriding the
# spring-boot-dependencies version property in pom.xml (e.g. tomcat.version).
# That override is only correct while it is NEWER than what the Boot parent
# manages. Once a Boot bump manages the same or a newer version, the leftover
# override silently pins (or DOWNGRADES) what Boot ships, and nothing else goes
# red. This gate is what goes red.
#
# CONTRACT
#   * Overrides live between the `boot-overrides:begin` / `boot-overrides:end`
#     comment markers in pom.xml <properties>, one single-line element each.
#   * Every property in that block must exist in the parent's
#     spring-boot-dependencies BOM (catches a property Boot renamed/removed).
#   * A Boot-managed property overridden OUTSIDE the block fails (catches an
#     override that would otherwise escape the check).
#   * Each override must be strictly NEWER than the Boot-managed value.
#     Equal or older => FAIL: delete it (in the same PR as the Boot bump).
#   * A deliberate hold-back is waived per line with a written reason:
#       <x.version>1.2.3</x.version> <!-- boot-override-ok: why -->
#   * Only plain numeric versions (1.2.3) are compared. Anything else
#     (-RC1, .Final, .RELEASE) fails loudly rather than being mis-ordered:
#     `sort -V` does not implement Maven's qualifier ordering.
#
# NOT COVERED (stated, not hidden): an override expressed as an explicit
# <version> on a dependency, or via <dependencyManagement>. There are none
# today; this gate only sees <properties>.
#
# Usage: check-boot-overrides.sh              # check ./pom.xml
#        check-boot-overrides.sh --self-test  # mutation-proof the logic (offline)
set -euo pipefail

BEGIN_MARK='boot-overrides:begin'
END_MARK='boot-overrides:end'
WAIVER_MARK='boot-override-ok:'
# A real spring-boot-dependencies BOM carries several hundred version
# properties; fewer than this means we did not parse a real BOM.
MIN_BOM_PROPS="${MIN_BOM_PROPS:-50}"
BOM_SENTINEL_PROP='tomcat.version'
POM_SENTINEL_PROP='java.version'

die() { echo "check-boot-overrides: ERROR: $*" >&2; exit 2; }

# Print "name=value" for each single-line <name>value</name> element on stdin.
elements() {
  sed -nE 's/^[[:space:]]*<([A-Za-z0-9._-]+)>([^<]*)<\/[A-Za-z0-9._-]+>.*$/\1=\2/p'
}

# Print "name=value" for every element inside <properties>…</properties> of $1.
props_of() {
  awk '/<properties>/{f=1;next} /<\/properties>/{f=0} f' "$1" | elements
}

# Print the raw pom lines between the override markers of $1.
block_lines() {
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" \
    'index($0,e){f=0} f; index($0,b){f=1}' "$1"
}

# Look up key $2 in a "name=value" list $1 (fixed-string match, no regex).
value_of() {
  awk -v k="$2" 'index($0,k"=")==1 {print substr($0,length(k)+2); exit}' <<< "$1"
}

is_plain_version() {
  case "$1" in
    ''|*[!0-9.]*|.*|*.|*..*) return 1 ;;
    *) return 0 ;;
  esac
}

# Exit 0 when $1 is strictly newer than $2 (both plain numeric versions).
strictly_newer() {
  local newest
  [ "$1" != "$2" ] || return 1
  newest="$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)"
  [ "$newest" = "$1" ]
}

# check POM BOM BOOT_VERSION — the whole decision; prints a report, returns 0/1.
check() {
  local pom="$1" bom="$2" boot_version="$3"
  local pom_props bom_props block block_props bom_count rc=0 checked=0 waived=0
  local name value managed line

  [ -f "$pom" ] || die "pom not found: $pom"
  [ -f "$bom" ] || die "spring-boot-dependencies BOM not found: $bom"

  pom_props="$(props_of "$pom")"
  bom_props="$(props_of "$bom")"
  [ -n "$(value_of "$pom_props" "$POM_SENTINEL_PROP")" ] \
    || die "could not parse <properties> of $pom (no $POM_SENTINEL_PROP)"
  bom_count="$(awk 'NF{n++} END{print n+0}' <<< "$bom_props")"
  [ "$bom_count" -ge "$MIN_BOM_PROPS" ] \
    || die "parsed only $bom_count properties from $bom — not a real BOM?"
  [ -n "$(value_of "$bom_props" "$BOM_SENTINEL_PROP")" ] \
    || die "$bom has no $BOM_SENTINEL_PROP property — not a spring-boot-dependencies BOM?"

  awk -v b="$BEGIN_MARK" 'index($0,b){f=1} END{exit !f}' "$pom" \
    || die "$pom has no '$BEGIN_MARK' marker (keep the markers even when the block is empty)"
  awk -v e="$END_MARK" 'index($0,e){f=1} END{exit !f}' "$pom" \
    || die "$pom has no '$END_MARK' marker"

  block="$(block_lines "$pom")"
  block_props="$(elements <<< "$block")"

  # 1. A Boot-managed property overridden outside the marked block escapes the check.
  while IFS='=' read -r name value; do
    [ -n "$name" ] || continue
    [ -n "$(value_of "$bom_props" "$name")" ] || continue
    if [ -z "$(value_of "$block_props" "$name")" ]; then
      echo "FAIL  $name=$value overrides a Spring Boot-managed property OUTSIDE the $BEGIN_MARK block — move it inside so it is checked."
      rc=1
    fi
  done <<< "$pom_props"

  # 2. Every override in the block must still be ahead of Boot.
  while IFS='=' read -r name value; do
    [ -n "$name" ] || continue
    checked=$((checked + 1))
    managed="$(value_of "$bom_props" "$name")"
    if [ -z "$managed" ]; then
      echo "FAIL  $name=$value is not a property of spring-boot-dependencies $boot_version (renamed or removed by Boot?) — the override no longer does anything; delete or rename it."
      rc=1
      continue
    fi
    line="$(awk -v k="<$name>" 'index($0,k){print; exit}' <<< "$block")"
    if [ "${line#*"$WAIVER_MARK"}" != "$line" ]; then
      if [ -n "$(sed -E "s/.*${WAIVER_MARK}[[:space:]]*//; s/[[:space:]]*-->.*//" <<< "$line")" ]; then
        echo "WAIVED $name=$value (Boot $boot_version manages $managed) — ${WAIVER_MARK}${line#*"$WAIVER_MARK"}"
        waived=$((waived + 1))
        continue
      fi
      echo "FAIL  $name has a '$WAIVER_MARK' marker with no reason."
      rc=1
      continue
    fi
    if ! is_plain_version "$value" || ! is_plain_version "$managed"; then
      echo "FAIL  $name: cannot compare override '$value' with Boot-managed '$managed' — only plain numeric versions are supported (qualifiers are not ordered the Maven way). Compare by hand and either delete the override or waive it with '$WAIVER_MARK <reason>'."
      rc=1
      continue
    fi
    if strictly_newer "$value" "$managed"; then
      echo "ok    $name override $value > Boot-managed $managed"
    else
      echo "FAIL  $name override $value is no longer ahead of Spring Boot $boot_version, which manages $managed. Delete this override from pom.xml (in the SAME PR as the Boot bump) — keeping it pins or downgrades what Boot ships."
      rc=1
    fi
  done <<< "$block_props"

  echo "check-boot-overrides: Spring Boot $boot_version, BOM properties parsed: $bom_count, overrides checked: $checked (waived: $waived)"
  return "$rc"
}

self_test() {
  local tmp failures=0 out rc i
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mk_bom() { # mk_bom FILE [extra property lines…]
    local f="$1"; shift
    { echo '<project><properties>'
      for i in $(seq 1 "$MIN_BOM_PROPS"); do echo "    <filler$i.version>1.0.$i</filler$i.version>"; done
      printf '    %s\n' "$@"
      echo '</properties></project>'; } > "$f"
  }
  mk_pom() { # mk_pom FILE "<outside lines>" "<block lines>"
    { echo '<project><properties>'
      echo '    <java.version>21</java.version>'
      [ -z "$2" ] || printf '%b\n' "$2"
      echo "    <!-- $BEGIN_MARK -->"
      [ -z "$3" ] || printf '%b\n' "$3"
      echo "    <!-- $END_MARK -->"
      echo '</properties></project>'; } > "$1"
  }
  # expect NAME WANT_RC NEEDLE — run check on $tmp/pom.xml vs $tmp/bom.pom
  expect() {
    rc=0
    out="$(check "$tmp/pom.xml" "$tmp/bom.pom" 9.9.9 2>&1)" || rc=$?
    if [ "$rc" -ne "$2" ] || [ "${out#*"$3"}" = "$out" ]; then
      echo "self-test FAIL: $1 (want rc=$2 containing '$3'; got rc=$rc)"; printf '    %s\n' "${out//$'\n'/$'\n'    }"
      failures=$((failures + 1))
    else
      echo "self-test ok:   $1"
    fi
  }

  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.24</tomcat.version>' '<jackson-bom.version>3.1.5</jackson-bom.version>'

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version>'
  expect 'override newer than Boot passes' 0 'ok    tomcat.version override 11.0.25 > Boot-managed 11.0.24'

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.24</tomcat.version>'
  expect 'override EQUAL to Boot fails' 1 'no longer ahead'

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.23</tomcat.version>'
  expect 'override OLDER than Boot fails' 1 'no longer ahead'

  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.9</tomcat.version>'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version>'
  expect 'numeric (not lexical) ordering: 11.0.25 > 11.0.9' 0 'overrides checked: 1'
  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.25</tomcat.version>'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.9</tomcat.version>'
  expect 'numeric (not lexical) ordering: 11.0.9 < 11.0.25 fails' 1 'no longer ahead'

  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.24</tomcat.version>'
  mk_pom "$tmp/pom.xml" '' '    <jackson-2-bom.version>2.21.7</jackson-2-bom.version>'
  expect 'block property missing from BOM fails' 1 'is not a property of spring-boot-dependencies'

  mk_pom "$tmp/pom.xml" '    <tomcat.version>11.0.25</tomcat.version>' ''
  expect 'Boot-managed override OUTSIDE the block fails' 1 'OUTSIDE the'

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25-RC1</tomcat.version>'
  expect 'qualified override version fails (not mis-ordered)' 1 'only plain numeric versions'
  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.24.Final</tomcat.version>'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version>'
  expect 'qualified Boot-managed version fails (not mis-ordered)' 1 'only plain numeric versions'

  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.24</tomcat.version>' '<jackson-bom.version>3.1.5</jackson-bom.version>'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.20</tomcat.version> <!-- boot-override-ok: regression in 11.0.24 -->'
  expect 'waived hold-back passes' 0 'WAIVED tomcat.version=11.0.20'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.20</tomcat.version> <!-- boot-override-ok: regression in 11.0.24 -->\n    <jackson-bom.version>3.1.4</jackson-bom.version>'
  expect 'waiver does not cover an unmarked sibling' 1 'jackson-bom.version override 3.1.4 is no longer ahead'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.20</tomcat.version> <!-- boot-override-ok: -->'
  expect 'waiver without a reason fails' 1 'marker with no reason'

  mk_pom "$tmp/pom.xml" '' ''
  expect 'empty block passes with zero overrides' 0 'overrides checked: 0'

  { echo '<project><properties>'; echo '<java.version>21</java.version>'; echo '</properties></project>'; } > "$tmp/pom.xml"
  expect 'pom without markers is an error, not a pass' 2 "has no '$BEGIN_MARK' marker"

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version>'
  echo '<project><properties><tomcat.version>11.0.24</tomcat.version></properties></project>' > "$tmp/bom.pom"
  expect 'truncated/unparsed BOM is an error, not a pass' 2 'not a real BOM'

  if [ "$failures" -ne 0 ]; then
    echo "check-boot-overrides self-test: $failures case(s) FAILED"
    return 1
  fi
  echo "check-boot-overrides self-test: all cases passed"
}

main() {
  local pom="pom.xml" boot_version repo bom
  [ -f "$pom" ] || die "run from the repo root (no $pom)"
  boot_version="$(awk '/<parent>/{f=1} /<\/parent>/{f=0} f' "$pom" | sed -nE 's/^[[:space:]]*<version>([^<]+)<\/version>.*$/\1/p' | head -n 1 || true)"
  [ -n "$boot_version" ] || die "could not read the parent version from $pom"
  # Resolving any expression builds the project model, which downloads the
  # parent chain (incl. the spring-boot-dependencies BOM) into the local repo.
  repo="$(mvn -B -q help:evaluate -Dexpression=settings.localRepository -DforceStdout 2>/dev/null || true)"
  [ -n "$repo" ] && [ -d "$repo" ] || die "could not resolve the Maven local repository (got '$repo')"
  bom="$repo/org/springframework/boot/spring-boot-dependencies/$boot_version/spring-boot-dependencies-$boot_version.pom"
  check "$pom" "$bom" "$boot_version"
}

case "${1:-}" in
  --self-test) self_test ;;
  '') main ;;
  *) die "unknown argument: $1" ;;
esac
