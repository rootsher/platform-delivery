# sample-backend: migration job failed

The migration Job runs in sync wave 0, after the database and before the new
pods. When it fails, ArgoCD stops the sync there: the previous release keeps
serving, and the new pods are never started. Nothing is broken for users yet,
but the release is stuck.

## Find out why

```sh
kubectl -n sample-backend logs job/sample-backend-migrate
kubectl -n sample-backend describe job sample-backend-migrate
```

- Denied by admission (event mentions Kyverno): the image is not signed by CI
  or not pinned by digest. It did not come from the pipeline; fix the values,
  not the policy.
- Cannot connect: check the database is healthy and the `sample-backend-db-app`
  Secret exists.
- SQL error: the migration itself is wrong. Revert the digest so the stuck
  sync goes away, and fix the migration in platform-sample-backend.

## Undoing a schema change on purpose

Only when a released migration has to be taken back. Run the down migration
from the image of the release that introduced it (only that image contains
it), then revert the digest:

```sh
kubectl -n sample-backend get job sample-backend-migrate -o yaml \
  | yq '.metadata = {"name": "migrate-down", "namespace": "sample-backend"}
        | del(.spec.selector) | del(.status)
        | del(.spec.template.metadata.labels["batch.kubernetes.io/controller-uid"])
        | del(.spec.template.metadata.labels["batch.kubernetes.io/job-name"])
        | del(.spec.template.metadata.labels["controller-uid"])
        | del(.spec.template.metadata.labels["job-name"])
        | .spec.template.spec.containers[0].args[1] = "down"' \
  | kubectl apply -f -
kubectl -n sample-backend wait --for=condition=complete job/migrate-down --timeout=5m
```

The migration Job is kept for a day after it finishes. If it is gone, render
it from the chart at the release's digest with `helm template` instead.

Then revert the promotion pull request as usual.
