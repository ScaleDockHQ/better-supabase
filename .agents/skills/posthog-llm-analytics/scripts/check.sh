#!/usr/bin/env bash
# Read-only PostHog AI Observability check. Needs bash 3.2+; curl and jq optional. Prints variable NAMES and versions, never values.
# Usage: scripts/check.sh   (POSTHOG_HOST optional, default https://us.i.posthog.com)
set -uo pipefail
echo "-- SDKs"
(pip show posthog 2>/dev/null | grep -E '^(Name|Version)') || echo "posthog (python) not installed in this Python"
(pip show litellm 2>/dev/null | grep -E '^(Name|Version)') || echo "litellm not installed in this Python"
[ -f package.json ] && jq -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries[] | select(.key | test("^(@posthog/ai|posthog-node)$")) | "\(.key) \(.value)"' package.json 2>/dev/null
echo "-- env names present"
env | cut -d= -f1 | grep -E '^(POSTHOG_|OTEL_EXPORTER)' | sort || true
[ -n "${POSTHOG_API_KEY:-${POSTHOG_PROJECT_TOKEN:-}}" ] && echo "project token: set" || echo "project token: not set"
echo "-- reachability (any HTTP code means reachable)"
host="${POSTHOG_HOST:-https://us.i.posthog.com}"
code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$host/" 2>/dev/null || true)
echo "$host -> HTTP ${code:-none}"
echo "-- newest posthog on PyPI"
curl -fsS -m 8 https://pypi.org/pypi/posthog/json 2>/dev/null | jq -r .info.version 2>/dev/null || echo "lookup failed"
