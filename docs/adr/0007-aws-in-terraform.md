# 7. AWS in Terraform

Date: 2026-01-18

## Context

The cloud side (VPC, EKS, IAM, Pod Identity, DNS) should be plain Terraform
that anyone can read, review and run against an account, with every change
checked before it lands.

## Decision

The AWS environments are described in Terraform under `infra/aws` and every
change goes through `scripts/check-infra.sh`: `terraform validate`, tflint,
trivy config and `terraform test`, which plans every module and both
environments and asserts on the result. The same flow also runs end to end
locally, which is why ADR 2 matters.

## Consequences

Structural and policy mistakes are caught in CI, before a plan ever reaches an
account. The tests assert on the planned resources, so a module change that
breaks an environment fails there first.
