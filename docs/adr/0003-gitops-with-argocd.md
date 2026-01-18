# 3. GitOps with ArgoCD and one ApplicationSet

Date: 2026-01-18

## Context

The cluster state should come from this repo and nothing else. Changes go
through pull requests, a rollback is a revert, and drift is visible instead of
silently accepted.

Flux and ArgoCD both do this well. ArgoCD was picked for its UI, which makes
the sync state easy to show, and for ApplicationSet, which generates one
Application per environment from a single template.

## Decision

ArgoCD is installed once per cluster by the bootstrap step and then manages
itself and everything else. A single ApplicationSet uses a git directory
generator over `environments/*`: each directory becomes an environment, and the
chart templates are shared. Environments differ only in values.

The image is referenced by digest, never by tag. Promotion is a change of that
digest in an environment's values.

## Consequences

Adding an environment is adding a directory. The cost is that per environment
differences have to be expressible as values; if something needs a different
template, that is a sign the chart is missing an option.
