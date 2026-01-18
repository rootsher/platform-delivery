# 5. Gateway API for traffic

Date: 2026-01-18

## Context

ingress-nginx, the default choice for years, is retired upstream and no longer
maintained. The Ingress resource itself is frozen, and anything beyond host and
path routing ends up in controller specific annotations.

## Decision

Traffic enters through Gateway API. The platform owns the Gateway, workloads
own their HTTPRoutes. The implementation behind it is a platform detail and can
differ between environments without touching the charts.

## Consequences

Gateway API needs its CRDs installed before anything else, which adds a step
to the bootstrap. Routes are portable between implementations as long as they
stay within the standard channel.
