# 14. Canary releases with Argo Rollouts

Date: 2026-10-04

## Context

A rolling update replaces pods once they pass their readiness probe. A
release that fails a share of requests while `/readyz` stays green goes out
to everyone, and the first sign of it is the SLO alert, by which time the
error budget is already burning. Rollback stays a revert in git (ADR 8), but
someone has to notice first.

## Decision

The service ships as an Argo Rollouts `Rollout` instead of a `Deployment`.
A new pod template, which is what a new digest is, gets 10% of the HTTPRoute
for two minutes, then 50% for two minutes, then everything. Envoy Gateway
does the split; the controller moves the weights through the Gateway API
plugin. The steps are the same in every environment (ADR 2).

For the whole canary an analysis asks Prometheus for the canary's share of
5xx responses, probes excluded. The threshold is the availability error
budget, 0.5%, the number the SLO alerts burn against. Two failed
measurements abort the release: traffic goes back to the stable pods and the
canary is scaled down. A canary that is not ready within ten minutes is
aborted too. A canary that gets no requests passes; there is nothing to
judge, and the SLO alerts still watch it once it is out.

The abort is automatic, the revert in git is not. The controller does not
change the Rollout spec, so git still names the failed digest and ArgoCD
shows the application Synced and Degraded until someone reverts the
promotion pull request or releases a fix. That is a deliberate step for a
person: the analysis can be wrong, and a pull request that reverts
production should have someone behind it.

ArgoCD ignores the weights on workload HTTPRoutes, or selfHeal would undo
them. Pods are scraped through a PodMonitor carrying the pod template hash,
since the stable and canary Services overlap and a ServiceMonitor would count
every pod twice. Kyverno's CLI does not know Rollouts, so `scripts/check.sh`
runs the policies on the pod a Rollout would create.

## Consequences

A release takes about five minutes instead of one, and a bad one reaches a
tenth of the traffic for about two minutes before it is stopped. Telling a
bad release from a bad moment is up to the analysis, which only knows the
error rate; latency is still left to the SLO alerts.

Nothing pages on an aborted release. It shows in ArgoCD, and the drill in
`docs/runbooks/release-drill.md` shows the whole path on the local cluster.

The existing clusters had no workload running yet, so the Deployment was
replaced outright. On a live cluster the Rollout would first reference the
Deployment through `workloadRef` and take over its pods before the
Deployment is removed.
