# platform-delivery

The platform side of a delivery flow: everything a service passes through
between a merged commit and a running pod, with no application code in it.
The service it delivers lives in
[platform-sample-backend](https://github.com/rootsher/platform-sample-backend).

**Local is smaller, not looser.** The kind cluster on a laptop runs the same
GitOps flow, the same database operator and the same policies as the cloud
environments. It has fewer replicas and less memory. It does not have fewer
rules.

## Layout

```
bootstrap/       what has to exist before ArgoCD can manage the rest
charts/          Helm charts for the workloads
environments/    one directory per environment, only values live here
clusters/        cluster definitions (kind locally)
docs/adr/        decisions and the reasons behind them
```

An environment is a directory. Adding one means adding values, not templates.

## Running it locally

Needs Docker, kind, kubectl, helm and jq, and about 6 GB of free memory.

```sh
make up        # cluster, ArgoCD, then everything else through GitOps
make password  # admin password for the ArgoCD UI
make down
```

`make up` only installs ArgoCD and applies `clusters/local/root.yaml`. From
there ArgoCD takes over managing itself, installs the operators and syncs the
workloads from `environments/local`. The last step is a smoke test that writes
a note through the API and reads it back.

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
