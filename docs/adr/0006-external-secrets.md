# 6. external-secrets in every environment

Date: 2026-01-18

## Context

Secrets should not live in git, not even encrypted, and the way a workload
receives them should not depend on where it runs.

## Decision

Workloads get secrets from ExternalSecret objects, which are the same in every
environment. Only the SecretStore changes: OpenBao locally, AWS Secrets Manager
in the cloud, reached through EKS Pod Identity so there are no static AWS keys
anywhere.

Database credentials are the exception. CloudNativePG generates them and
writes the Secret itself, so there is nothing to fetch.

## Consequences

Locally there is one more component to run and seed. The benefit is that
a missing or misnamed secret fails in the same way on a laptop as in
production.
