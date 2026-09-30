#!/usr/bin/env bash
# Compares the values clusters/<env>/platform.yaml takes from Terraform with
# the outputs of the applied stack. Needs credentials that can read the
# state. Run by make bootstrap before anything is installed.
set -euo pipefail

env=${1:?usage: scripts/check-outputs.sh <staging|prod>}
values=clusters/$env/platform.yaml

terraform -chdir=infra/aws/stack init -input=false -reconfigure \
  -backend-config="env/$env.s3.tfbackend" >/dev/null
outputs=$(terraform -chdir=infra/aws/stack output -json)

failed=0
check() {
  local output=$1 path=$2 want got
  want=$(jq -r "$output" <<<"$outputs")
  got=$(yq "$path" "$values")
  if [[ $want != "$got" ]]; then
    echo "check-outputs: $values $path is $got, terraform says $want" >&2
    failed=1
  fi
}

check .cluster_name.value .components.awsLoadBalancerController.clusterName
check .vpc_id.value .components.awsLoadBalancerController.vpcId
check .telemetry_buckets.value.loki .components.loki.loki.storage.bucketNames.chunks
check .telemetry_buckets.value.tempo .components.tempo.tempo.storage.trace.s3.bucket

exit $failed
