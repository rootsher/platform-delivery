#!/usr/bin/env bash
# Goes through the service the way a client would, through the Gateway: write
# a note, read it back.
set -euo pipefail

context=${1:-kind-platform}
base=${BASE_URL:-http://notes.localhost:8080}

# Healthy means fully promoted: no canary step or analysis still running.
kubectl --context "$context" -n sample-backend wait rollout/sample-backend --timeout=5m \
  --for=jsonpath='{.status.phase}'=Healthy

# The route can lag behind the rollout while Envoy picks up the new endpoints.
for _ in $(seq 60); do
  curl -fs "$base/api/notes?limit=1" >/dev/null && break
  sleep 1
done

title="smoke $(date +%s)"
id=$(curl -fsS -X POST "$base/api/notes" \
  -H 'content-type: application/json' \
  -d "{\"title\": \"$title\", \"body\": \"written by make smoke\"}" | jq -r .id)

got=$(curl -fsS "$base/api/notes/$id" | jq -r .title)
if [[ "$got" != "$title" ]]; then
  echo "smoke: expected note $id to have title '$title', got '$got'" >&2
  exit 1
fi
echo "smoke: note $id written and read back through the gateway"
