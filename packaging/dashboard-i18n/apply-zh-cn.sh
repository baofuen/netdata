#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Apply (or revert) the Simplified Chinese dashboard localisation on an installed Netdata web
# directory.
#
# The Agent ships a prebuilt dashboard bundle, so localisation is applied to the installed files:
# this script installs zh-CN.js and zh-CN.json into the dashboard's v3 directory and references the
# script from every HTML entry point. Re-running it is a no-op; --uninstall reverses it.
#
# Usage:
#   apply-zh-cn.sh [--dry-run] [--uninstall] <web-dir>
#
#   <web-dir>   installed dashboard root, e.g. /usr/share/netdata/web
#               (in a container: docker exec <name> sh -c '.../apply-zh-cn.sh /usr/share/netdata/web')

set -euo pipefail

MARKER="netdata-zh-cn"
SCRIPT_NAME="zh-CN.js"
DICT_NAME="zh-CN.json"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
UNINSTALL=0
WEB_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: unknown option: $1" >&2; exit 2 ;;
    *) WEB_DIR="$1" ;;
  esac
  shift
done

if [ -z "${WEB_DIR}" ]; then
  echo "error: missing <web-dir>" >&2
  exit 2
fi

if [ ! -d "${WEB_DIR}" ]; then
  echo "error: not a directory: ${WEB_DIR}" >&2
  exit 2
fi

V3_DIR="${WEB_DIR}/v3"
if [ ! -d "${V3_DIR}" ]; then
  echo "error: ${WEB_DIR} does not look like a Netdata dashboard (no v3 directory)" >&2
  exit 2
fi

if [ "${DRY_RUN}" -eq 0 ] && [ "${UNINSTALL}" -eq 0 ]; then
  for f in "${SCRIPT_NAME}" "${DICT_NAME}"; do
    if [ ! -f "${HERE}/${f}" ]; then
      echo "error: missing ${HERE}/${f}" >&2
      exit 2
    fi
  done
  command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 2; }

  # A malformed dictionary does not break the dashboard, it silently disables the localisation, so
  # refuse to install one instead of shipping an English dashboard that looks applied.
  if ! python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as error:
    sys.exit("not valid JSON: %s" % error)
if not isinstance(data, dict):
    sys.exit("top level is %s, expected an object" % type(data).__name__)
bad = [k for k, v in data.items() if not isinstance(v, str)]
if bad:
    sys.exit("values must all be strings, found: %s" % ", ".join(map(str, bad[:5])))
' "${HERE}/${DICT_NAME}"; then
    echo "error: ${HERE}/${DICT_NAME} must be a JSON object mapping strings to strings" >&2
    exit 2
  fi
fi

if [ "${UNINSTALL}" -eq 1 ]; then
  echo "Removing localisation from ${WEB_DIR}"
  rm -f "${V3_DIR}/${SCRIPT_NAME}" "${V3_DIR}/${DICT_NAME}"
else
  echo "Installing localisation into ${WEB_DIR}"
  if [ "${DRY_RUN}" -eq 0 ]; then
    cp "${HERE}/${SCRIPT_NAME}" "${V3_DIR}/${SCRIPT_NAME}"
    cp "${HERE}/${DICT_NAME}" "${V3_DIR}/${DICT_NAME}"
  fi
fi

python3 - "${WEB_DIR}" "${DRY_RUN}" "${UNINSTALL}" "${MARKER}" "${SCRIPT_NAME}" <<'PY'
import os
import sys

web_dir, dry_run, uninstall, marker, script_name = (
    sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1", sys.argv[4], sys.argv[5],
)
web_dir = os.path.abspath(web_dir)
start_tag = "<!-- %s -->" % marker

changed = 0
scanned = 0

for root, _dirs, files in os.walk(web_dir):
    for name in sorted(files):
        if not name.endswith(".html"):
            continue
        scanned += 1
        path = os.path.join(root, name)
        with open(path, encoding="utf-8") as handle:
            content = handle.read()

        if uninstall:
            if start_tag not in content:
                continue
            start = content.index(start_tag)
            end = content.find("</script>", start)
            if end == -1:
                continue
            updated = content[:start] + content[end + len("</script>"):]
        else:
            if start_tag in content:
                continue
            head = content.find("<head")
            if head == -1:
                continue
            head_end = content.find(">", head)
            if head_end == -1:
                continue
            # Relative reference so the dashboard keeps working when served under a sub-path.
            relative_dir = os.path.relpath(root, web_dir)
            depth = 0 if relative_dir == "." else len(relative_dir.strip(os.sep).split(os.sep))
            src = "../" * depth + "v3/" + script_name
            snippet = '%s<script src="%s"></script>' % (start_tag, src)
            updated = content[:head_end + 1] + snippet + content[head_end + 1:]

        changed += 1
        if not dry_run:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(updated)

action = "would revert" if uninstall and dry_run else "reverted" if uninstall \
    else "would patch" if dry_run else "patched"
print("%s %d of %d HTML file(s)" % (action, changed, scanned))
PY

echo "Done."
