# 4. CloudNativePG in every environment

Date: 2026-01-18

## Context

In AWS the default answer for Postgres is RDS. Locally there is no RDS, so the
local setup would use something else, and the two would differ in how the
database is created, how credentials reach the application, how backups work
and how upgrades happen. That is exactly the kind of gap ADR 2 rules out.

## Decision

Postgres runs on CloudNativePG in every environment. The operator creates the
cluster, the application role and a Secret with the connection details, and
the workload reads that Secret the same way everywhere. In the cloud the
difference is storage class, instance count and backups to object storage.

## Consequences

The database is operated by the platform instead of by AWS. That means owning
backups, upgrades and failover, which the operator automates but does not make
free. For this project the consistency is worth more than the managed service.
