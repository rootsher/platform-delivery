# platform-delivery

The platform side of a delivery flow: everything a service passes through
between a merged commit and a running pod, with no application code in it.
The service it delivers lives in
[platform-sample-backend](https://github.com/rootsher/platform-sample-backend).

**Local is smaller, not looser.** The kind cluster on a laptop runs the same
GitOps flow, the same database operator and the same policies as the cloud
environments. It has fewer replicas and less memory. It does not have fewer
rules.

## Flow

From a push in the service repo to a request served in a cluster. Dashed
lines lead to the staging and prod clusters, which are defined here but not
provisioned (ADR 7); locally the same flow runs end to end.

```mermaid
flowchart TB
  subgraph backend["platform-sample-backend CI"]
    direction LR
    push["push to main"] --> checks["lint, type check,<br/>tests on Postgres"]
    push --> scans["gitleaks, Semgrep"]
    checks --> build["image build<br/>(distroless, non-root)"]
    scans --> build
    build --> sbom["Syft SBOM"] --> grype["Grype scan"]
    grype --> publish["push to GHCR"]
    publish --> sign["cosign sign,<br/>SBOM and SLSA attestations"]
  end

  publish --> ghcr[("GHCR<br/>image by digest")]
  sign --> rekor[("Rekor<br/>transparency log")]

  subgraph repo["platform-delivery"]
    direction LR
    local["environments/local"]
    staging["environments/staging"]
    prod["environments/prod"]
  end

  sign -- "auto merged PR<br/>with the new digest" --> staging
  staging -- "promote workflow,<br/>reviewed PR" --> prod
  checks2["ci: render, schemas,<br/>policies, parity"] -.- repo

  subgraph cluster["cluster"]
    direction LR
    argocd["ArgoCD<br/>ApplicationSet"] --> admission{"admission:<br/>Pod Security restricted,<br/>Kyverno"}
    admission --> db["CloudNativePG cluster"] --> migrate["migration job"] --> api["API pods"]
    api --> gateway["Envoy Gateway"]
  end

  local --> argocd
  staging -.-> argocd
  prod -.-> argocd
  admission -- "signature and SBOM" --> rekor
  admission -- "pull by digest" --> ghcr
  gateway --> client(("client"))
```

The digest is the only thing that moves between environments. It is written
once by CI, checked at admission against the signature CI made, and a rollback
is a revert of the commit that changed it ([ADR 8](docs/adr/0008-rollback-by-digest.md)).

### Inside a cluster

`make up` does the first two steps by hand. Everything after that is ArgoCD
syncing this repo, in waves, each one waiting for the previous one to be
healthy.

```mermaid
flowchart TB
  kind["kind cluster"] --> install["helm install ArgoCD"] --> root["apply clusters/local/root.yaml"]
  root --> w3

  subgraph w3["wave -3: cloud clusters only"]
    sc["gp3 StorageClass"]
    lbc["AWS Load Balancer Controller"]
  end

  w3 --> w2

  subgraph w2["wave -2: operators and CRDs"]
    eg["Envoy Gateway<br/>(Gateway API CRDs)"]
    kyverno["Kyverno"]
    eso["external-secrets"]
    bao["OpenBao (local only)"]
  end

  w2 --> w1

  subgraph w1["wave -1: platform configuration and services"]
    gw["GatewayClass, Gateway"]
    pol["admission policies"]
    store["ClusterSecretStore"]
    cnpg["CloudNativePG operator"]
    obs["Prometheus, Grafana,<br/>Loki, Tempo, collector"]
  end

  w1 --> w0

  subgraph w0["wave 0: ArgoCD and workloads"]
    self["ArgoCD manages itself"]
    appset["workloads ApplicationSet"]
  end

  appset --> app

  subgraph app["one Application per workload"]
    direction LR
    cluster["wave -1<br/>Postgres cluster"] --> job["wave 0<br/>migration job, Service,<br/>HTTPRoute, alerts"] --> deploy["wave 1<br/>Deployment"]
  end
```

## Stack

| Layer | Tool | Role |
| --- | --- | --- |
| Local cluster | kind, Kubernetes 1.37 | one control plane and two workers, so spreading and failover are real |
| Packaging | Helm | one chart per workload; environments only supply values |
| GitOps | ArgoCD with ApplicationSet | app of apps from `clusters/<env>/root.yaml`; ArgoCD also manages itself |
| Database | CloudNativePG, Postgres 18 | a two instance cluster per workload; the operator writes the credentials Secret |
| Migrations | a Job from the release image | runs between the database and the new pods, from the same digest |
| Traffic | Gateway API, Envoy Gateway | the platform owns the Gateway, workloads own their HTTPRoutes |
| Secrets | external-secrets, OpenBao locally | Kubernetes auth into OpenBao; AWS Secrets Manager through Pod Identity in the cloud |
| Pod security | Pod Security Admission | restricted level on every workload namespace |
| Admission policies | Kyverno, CEL policy types | signed images, SBOM attestation, known registries, digests, requests and limits |
| Supply chain | cosign keyless, Rekor | signatures and attestations made in CI, verified again at admission |
| Promotion | GitHub Actions, a GitHub App | staging follows main by auto merged PRs; prod by a reviewed PR |
| Checks | kubeconform, Kyverno CLI, yq | every environment rendered and checked on every PR, plus a parity check |
| Dependencies | Renovate | charts, pinned images, actions and CI tools; platform changes are always reviewed |
| Runtime scanning | Grype, nightly | every digest deployed anywhere is rescanned; findings open an issue |
| Metrics and alerts | kube-prometheus-stack | ServiceMonitor and SLO burn rate rules shipped in the workload chart, tested with promtool |
| Traces and logs | OpenTelemetry collector, Tempo, Loki | one collector per node for traces and container logs; S3 in the cloud |
| Dashboards | Grafana | SLO dashboard from git, log to trace links |
| Cloud | EKS, AWS Secrets Manager, NLB | staging and prod as definitions: gp3 storage, TLS from Secrets Manager, HTTPS only |
| Infrastructure | Terraform, tflint, trivy | VPC, EKS on Bottlerocket, KMS, Pod Identity roles, Route 53; tested with a mocked provider |

### Telemetry

```mermaid
flowchart LR
  api["API pods"] -- "OTLP traces" --> otel["OpenTelemetry collector<br/>(one per node)"]
  pods["container logs<br/>on the node"] -- "filelog" --> otel
  otel -- traces --> tempo[("Tempo")]
  otel -- "logs over OTLP" --> loki[("Loki")]
  prom["Prometheus"] -- "scrapes /metrics" --> api
  prom -- "SLO burn rate rules" --> am["Alertmanager"]
  am -- "severity=page" --> pager(("pager"))
  am -- "severity=ticket" --> tickets(("tickets"))
  grafana["Grafana"] --> prom
  grafana --> tempo
  grafana --> loki
```

Every alert carries a link to its runbook in [docs/runbooks](docs/runbooks).

## Layout

```
bootstrap/       what has to exist before ArgoCD can manage the rest
charts/          Helm charts: the workloads, and platform-apps with one cluster's Applications
clusters/        per cluster: root app, its values, and what differs from others
environments/    one directory per environment, only values live here
platform/        manifests shared by every cluster (gateway, policies, dashboards)
scripts/         the smoke test and the checks CI runs
infra/aws/       Terraform: one root module, one variables file per environment
docs/adr/        decisions and the reasons behind them
docs/runbooks/   what to do when an alert fires
```

An environment is a directory. Adding one means adding values, not templates.

## Running it locally

Needs Docker, kind, kubectl, helm and jq, and about 10 GB of free memory.

```sh
make up        # cluster, ArgoCD, then everything else through GitOps
make password  # admin password for the ArgoCD UI
make down
```

`make up` only installs ArgoCD and applies `clusters/local/root.yaml`. From
there ArgoCD takes over managing itself, installs the operators and syncs the
workloads from `environments/local`. The last step is a smoke test that writes
a note through the Gateway and reads it back.

Once it is up, http://notes.localhost:8080/api/notes is the service,
http://argocd.localhost:8080 is ArgoCD and http://grafana.localhost:8080 is
Grafana (the admin password is in the `grafana-admin` Secret in `monitoring`).

ArgoCD reads this repo from GitHub, not from the working copy, so local changes
have to be pushed before the cluster sees them. While the repo is private, pass
a token that can read it: `make up REPO_TOKEN=$(gh auth token)`.

## Decisions

The reasoning is in [docs/adr](docs/adr). The short version:

- ArgoCD with a single ApplicationSet, environments as directories.
- CloudNativePG in every environment, including local.
- Gateway API for traffic.
- external-secrets everywhere, with a different store per environment.
- AWS is described in Terraform and checked without an account. Nothing is
  actually provisioned; the working end to end flow is the local one.
- Schema changes are expand then contract, so a rollback is a digest revert.
- Pod Security Admission at restricted plus Kyverno in Enforce mode in every
  environment and every namespace outside the platform's own: signed images
  by digest, known registries, requests and limits.
- Staging follows main through automatic pull requests; prod gets the digest
  staging already runs, through a reviewed pull request.
