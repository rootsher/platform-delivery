# ENV picks the cluster: local is kind on this machine, staging and prod are
# the EKS clusters from infra/aws. `make up` is local only; `make bootstrap
# ENV=staging` does the same for a cloud cluster that Terraform already built.
ENV ?= local
CLUSTER := platform

ifeq ($(ENV),local)
CONTEXT := kind-$(CLUSTER)
else
CONTEXT := $(CLUSTER)-$(ENV)
EKS_CLUSTER = $(shell yq '.components.awsLoadBalancerController.clusterName' clusters/$(ENV)/platform.yaml)
REGION = $(shell yq '.components.awsLoadBalancerController.region' clusters/$(ENV)/platform.yaml)
ifneq ($(filter up cluster smoke down,$(MAKECMDGOALS)),)
$(error up, cluster, smoke and down are for the local cluster; use make bootstrap ENV=$(ENV))
endif
endif

ifeq ($(wildcard clusters/$(ENV)/root.yaml),)
$(error no cluster called $(ENV) in clusters/)
endif

KUBECTL := kubectl --context $(CONTEXT)

# The bootstrap install and the Application that later manages ArgoCD must use
# the same chart version, so it is read from the Application, not repeated.
ARGOCD_CHART := $(shell awk '/chart: argo-cd/ { getline; print $$2 }' charts/platform-apps/templates/argocd.yaml)

# Only needed while the repo is private. ArgoCD reads this repo from GitHub,
# not from the working copy, so it has to be able to authenticate.
REPO_TOKEN ?=

.PHONY: up bootstrap down cluster kubeconfig outputs argocd repo-creds root wait smoke password check check-infra

up: cluster bootstrap smoke

bootstrap: kubeconfig outputs argocd repo-creds root wait

cluster:
	@kind get clusters 2>/dev/null | grep -qx $(CLUSTER) || \
		kind create cluster --config clusters/local/kind.yaml

kubeconfig:
ifneq ($(ENV),local)
	aws eks update-kubeconfig --name $(EKS_CLUSTER) --region $(REGION) --alias $(CONTEXT)
endif

# clusters/<env>/platform.yaml carries values that come from Terraform. A
# cluster bootstrapped with stale ones would put the load balancer in the
# wrong VPC, so this stops first.
outputs:
ifneq ($(ENV),local)
	@scripts/check-outputs.sh $(ENV)
endif

# Installed with the same values the argocd Application uses later, including
# this cluster's, so the handover to ArgoCD changes nothing.
argocd:
	yq '.components.argocd // {}' clusters/$(ENV)/platform.yaml | \
	helm upgrade --install argocd argo-cd \
		--kube-context $(CONTEXT) \
		--repo https://argoproj.github.io/argo-helm --version $(ARGOCD_CHART) \
		--namespace argocd --create-namespace \
		--values bootstrap/argocd/values.yaml --values - \
		--wait --timeout 10m

repo-creds:
ifneq ($(REPO_TOKEN),)
	@$(KUBECTL) -n argocd create secret generic github-rootsher \
		--from-literal=type=git \
		--from-literal=url=https://github.com/rootsher \
		--from-literal=username=x-access-token \
		--from-literal=password=$(REPO_TOKEN) \
		--dry-run=client -o yaml \
	| $(KUBECTL) label --local -f - -o yaml argocd.argoproj.io/secret-type=repo-creds \
	| $(KUBECTL) apply -f -
endif

root:
	$(KUBECTL) apply -f clusters/$(ENV)/root.yaml

# The workload Applications are created by the ApplicationSet, so they may not
# exist yet when this starts.
wait:
	@echo "waiting for $(ENV)-sample-backend to be synced and healthy"
	@until $(KUBECTL) -n argocd get application $(ENV)-sample-backend >/dev/null 2>&1; do sleep 5; done
	@$(KUBECTL) -n argocd wait application/$(ENV)-sample-backend --timeout=15m \
		--for=jsonpath='{.status.health.status}'=Healthy
	@$(KUBECTL) -n argocd wait application/$(ENV)-sample-backend --timeout=5m \
		--for=jsonpath='{.status.sync.status}'=Synced

smoke:
	@scripts/smoke.sh $(CONTEXT)

password:
	@$(KUBECTL) -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

# The same checks CI runs on every pull request.
check:
	@scripts/check.sh
	@scripts/check-parity.sh

check-infra:
	@scripts/check-infra.sh

down:
	kind delete cluster --name $(CLUSTER)
