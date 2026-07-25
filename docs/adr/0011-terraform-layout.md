# 11. One Terraform root, environments as variables

Date: 2026-07-25

## Context

The AWS side needs a VPC, an EKS cluster and a handful of IAM roles per
environment. The common layouts are a directory per environment that calls
shared modules, or a single root module applied with a different variables
file per environment.

## Decision

`infra/aws/stack` is the only root module. `env/<environment>.tfvars` holds
what differs, which is size and addressing, and
`env/<environment>.s3.tfbackend` points each environment at its own state in
its own account. It is the same rule as for the Kubernetes side: an
environment is values, not a copy of the code.

The modules are small and written here rather than taken from the community
modules. Those cover every option AWS has; these cover what this platform uses,
which keeps them readable in a review and testable with `terraform test` and
a mocked provider. IAM policies are built with `jsonencode` instead of
`aws_iam_policy_document`, so the tests can assert on their real content.

Every AWS permission a workload needs goes through EKS Pod Identity. There is
no OIDC provider and no role annotation on service accounts, and the node role
carries only what the kubelet itself needs.

GHCR stays the only registry. An ECR pull through cache was considered: it
would change image references in the cloud and make the admission policies
and the values differ from local, for a latency gain that does not matter at
this size.

## Consequences

Staging and prod cannot drift structurally, because there is nothing to drift:
a new resource lands in both or in neither. A change that should only reach
staging first has to be gated by a variable, which is visible in review.
