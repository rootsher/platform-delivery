# Release drill

Shows on the local cluster what a bad release does, end to end: a version
that fails a share of requests while its pods stay ready is released through
git, the canary analysis stops it, and a revert puts git back. Run it after
changing anything in the release path: the chart's Rollout, the analysis,
the PodMonitor or the controller.

The fault is the backend's `FAULT_ERROR_RATE`, set through `faultErrorRate`
in `environments/local`. The parity check allows that key there and nowhere
else.

## Release the bad version

```sh
yq -i '.faultErrorRate = 0.3' environments/local/sample-backend/values.yaml
git commit -am "chore(local): release drill, fail 30% of requests"
git push
```

ArgoCD picks it up within its polling interval, or at once with a refresh
from the UI. The Rollout starts a canary with the new pod template and gives
it 10% of the route.

## Watch it get stopped

The analysis only sees requests, so send some through the Gateway:

```sh
while true; do curl -s -o /dev/null -w '%{http_code}\n' http://notes.localhost:8080/api/notes; sleep 0.2; done
```

About 3% of those fail (30% of the canary's 10%). Within the analysis delay
and two failed measurements, a little over two minutes, the controller
aborts:

```sh
kubectl argo rollouts get rollout sample-backend -n sample-backend --watch
```

The status turns Degraded, the weights on the HTTPRoute go back to 100 for
stable, the canary pod is deleted, and the curl loop stops seeing 500s.

## Put git back

```sh
git revert --no-edit HEAD
git push
```

After the sync the application is Healthy again, and the Rollout does not
start a canary for it: the reverted spec is the stable one. This is the same
step as in [sample-backend-release-aborted](sample-backend-release-aborted.md).
