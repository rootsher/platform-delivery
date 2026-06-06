#!/usr/bin/env bash
# Environments may differ in size, in the image they run and in their
# hostnames. Anything else would make one environment behave differently from
# another (ADR 2), so a values file that sets any other key fails the check.
set -euo pipefail

allowed='^(image\.digest|replicas|resources\..*|logLevel|database\.(instances|storage|storageClass|resources\..*)|route\..*)$'

status=0
for values in environments/*/*/values.yaml; do
  while read -r key; do
    if [[ ! $key =~ $allowed ]]; then
      echo "$values: $key is not an allowed per environment difference" >&2
      status=1
    fi
  done < <(yq '[.. | select(tag != "!!map" and tag != "!!seq") | path | join(".")] | .[]' "$values" | sed -E 's/\.[0-9]+$//' | sort -u)
done

# Every environment runs the same set of workloads.
reference=$(ls environments/local)
for env in environments/*/; do
  if [[ $(ls "$env") != "$reference" ]]; then
    echo "$env runs a different set of workloads than environments/local" >&2
    status=1
  fi
done

[[ $status -eq 0 ]] && echo "parity: environments differ only in allowed keys"
exit $status
