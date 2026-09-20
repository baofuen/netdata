#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Self-check for apply-zh-cn.sh. Copies the localisation directory into a temporary workspace, builds
# a throwaway dashboard tree there, and asserts the properties the localisation depends on. Neither
# the repository nor any installed dashboard is touched. Run it directly:
#
#   packaging/dashboard-i18n/selftest.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Run the copy, not the originals: the dictionary-rejection cases below need a mutable dictionary.
tool="${work}/tool"
mkdir -p "${tool}"
cp "${HERE}/apply-zh-cn.sh" "${HERE}/zh-CN.js" "${HERE}/zh-CN.json" "${tool}/"
APPLY="${tool}/apply-zh-cn.sh"

START_MARKER='<!-- netdata-zh-cn -->'
END_MARKER='<!-- /netdata-zh-cn -->'
failures=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "${expected}" = "${actual}" ]; then
    echo "  ok   ${label}"
  else
    echo "  FAIL ${label}: expected [${expected}], got [${actual}]"
    failures=$((failures + 1))
  fi
}

count_matching() {
  grep -c -- "$2" "$1" 2>/dev/null || true
}

# The summary line is the last one the script prints before "Done."; matching it by shape keeps the
# assertion independent of the progress lines above it.
summary() {
  grep -oE '(patched|would patch|would revert|reverted) [0-9]+ of [0-9]+ HTML file\(s\)' "$1" | tail -1 || true
}

# Every invocation goes through this so a failed run is reported by check() instead of aborting the
# whole self-check under set -e.
run_apply() {
  local out="$1"; shift
  set +e
  "${APPLY}" "$@" > "${out}" 2>&1
  APPLY_STATUS=$?
  set -e
}

make_tree() {
  rm -rf "${work}/web"
  mkdir -p "${work}/web/v3/static/site/pages/error-404"
  printf '<!doctype html><html><head><title>t</title></head><body>hi</body></html>' > "${work}/web/index.html"
  printf '<!doctype html><html><head></head><body>hi</body></html>' > "${work}/web/v3/local-agent.html"
  printf '<!doctype html><html><head></head><body>deep</body></html>' > "${work}/web/v3/static/site/pages/error-404/index.html"
  # No <head>, only <header>: must be skipped rather than patched inside the <header> element.
  printf '<!doctype html><html><body><header>nav</header></body></html>' > "${work}/web/v3/no-head.html"
  printf '<!doctype html><html><head></head><body>caf\xe9</body></html>' > "${work}/web/v3/latin1.html"
  cp "${work}/web/v3/latin1.html" "${work}/latin1.orig"
}

# A snippet as emitted by the earlier revision: one relative reference, no closing marker.
make_legacy_snippet() {
  printf '<!doctype html><html><head>%s<script src="../v3/zh-CN.js"></script></head><body>hi</body></html>' \
    "${START_MARKER}" > "${work}/web/v3/local-agent.html"
}

echo "apply"
make_tree
run_apply "${work}/out" "${work}/web"
check "apply exits 0"                         "0" "${APPLY_STATUS}"
check "absolute reference at the web root"    "1" "$(count_matching "${work}/web/index.html" 'src="/v3/zh-CN.js"')"
check "relative reference at the web root"    "1" "$(count_matching "${work}/web/index.html" 'src="v3/zh-CN.js"')"
check "absolute reference inside v3"          "1" "$(count_matching "${work}/web/v3/local-agent.html" 'src="/v3/zh-CN.js"')"
check "relative reference inside v3"          "1" "$(count_matching "${work}/web/v3/local-agent.html" 'src="../v3/zh-CN.js"')"
check "relative reference at depth"           "1" "$(count_matching "${work}/web/v3/static/site/pages/error-404/index.html" 'src="../../../../../v3/zh-CN.js"')"
check "snippet is closed by a marker"         "1" "$(count_matching "${work}/web/v3/local-agent.html" "${END_MARKER}")"
check "translator installed"                  "1" "$([ -f "${work}/web/v3/zh-CN.js" ] && echo 1 || echo 0)"
check "dictionary installed"                  "1" "$([ -f "${work}/web/v3/zh-CN.json" ] && echo 1 || echo 0)"
check "patches 3 of 5, skipping the rest"     "patched 3 of 5 HTML file(s)" "$(summary "${work}/out")"
check "reports what it skipped"               "1" "$(count_matching "${work}/out" '^skipped 2 file(s)')"
check "head-less file left untouched"         "0" "$(count_matching "${work}/web/v3/no-head.html" "${START_MARKER}")"
check "non-UTF-8 file left untouched"         "0" "$(count_matching "${work}/web/v3/latin1.html" "${START_MARKER}")"

