# 12. Observability and alerting on SLOs

Date: 2026-09-05

## Context

The platform should answer two questions without anyone logging into a pod:
is the service meeting its objectives, and if not, where is the time or the
error coming from. Alerts should fire on what users feel, not on every CPU
spike.

## Decision

- Metrics: Prometheus from kube-prometheus-stack. Workloads ship their own
  ServiceMonitor and PrometheusRule in their chart; Prometheus selects them in
  every namespace.
- Traces: the service exports OTLP with the OpenTelemetry SDK to a collector
  on its node, which forwards to Tempo. Metrics are not pushed over OTLP as
  well; Prometheus scraping stays the one metrics path.
- Logs: the same collector tails container logs on the node and sends them to
  Loki over OTLP. There is no separate log agent.
- Grafana connects the three: from a log line to its trace, from a trace to
  the logs of that request.
- Loki and Tempo keep data on local disks in the kind cluster and in S3 in
  the cloud, through Pod Identity. Everything else is identical.

Alerting is on SLOs, not on symptoms: availability (share of non 5xx
responses) and latency (share of requests under 250 ms), each with multi
window, multi burn rate alerts. A fast burn pages, a slow burn opens a ticket.
Probe requests are excluded from both ratios. Every alert links to a runbook
in `docs/runbooks`. The rules have promtool unit tests, run in CI against the
rules rendered for every environment.

## Consequences

Four more components per cluster, which is most of the memory the local
cluster needs. The SLO rules need a few days of traffic before the slow burn
windows mean anything; until then only the fast burn alerts are useful.
