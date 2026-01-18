# 7. AWS as definitions only

Date: 2026-01-18

## Context

The cloud side (VPC, EKS, IAM, Pod Identity, ECR, DNS) should be real
Terraform that would work against an account. Keeping an EKS cluster running
for a portfolio project is not worth the cost.

## Decision

The AWS environments are described in Terraform and checked without an
account: `terraform validate`, tflint, trivy config and `terraform test` with
mocked providers. Nothing is applied. The flow that actually runs end to end is
the local one, which is why ADR 2 matters.

## Consequences

The Terraform is verified for structure and policy, not for behaviour against
real AWS APIs. Some errors only show up on a real apply, and this setup will
not catch them.
