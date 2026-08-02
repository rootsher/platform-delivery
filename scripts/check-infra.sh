#!/usr/bin/env bash
# Everything that can be checked about the AWS Terraform without an AWS
# account (ADR 7): formatting, validation, lint, a security scan, and the
# tests, which plan every module and both environments against a mocked
# provider and assert on the result.
set -euo pipefail

cd infra/aws

terraform fmt -check -recursive

for dir in modules/* stack; do
  echo "== $dir"
  terraform -chdir="$dir" init -backend=false -input=false >/dev/null
  terraform -chdir="$dir" validate -no-color
done

for dir in modules/*; do
  terraform -chdir="$dir" test -no-color
done
for env in staging prod; do
  terraform -chdir=stack test -no-color -var-file="env/$env.tfvars"
done

tflint --init --config "$PWD/.tflint.hcl" >/dev/null
tflint --recursive --config "$PWD/.tflint.hcl"

# Scanning the stack evaluates the modules with real inputs; scanning the
# modules alone would miss what the stack passes into them.
for env in staging prod; do
  trivy config --quiet --exit-code 1 --severity MEDIUM,HIGH,CRITICAL \
    --tf-vars "stack/env/$env.tfvars" stack
done