echo "apply: idempotent"
run_apply "${work}/out2" "${work}/web"
check "second run exits 0"                    "0" "${APPLY_STATUS}"
check "second run patches nothing"            "patched 0 of 5 HTML file(s)" "$(summary "${work}/out2")"
check "no duplicate snippet"                  "1" "$(count_matching "${work}/web/index.html" "${START_MARKER}")"

echo "apply: upgrades a snippet from an earlier revision"
make_tree
make_legacy_snippet
run_apply "${work}/out3" "${work}/web"
check "upgrade exits 0"                       "0" "${APPLY_STATUS}"
check "legacy snippet replaced, not doubled"  "1" "$(count_matching "${work}/web/v3/local-agent.html" "${START_MARKER}")"
check "upgraded file gains the marker pair"   "1" "$(count_matching "${work}/web/v3/local-agent.html" "${END_MARKER}")"
check "upgraded file gains the absolute ref"  "1" "$(count_matching "${work}/web/v3/local-agent.html" 'src="/v3/zh-CN.js"')"

echo "uninstall: --dry-run must not delete"
make_tree
run_apply "${work}/out4" "${work}/web"
run_apply "${work}/out5" --dry-run --uninstall "${work}/web"
check "dry-run uninstall exits 0"             "0" "${APPLY_STATUS}"
check "reports the revert"                    "would revert 3 of 5 HTML file(s)" "$(summary "${work}/out5")"
check "translator still present"              "1" "$([ -f "${work}/web/v3/zh-CN.js" ] && echo 1 || echo 0)"
check "dictionary still present"              "1" "$([ -f "${work}/web/v3/zh-CN.json" ] && echo 1 || echo 0)"
check "HTML still patched"                    "1" "$(count_matching "${work}/web/index.html" "${START_MARKER}")"

echo "uninstall"
run_apply "${work}/out6" --uninstall "${work}/web"
check "uninstall exits 0"                     "0" "${APPLY_STATUS}"
check "translator removed"                    "0" "$([ -f "${work}/web/v3/zh-CN.js" ] && echo 1 || echo 0)"
check "dictionary removed"                    "0" "$([ -f "${work}/web/v3/zh-CN.json" ] && echo 1 || echo 0)"
check "every file restored"                   "0" "$(grep -rl -e "${START_MARKER}" -e "${END_MARKER}" "${work}/web" 2>/dev/null | wc -l | tr -d ' ')"
check "non-UTF-8 file untouched throughout"   "0" "$(cmp -s "${work}/web/v3/latin1.html" "${work}/latin1.orig" && echo 0 || echo 1)"

echo "uninstall: an earlier-revision snippet is removed too"
make_tree
make_legacy_snippet
run_apply "${work}/out7" --uninstall "${work}/web"
check "legacy uninstall exits 0"              "0" "${APPLY_STATUS}"
check "legacy snippet removed"                "0" "$(count_matching "${work}/web/v3/local-agent.html" "${START_MARKER}")"

echo "dictionary rejection"
reject_case() {
  local label="$1" body="$2"
  cp "${tool}/zh-CN.json" "${work}/dict.bak"
  printf '%s' "${body}" > "${tool}/zh-CN.json"
  set +e
  "${APPLY}" "${work}/web" > /dev/null 2>&1
  local status=$?
  set -e
  cp "${work}/dict.bak" "${tool}/zh-CN.json"
  check "rejects ${label}" "2" "${status}"
}
reject_case "malformed JSON"      '{"Nodes": '
reject_case "an empty translation" '{"Nodes": ""}'
reject_case "a non-string value"   '{"Nodes": 1}'
reject_case "a value that is also a key" '{"Nodes": "Alerts", "Alerts": "告警"}'
run_apply "${work}/out8" "${work}/web"
check "accepts the shipped dictionary"        "0" "${APPLY_STATUS}"

echo
if [ "${failures}" -eq 0 ]; then
  echo "all checks passed"
else
  echo "${failures} check(s) failed"
  exit 1
fi
