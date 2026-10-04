# sample-backend: release aborted

The canary of a new release failed its analysis, or never got ready, and the
rollout controller aborted it. All traffic is back on the previous release
and the canary pods are gone. Users are fine; what is left is to make git
agree with what runs.

In ArgoCD the application is Synced but Degraded: git still names the new
digest, and so does the Rollout, but the pods serving are the previous ones.
The controller will not try the same release again on its own.

## Find out why

```sh
kubectl argo rollouts get rollout sample-backend -n sample-backend
kubectl -n sample-backend get analysisrun --sort-by=.metadata.creationTimestamp
kubectl -n sample-backend describe analysisrun <the last one>
```

- The error rate measurement failed: the canary answered too many 5xx. Look
  at its logs and traces in Grafana; the pod template hash in the analysis
  run is the label to filter on.
- The measurement errored: Prometheus did not answer. That says nothing
  about the release, see below.
- Progress deadline: the canary never got ready. Same causes as any pod that
  does not start, admission included.

## Put git back

Revert the promotion pull request, as for any rollback (ADR 8). Once ArgoCD
syncs it, the Rollout spec matches the pods that serve and the application
turns Healthy, without a new canary and without restarting anything.

Fixing forward works too: a new digest starts a fresh canary from the
current stable release.

## A false alarm

If the release was fine and the analysis was not (Prometheus was down, a
dependency failed at the same moment), run the canary again instead of
reverting:

```sh
kubectl argo rollouts retry rollout sample-backend -n sample-backend
```
