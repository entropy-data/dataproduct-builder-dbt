#!/usr/bin/env bash
# PostToolUse hook: lint ODCS data contracts after Write/Edit/MultiEdit.
#
# Runs `datacontract lint` on edits to datacontracts/*.odcs.{yaml,yml}.
# Other paths are silently passed through.
#
# Stdin: Claude Code tool-call JSON. Exit 0 on success or non-applicable file.
# Non-zero exit + stderr surfaces the lint failure to the agent.

set -euo pipefail

# Tolerate missing jq: parse the file path with a small Python fallback.
input=$(cat)
if command -v jq >/dev/null 2>&1; then
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
else
  file_path=$(printf '%s' "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)
fi

[ -n "${file_path:-}" ] || exit 0
[ -f "$file_path" ] || exit 0

# ODCS data contracts under datacontracts/
case "$file_path" in
  */datacontracts/*.odcs.yaml | */datacontracts/*.odcs.yml)
    if command -v datacontract >/dev/null 2>&1; then
      if ! out=$(datacontract lint "$file_path" 2>&1); then
        printf 'datacontract lint failed for %s:\n%s\n' "$file_path" "$out" >&2
        exit 1
      fi
    fi
    ;;
esac

exit 0
