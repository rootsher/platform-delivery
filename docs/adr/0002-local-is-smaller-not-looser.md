# 2. Local is smaller, not looser

Date: 2026-01-18

## Context

The usual shortcut for local environments is to swap things out: a plain
Postgres container instead of the operator, a Secret in a file instead of the
secret store, policies off because they get in the way. Each swap is
reasonable on its own. Together they mean the first place the real setup runs
is a shared environment, and the first person to find a broken policy or
a missing permission is whoever deploys next.

## Decision

The local kind cluster runs the same components as the cloud environments:
ArgoCD, CloudNativePG, Gateway API, external-secrets and the same admission
policies in Enforce mode. What changes between environments is size (replicas,
requests, storage) and the providers behind the same interfaces (a local
secret store instead of a cloud one, a NodePort instead of a load balancer).

A difference between local and cloud that is not about size or provider needs
its own record explaining why.

## Consequences

The local cluster is heavier than it could be and needs a machine with
a reasonable amount of memory. In exchange a change that works locally has
already been through the policies, the GitOps sync and the migrations job that
the cloud environments use.
