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
# Elements must be single-line `<name>value</name>`. A Boot-managed property
# written any other way (wrapped across lines, `<name >`), or defined more than
# once (e.g. again in a <profile>), FAILS rather than being skipped. Known false
# RED, loud by design: an override commented out with a MULTI-line `<!-- … -->`
# is still read as live — use a single-line comment or delete it.
#
# NOT COVERED (stated, not hidden): an override expressed as an explicit
# <version> on a dependency, or via <dependencyManagement>. There are none
# today; this gate only sees <properties>.
#
# Usage: check-boot-overrides.sh              # check ./pom.xml
#        check-boot-overrides.sh --fix        # delete caught-up overrides, then re-check
#        check-boot-overrides.sh --self-test  # mutation-proof the logic (offline)
#
# --fix deletes ONLY block lines that are (a) strictly between the markers,
# (b) not waived, (c) plain-numeric on both sides and (d) no longer newer than
# Boot's value. Deleting such a line can never reintroduce a CVE: Boot then ships
# a version >= the override. pom.xml is rewritten only when the full re-check
# passes; anything else (qualifier, renamed property, override outside the block)
# is left for a human and --fix exits 1 with pom.xml untouched.
# Used by .github/workflows/renovate-autofix.yml.
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
    ''|*[!0-9.]*|.*|*.|*..*|0[0-9]*|*.0[0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Exit 0 when $1 is strictly newer than $2 (both plain numeric versions).
# Maven treats 11.0.25 and 11.0.25.0 as the same version; drop trailing ".0"s.
normalise() {
  local v="$1"
  while [ "${v%.0}" != "$v" ]; do v="${v%.0}"; done
  printf '%s' "$v"
}

strictly_newer() {
  local a b newest
  a="$(normalise "$1")"; b="$(normalise "$2")"
  [ "$a" != "$b" ] || return 1
  newest="$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1)"
  [ "$newest" = "$a" ]
}

# check POM BOM BOOT_VERSION — the whole decision; prints a report, returns 0/1.
check() {
  local pom="$1" bom="$2" boot_version="$3"
  local pom_props bom_props block block_props bom_count rc=0 checked=0 waived=0
  local name value managed line census count

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

  # 0. Every Boot-managed property that appears in the pom AT ALL must be a
  #    single-line element defined exactly once — otherwise the parser cannot
  #    see it (wrapped element) or a second copy escapes (e.g. in a <profile>).
  census="$(sed 's/<!--.*-->//g' "$pom" | grep -oE '<[A-Za-z0-9._-]+[[:space:]]*>' | tr -d '<> \t' | sort -u || true)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ -n "$(value_of "$bom_props" "$name")" ] || continue
    count="$(awk -F= -v k="$name" '$1==k{n++} END{print n+0}' <<< "$pom_props")"
    if [ "$count" -eq 0 ]; then
      echo "FAIL  $name is a Spring Boot-managed property but is not written as a single-line <$name>value</$name> element — this gate cannot read it. Put it on one line."
      rc=1
    elif [ "$count" -gt 1 ]; then
      echo "FAIL  $name is defined $count times in $pom (a second copy, e.g. in a <profile>, escapes the check). Define it once, inside the $BEGIN_MARK block."
      rc=1
    fi
  done <<< "$census"

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
    line="$(awk -v k="<$name>" '{l=$0; sub(/^[ \t]+/,"",l)} index(l,k)==1 {print; exit}' <<< "$block")"
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

# fix POM BOM BOOT_VERSION — see the header. Returns 0 when nothing needed
# removing or the removal made the check pass; 1 (pom untouched) otherwise.
fix() {
  local pom="$1" bom="$2" boot_version="$3"
  local bom_props block_props begin end name value managed lineno del="" n=0 tmp

  [ -f "$pom" ] || die "pom not found: $pom"
  [ -f "$bom" ] || die "spring-boot-dependencies BOM not found: $bom"
  bom_props="$(props_of "$bom")"
  begin="$(awk -v b="$BEGIN_MARK" 'index($0,b){print NR; exit}' "$pom")"
  end="$(awk -v e="$END_MARK" 'index($0,e){print NR; exit}' "$pom")"
  if [ -z "$begin" ] || [ -z "$end" ] || [ "$begin" -ge "$end" ]; then
    die "$pom: override markers missing or out of order"
  fi
  block_props="$(elements <<< "$(block_lines "$pom")")"

  while IFS='=' read -r name value; do
    [ -n "$name" ] || continue
    managed="$(value_of "$bom_props" "$name")"
    [ -n "$managed" ] || continue
    if ! is_plain_version "$value" || ! is_plain_version "$managed"; then continue; fi
    if strictly_newer "$value" "$managed"; then continue; fi
    # Exactly one un-waived element line strictly between the markers, or skip.
    lineno="$(awk -v k="<$name>" -v b="$begin" -v e="$end" -v w="$WAIVER_MARK" '
      NR > b && NR < e { l = $0; sub(/^[ \t]+/, "", l)
                         # a line holding exactly ONE element (never a shared line)
                         if (index(l, k) == 1 && index($0, w) == 0 &&
                             l ~ /^<[A-Za-z0-9._-]+>[^<]*<\/[A-Za-z0-9._-]+>[ \t\r]*$/) { print NR; c++ } }
      END { exit (c == 1 ? 0 : 1) }' "$pom")" || continue
    case " $del " in *" $lineno "*) continue ;; esac   # a name listed twice
    echo "FIX   removing $name=$value (Spring Boot $boot_version manages $managed) at $pom:$lineno"
    del="$del $lineno"
    n=$((n + 1))
  done <<< "$block_props"

  if [ "$n" -eq 0 ]; then
    echo "check-boot-overrides --fix: no caught-up override to remove"
    return 0
  fi
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  local sedexpr=() l
  for l in $del; do sedexpr+=(-e "${l}d"); done
  sed "${sedexpr[@]}" "$pom" > "$tmp"
  if check "$tmp" "$bom" "$boot_version"; then
    cat "$tmp" > "$pom"
    rm -f "$tmp"
    echo "check-boot-overrides --fix: removed $n override(s); re-check passes"
    return 0
  fi
  rm -f "$tmp"
  echo "check-boot-overrides --fix: re-check still fails after removing $n override(s) — pom.xml left UNCHANGED for a human"
  return 1
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

  # --- cases from the implementation review (each was a reachable false GREEN) ---
  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.25</tomcat.version>'

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.26</tomcat.version>'
  printf '%s\n' '<profile><properties>' '    <tomcat.version>11.0.20</tomcat.version>' '</properties></profile>' >> "$tmp/pom.xml"
  expect 'second copy of an override in a <profile> fails' 1 'is defined 2 times'

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>\n      11.0.20\n    </tomcat.version>'
  expect 'override wrapped across lines fails (not skipped)' 1 'not written as a single-line'
  mk_pom "$tmp/pom.xml" '    <tomcat.version >11.0.20</tomcat.version>' ''
  expect 'override with whitespace in the tag fails (not skipped)' 1 'not written as a single-line'

  mk_pom "$tmp/pom.xml" '' '    <!-- <tomcat.version> see boot-override-ok: note -->\n    <tomcat.version>11.0.20</tomcat.version>'
  expect 'a comment line cannot lend its waiver to the element' 1 'tomcat.version override 11.0.20 is no longer ahead'

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25.0</tomcat.version>'
  expect 'Maven-equal version with trailing .0 is not "newer"' 1 'no longer ahead'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.00.26</tomcat.version>'
  expect 'leading-zero version component is rejected' 1 'only plain numeric versions'

  mk_pom "$tmp/pom.xml" '' '    <!-- <tomcat.version>11.0.20</tomcat.version> -->'
  expect 'single-line commented-out override is ignored' 0 'overrides checked: 0'

  # --- guards the first self-test left unexercised (surviving mutants) ---
  { echo '<project><properties>'; echo "    <!-- $BEGIN_MARK -->"; echo "    <!-- $END_MARK -->"; echo '</properties></project>'; } > "$tmp/pom.xml"
  expect 'pom whose <properties> did not parse is an error' 2 "no $POM_SENTINEL_PROP"

  { echo '<project><properties>'; echo '<java.version>21</java.version>'; echo "    <!-- $BEGIN_MARK -->"; echo '</properties></project>'; } > "$tmp/pom.xml"
  expect 'pom with a begin marker but no end marker is an error' 2 "has no '$END_MARK' marker"

  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.26</tomcat.version>'
  mk_bom "$tmp/bom.pom" '<jackson-bom.version>3.1.5</jackson-bom.version>'
  expect 'large BOM without the sentinel property is an error' 2 "has no $BOM_SENTINEL_PROP property"

  mk_bom "$tmp/bom.pom" '<tomcat.version-legacy>99.0.0</tomcat.version-legacy>' '<tomcat.version>11.0.24</tomcat.version>'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version>'
  expect 'prefix-named BOM property is not mistaken for the override' 0 'tomcat.version override 11.0.25 > Boot-managed 11.0.24'

  # --- --fix: deletes only caught-up, un-waived, in-block lines; re-checks ---
  # expect_fix NAME WANT_RC NEEDLE — run fix on $tmp/pom.xml vs $tmp/bom.pom
  expect_fix() {
    rc=0
    cp "$tmp/pom.xml" "$tmp/pom.before"
    out="$(fix "$tmp/pom.xml" "$tmp/bom.pom" 9.9.9 2>&1)" || rc=$?
    if [ "$rc" -ne "$2" ] || [ "${out#*"$3"}" = "$out" ]; then
      echo "self-test FAIL: $1 (want rc=$2 containing '$3'; got rc=$rc)"; printf '    %s\n' "${out//$'\n'/$'\n'    }"
      failures=$((failures + 1)); return 1
    fi
  }
  # pom_has PATTERN COUNT — assert $tmp/pom.xml contains PATTERN exactly COUNT times
  pom_has() { [ "$(grep -cF -- "$1" "$tmp/pom.xml" || true)" -eq "$2" ]; }
  ok_or_fail() { if "$@"; then :; else echo "self-test FAIL: $FIXCASE (assertion: $*)"; failures=$((failures + 1)); return 1; fi; }

  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.25</tomcat.version>' '<jackson-bom.version>3.1.5</jackson-bom.version>'
  FIXCASE='--fix removes a caught-up override and keeps a still-ahead one'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version>\n    <jackson-bom.version>3.1.7</jackson-bom.version>'
  if expect_fix "$FIXCASE" 0 'removed 1 override(s)'; then
    ok_or_fail pom_has '<tomcat.version>' 0 && ok_or_fail pom_has '<jackson-bom.version>3.1.7' 1 \
      && ok_or_fail pom_has "$BEGIN_MARK" 1 && ok_or_fail pom_has "$END_MARK" 1 && echo "self-test ok:   $FIXCASE"
  fi

  FIXCASE='--fix removes an override Boot has overtaken (older)'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.20</tomcat.version>'
  if expect_fix "$FIXCASE" 0 'removing tomcat.version=11.0.20'; then
    ok_or_fail pom_has '<tomcat.version>' 0 && echo "self-test ok:   $FIXCASE"
  fi

  FIXCASE='--fix leaves a WAIVED hold-back in place'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.20</tomcat.version> <!-- boot-override-ok: regression -->'
  if expect_fix "$FIXCASE" 0 'no caught-up override to remove'; then
    ok_or_fail cmp -s "$tmp/pom.xml" "$tmp/pom.before" && echo "self-test ok:   $FIXCASE"
  fi

  FIXCASE='--fix is a no-op when every override is still ahead'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.26</tomcat.version>'
  if expect_fix "$FIXCASE" 0 'no caught-up override to remove'; then
    ok_or_fail cmp -s "$tmp/pom.xml" "$tmp/pom.before" && echo "self-test ok:   $FIXCASE"
  fi

  FIXCASE='--fix leaves pom UNCHANGED when the re-check would still fail'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version>\n    <jackson-bom.version>3.1.7-RC1</jackson-bom.version>'
  if expect_fix "$FIXCASE" 1 'pom.xml left UNCHANGED'; then
    ok_or_fail cmp -s "$tmp/pom.xml" "$tmp/pom.before" && echo "self-test ok:   $FIXCASE"
  fi

  FIXCASE='--fix never deletes a line SHARED with a still-needed override'
  mk_bom "$tmp/bom.pom" '<tomcat.version>11.0.25</tomcat.version>' '<jackson-bom.version>3.1.5</jackson-bom.version>'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version><jackson-bom.version>3.1.7</jackson-bom.version>'
  if expect_fix "$FIXCASE" 0 'no caught-up override to remove'; then
    ok_or_fail cmp -s "$tmp/pom.xml" "$tmp/pom.before" && echo "self-test ok:   $FIXCASE"
  fi

  FIXCASE='--fix keeps a missing final newline (no spurious change)'
  mk_pom "$tmp/pom.xml" '' '    <tomcat.version>11.0.25</tomcat.version>'
  printf '%s' "$(cat "$tmp/pom.xml")" > "$tmp/pom.nonl" && mv "$tmp/pom.nonl" "$tmp/pom.xml"
  if expect_fix "$FIXCASE" 0 'removed 1 override(s)'; then
    ok_or_fail test "$(tail -c 1 "$tmp/pom.xml" | od -An -tx1 | tr -d ' ')" != "0a" && echo "self-test ok:   $FIXCASE"
  fi

  FIXCASE='--fix never touches a same-named line OUTSIDE the block'
  mk_pom "$tmp/pom.xml" '    <tomcat.version>11.0.25</tomcat.version>' ''
  if expect_fix "$FIXCASE" 0 'no caught-up override to remove'; then
    ok_or_fail cmp -s "$tmp/pom.xml" "$tmp/pom.before" && echo "self-test ok:   $FIXCASE"
  fi

  if [ "$failures" -ne 0 ]; then
    echo "check-boot-overrides self-test: $failures case(s) FAILED"
    return 1
  fi
  echo "check-boot-overrides self-test: all cases passed"
}

main() {
  local mode="$1" pom="pom.xml" boot_version repo bom
  [ -f "$pom" ] || die "run from the repo root (no $pom)"
  boot_version="$(awk '/<parent>/{f=1} /<\/parent>/{f=0} f' "$pom" | sed -nE 's/^[[:space:]]*<version>([^<]+)<\/version>.*$/\1/p' | head -n 1 || true)"
  [ -n "$boot_version" ] || die "could not read the parent version from $pom"
  # Resolving any expression builds the project model, which downloads the
  # parent chain (incl. the spring-boot-dependencies BOM) into the local repo.
  repo="$(mvn -B -q help:evaluate -Dexpression=settings.localRepository -DforceStdout 2>/dev/null || true)"
  [ -n "$repo" ] && [ -d "$repo" ] || die "could not resolve the Maven local repository (got '$repo')"
  bom="$repo/org/springframework/boot/spring-boot-dependencies/$boot_version/spring-boot-dependencies-$boot_version.pom"
  "$mode" "$pom" "$bom" "$boot_version"
}

case "${1:-}" in
  --self-test) self_test ;;
  '') main check ;;
  --fix) main fix ;;
  *) die "unknown argument: $1" ;;
esac
