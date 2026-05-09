CLUSTER := platform
CONTEXT := kind-$(CLUSTER)
KUBECTL := kubectl --context $(CONTEXT)

# The bootstrap install and the Application that later manages ArgoCD must use
# the same chart version, so it is read from the Application, not repeated.
ARGOCD_CHART := $(shell awk '/chart: argo-cd/ { getline; print $$2 }' charts/platform-apps/templates/argocd.yaml)

# Only needed while the repo is private. ArgoCD reads this repo from GitHub,
# not from the working copy, so it has to be able to authenticate.
REPO_TOKEN ?=

.PHONY: up down cluster argocd repo-creds root wait smoke password

up: cluster argocd repo-creds root wait smoke

cluster:
	@kind get clusters 2>/dev/null | grep -qx $(CLUSTER) || \
		kind create cluster --config clusters/local/kind.yaml

argocd:
	helm upgrade --install argocd argo-cd \
		--kube-context $(CONTEXT) \
		--repo https://argoproj.github.io/argo-helm --version $(ARGOCD_CHART) \
		--namespace argocd --create-namespace \
		--values bootstrap/argocd/values.yaml \
		--wait --timeout 10m
	@# Lets the ArgoCD UI attach its route to the platform Gateway.
	@$(KUBECTL) label namespace argocd platform.rootsher.dev/tier=platform --overwrite

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
	$(KUBECTL) apply -f clusters/local/root.yaml

# The workload Applications are created by the ApplicationSet, so they may not
# exist yet when this starts.
wait:
	@echo "waiting for local-sample-backend to be synced and healthy"
	@until $(KUBECTL) -n argocd get application local-sample-backend >/dev/null 2>&1; do sleep 5; done
	@$(KUBECTL) -n argocd wait application/local-sample-backend --timeout=15m \
		--for=jsonpath='{.status.health.status}'=Healthy
	@$(KUBECTL) -n argocd wait application/local-sample-backend --timeout=5m \
		--for=jsonpath='{.status.sync.status}'=Synced

smoke:
	@scripts/smoke.sh $(CONTEXT)

password:
	@$(KUBECTL) -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

down:
	kind delete cluster --name $(CLUSTER)
