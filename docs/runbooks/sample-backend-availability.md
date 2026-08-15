# sample-backend: availability budget burning

The share of 5xx responses is high enough that the 99.5% monthly objective
will be gone within days (fast burn, pages) or before the end of the window
(slow burn, ticket). Probes are not counted, so this is real traffic failing.

## First five minutes

1. Did something just change? Check the last merged pull request touching
   `environments/<env>/sample-backend` and the sync history of the
   `<env>-sample-backend` Application in ArgoCD.
2. Is it the database? The readiness probe checks it, so a Postgres problem
   shows as pods dropping out of the endpoints:

   ```sh
   kubectl -n sample-backend get pods
   kubectl -n sample-backend get cluster sample-backend-db
   ```

3. Which routes fail? In Grafana, Explore on Prometheus:

   ```promql
   sum by (route) (rate(http_request_duration_seconds_count{namespace="sample-backend", status_code=~"5.."}[5m]))
   ```

   Then open a failing request in Tempo from the trace in the logs, or search
   Tempo for `service.name = sample-backend` with `status = error`.

## If the last release caused it

Roll back by reverting the pull request that changed the digest
([ADR 8](../adr/0008-rollback-by-digest.md)). ArgoCD syncs the previous digest
within a minute; the schema stays as it is, which the previous release is
written to handle.

```sh
git revert <merge commit of the promotion PR>
git push   # through a pull request for prod
```

Do not run a down migration as part of an incident response unless the new
schema itself is the cause. That is a separate, deliberate step, described in
[sample-backend-migration.md](sample-backend-migration.md).

## If the database is the cause

CloudNativePG fails over on its own when the primary is lost. If the cluster
is stuck, `kubectl cnpg status sample-backend-db -n sample-backend` shows which
instance is primary and why a replica is not being promoted.
