# 9. Admission policies

Date: 2026-04-12

## Context

Scanning and signing in CI are only worth something if the cluster refuses
what did not go through them. Without admission control, anyone with deploy
access can run any image with any settings, and the pipeline becomes
a suggestion.

## Decision

Pod security uses the built in Pod Security Admission at the restricted level,
set as a label on every namespace that runs workloads. It needs no extra component and
covers non-root, dropped capabilities, seccomp and privilege escalation
exactly as the upstream standard defines them.

Kyverno covers what Pod Security Admission cannot:

- images from this account must be signed by the main branch CI workflow and
  carry a signed SBOM attestation,
- images must come from known registries and be pinned by digest,
- every container needs CPU and memory requests and a memory limit,
- namespaces must keep the restricted label.

The policies use Kyverno's CEL based policy types rather than the older
ClusterPolicy, and they run in Enforce mode in every environment, local
included. A policy in Audit mode is a report nobody reads.

The policies apply to every namespace except two kinds: the ones Kubernetes
itself owns (`kube-system` and friends) and platform namespaces, marked with
`platform.rootsher.dev/tier: platform`. Platform components come from upstream
charts and are not held to the workload rules. The exemption is opt in, not
the scope: a namespace nobody labelled is covered. Only ArgoCD, which sets the
label from this repo, or a cluster admin may put it on a namespace; for anyone
else the `platform-namespaces` policy denies it.

## Consequences

An image built on a laptop cannot run in any cluster, the local one included.
Trying a change end to end means pushing it through CI. That is slower, and it
is the point: the local cluster checks the same supply chain as production.
