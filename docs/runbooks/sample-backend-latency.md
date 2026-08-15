# sample-backend: latency budget burning

Too many requests take longer than 250 ms. Fast burn pages, slow burn opens
a ticket.

## Where the time goes

1. Pick a slow request in Tempo: `service.name = sample-backend` and
   `duration > 250ms`. The spans split the time between Fastify, the route
   handler and each Postgres query.
2. If the time is in Postgres, check whether the database is starved:

   ```sh
   kubectl -n sample-backend top pods
   kubectl -n sample-backend get cluster sample-backend-db -o jsonpath='{.status.instancesStatus}'
   ```

3. If the time is in the pods, check CPU throttling is not the cause. The
   chart sets no CPU limit on purpose, so look for nodes running out of CPU
   instead:

   ```sh
   kubectl top nodes
   ```

## Mitigation

- A release made it worse: revert the digest, as in
  [sample-backend-availability.md](sample-backend-availability.md).
- Load grew: raise `replicas` in `environments/<env>/sample-backend/values.yaml`
  through a pull request. Scaling by hand gets reverted by ArgoCD.
