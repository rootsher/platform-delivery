#!/usr/bin/env bash
# Renders every cluster and every environment the way ArgoCD would, then
# checks the result against the Kubernetes and CRD schemas and against the
# admission policies. A change that would be rejected in a cluster fails here,
# in the pull request, instead.
set -euo pipefail

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

schemas=(
  -schema-location default
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
)
validate() { kubeconform -strict -summary -kubernetes-version 1.36.0 "${schemas[@]}" "$@"; }

for cluster in clusters/*/; do
  env=$(basename "$cluster")
  echo "== $env"

  helm template root charts/platform-apps -f "$cluster/platform.yaml" >"$out/$env-apps.yaml"
  kubectl kustomize "$cluster/gateway" >"$out/$env-gateway.yaml"
  validate "$out/$env-apps.yaml" "$out/$env-gateway.yaml" "$cluster/root.yaml" "$cluster/secrets"

  for dir in "environments/$env"/*/; do
    workload=$(basename "$dir")
    rendered="$out/$env-$workload.yaml"
    helm template "$workload" "charts/$workload" -f "$dir/values.yaml" \
      | yq ".metadata.namespace = \"$workload\"" >"$rendered"
    validate "$rendered"

    # The namespace labels are the ones the workloads ApplicationSet sets.
    cat >"$out/values.yaml" <<VALUES
apiVersion: cli.kyverno.io/v1alpha1
kind: Values
namespaceSelector:
  - name: $workload
    labels:
      platform.rootsher.dev/tier: workload
VALUES
    # verify-images needs the registry and Rekor, so it is left to admission.
    kyverno apply platform/policies/workload-images.yaml platform/policies/workload-resources.yaml \
      --resource "$rendered" --values-file "$out/values.yaml" --table
  done
done
