#!/usr/bin/env bash
# Goes through the service the way a client would: write a note, read it back.
# Uses a port-forward until the Gateway is in place.
set -euo pipefail

context=${1:-kind-platform}
port=18080
kubectl=(kubectl --context "$context" -n sample-backend)
log=$(mktemp)
forward=

cleanup() {
  [[ -n $forward ]] && kill "$forward" 2>/dev/null
  rm -f "$log"
}
trap cleanup EXIT

"${kubectl[@]}" rollout status deploy/sample-backend --timeout=5m

# A port-forward attaches to a single pod and dies with it, which happens when
# the check runs right after a rollout. Start it again until the service answers.
ready=
for _ in $(seq 60); do
  if [[ -z $forward ]] || ! kill -0 "$forward" 2>/dev/null; then
    "${kubectl[@]}" port-forward svc/sample-backend "$port:80" >"$log" 2>&1 &
    forward=$!
  fi
  if curl -fs "localhost:$port/readyz" >/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
if [[ -z $ready ]]; then
  echo "smoke: service did not become ready through the port-forward" >&2
  cat "$log" >&2
  exit 1
fi

title="smoke $(date +%s)"
id=$(curl -fsS -X POST "localhost:$port/api/notes" \
  -H 'content-type: application/json' \
  -d "{\"title\": \"$title\", \"body\": \"written by make smoke\"}" | jq -r .id)

got=$(curl -fsS "localhost:$port/api/notes/$id" | jq -r .title)
if [[ "$got" != "$title" ]]; then
  echo "smoke: expected note $id to have title '$title', got '$got'" >&2
  exit 1
fi
echo "smoke: note $id written and read back"
