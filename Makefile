NAME ?= $(shell yq .global.pattern values-global.yaml)

ifeq ($(NAME),)
$(error Pattern name MUST be set in values-global.yaml with the value .global.pattern)
endif
ifeq ($(NAME),null)
$(error Pattern name MUST be set in values-global.yaml with the value .global.pattern)
endif

ifneq ($(origin TARGET_SITE), undefined)
  TARGET_SITE_OPT=--set main.clusterGroupName=$(TARGET_SITE)
endif

# This variable can be set in order to pass additional helm arguments from the
# the command line. I.e. we can set things without having to tweak values files
EXTRA_HELM_OPTS ?=

# This variable can be set in order to pass additional ansible-playbook arguments from the
# the command line. I.e. we can set -vvv for more verbose logging
EXTRA_PLAYBOOK_OPTS ?=

# INDEX_IMAGES=registry-proxy.engineering.redhat.com/rh-osbs/iib:394248
# or
# INDEX_IMAGES=registry-proxy.engineering.redhat.com/rh-osbs/iib:394248,registry-proxy.engineering.redhat.com/rh-osbs/iib:394249
INDEX_IMAGES ?=

# git branch --show-current is also available as of git 2.22, but we will use this for compatibility
TARGET_BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)

# Cluster topology detection (auto-detect or override with CLUSTER_TOPOLOGY=sno)
CLUSTER_TOPOLOGY ?= $(shell ./scripts/detect-cluster-topology.sh 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "ha")
OCP_VERSION ?= $(shell ./scripts/detect-ocp-version.sh 2>/dev/null || echo "4.18")
ODF_CHANNEL ?= stable-$(OCP_VERSION)

# Export for scripts and Ansible
export CLUSTER_TOPOLOGY
export OCP_VERSION
export ODF_CHANNEL

#default to the branch remote
TARGET_ORIGIN ?= $(shell git config branch.$(TARGET_BRANCH).remote)

# The URL for the configured origin (could be HTTP/HTTPS/SSH)
TARGET_REPO_RAW := $(shell git ls-remote --get-url --symref $(TARGET_ORIGIN))

UUID_FILE ?= ~/.config/validated-patterns/pattern-uuid
UUID_HELM_OPTS ?=

# --set values always take precedence over the contents of -f
ifneq ("$(wildcard $(UUID_FILE))","")
	UUID := $(shell cat $(UUID_FILE))
	UUID_HELM_OPTS := --set main.analyticsUUID=$(UUID)
endif

# Set the secret name *and* its namespace when deploying from private repositories
# The format of said secret is documented here: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories
TOKEN_SECRET ?=
TOKEN_NAMESPACE ?= openshift-operators

# Set this to true if you want to skip any origin validation
# if TOKEN_SECRET is set to something then we skip the validation as well
DISABLE_VALIDATE_ORIGIN ?= false
ifeq ($(DISABLE_VALIDATE_ORIGIN),true)
  VALIDATE_ORIGIN :=
else ifneq ($(TOKEN_SECRET),)
  VALIDATE_ORIGIN :=
else
  VALIDATE_ORIGIN := validate-origin
endif


ifeq ($(TOKEN_SECRET),)
  # SSH agents are not created for public repos (repos with no secret token) by the patterns operator so we convert to HTTPS
  TARGET_REPO := $(shell echo "$(TARGET_REPO_RAW)" | sed 's/^git@\(.*\):\(.*\)/https:\/\/\1\/\2/')
  SECRET_OPTS :=
else
  TARGET_REPO := $(TARGET_REPO_RAW)
  SECRET_OPTS := --set main.tokenSecret=$(TOKEN_SECRET) --set main.tokenSecretNamespace=$(TOKEN_NAMESPACE)
endif

HELM_OPTS := -f values-global.yaml \
             -f values-clustergroup.yaml \
             --set main.git.repoURL="$(TARGET_REPO)" \
             --set main.git.revision=$(TARGET_BRANCH) \
             $(SECRET_OPTS) \
             $(TARGET_SITE_OPT) \
             $(UUID_HELM_OPTS) \
             $(EXTRA_HELM_OPTS)

# Helm does the right thing and fetches all the tags and detects the newest one
PATTERN_INSTALL_CHART ?= oci://quay.io/hybridcloudpatterns/pattern-install

##@ Pattern Common Tasks

.PHONY: help
help: ## This help message
	@echo "Pattern: $(NAME)"
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^(\s|[a-zA-Z_0-9-])+:.*?##/ { printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: install-prereqs-local
install-prereqs-local: ## Install local workstation prerequisites (RHEL 9/10)
	@echo "Installing local workstation prerequisites..."
	@./scripts/install-prerequisites-rhel.sh

.PHONY: configure-cluster
configure-cluster: ## Configure cluster infrastructure (scale nodes, install ODF)
	@echo "Configuring cluster infrastructure..."
	@echo "Detected cluster topology: $(CLUSTER_TOPOLOGY)"
	@echo "Detected OpenShift version: $(OCP_VERSION)"
	@CLUSTER_TOPOLOGY=$(CLUSTER_TOPOLOGY) OCP_VERSION=$(OCP_VERSION) ./scripts/configure-cluster-infrastructure.sh

.PHONY: configure-cluster-ha
configure-cluster-ha: ## Configure HighlyAvailable multi-node cluster
	@CLUSTER_TOPOLOGY=ha ./scripts/configure-cluster-infrastructure.sh

.PHONY: configure-cluster-sno
configure-cluster-sno: ## Configure SNO SingleReplica cluster
	@CLUSTER_TOPOLOGY=sno ./scripts/configure-cluster-infrastructure.sh

.PHONY: show-cluster-info
show-cluster-info: ## Display detected cluster information
	@echo "Cluster Information:"
	@echo "  Topology: $(CLUSTER_TOPOLOGY)"
	@echo "  OpenShift Version: $(OCP_VERSION)"
	@echo "  Platform: $(shell oc get infrastructure cluster -o jsonpath='{.status.platformStatus.type}' 2>/dev/null || echo 'Unknown')"
	@echo "  ODF Channel: $(ODF_CHANNEL)"
	@echo ""
	@./scripts/detect-cluster-topology.sh --verbose || true

.PHONY: install
install: operator-deploy load-secrets validate-deployment ## Install the pattern (deploy + load secrets + validate)

.PHONY: deploy-with-prereqs
deploy-with-prereqs: ## Deploy pattern with full prerequisites via Ansible (Hybrid Management Model - ADR-030)
	@echo "\n\n***************************** Deploying with Prerequisites (Hybrid Management Model) \n"
	@./scripts/deploy-with-prereqs.sh

.PHONY: deploy-prereqs-only
deploy-prereqs-only: ## Deploy only Ansible prerequisites (ESO, secrets, notebooks, cluster RBAC)
	@echo "\n\n***************************** Deploying Prerequisites Only \n"
	@echo "Running Ansible playbook with tags: prerequisites,common,secrets,notebooks,cluster-resources"
	@ansible-navigator run ansible/playbooks/deploy_complete_pattern.yml \
		--container-engine $(CONTAINER_ENGINE) \
		--execution-environment-image $(TARGET_NAME):$(TARGET_TAG) \
		--mode stdout \
		--tags "prerequisites,common,secrets,notebooks,cluster-resources" \
		--extra-vars "enable_operator=false enable_validation=false" \
		--eev $(HOME)/.kube:/runner/.kube:Z \
		--set-env KUBECONFIG=/runner/.kube/config \
		--eev $$(pwd):/runner/project:Z \
		--set-env ANSIBLE_ROLES_PATH=/runner/project/ansible/roles

#  Makefiles in the individual patterns should call these targets explicitly
#  e.g. from industrial-edge: make -f common/Makefile show
.PHONY: show
show: ## show the starting template without installing it
	helm template $(PATTERN_INSTALL_CHART) --name-template $(NAME) $(HELM_OPTS)

preview-all: ## (EXPERIMENTAL) Previews all applications on hub and managed clusters
	@echo "NOTE: This is just a tentative approximation of rendering all hub and managed clusters templates"
	@common/scripts/preview-all.sh $(TARGET_REPO) $(TARGET_BRANCH)

preview-%:
	$(eval CLUSTERGROUP ?= $(shell yq ".main.clusterGroupName" values-global.yaml))
	@common/scripts/preview.sh $(CLUSTERGROUP) $* $(TARGET_REPO) $(TARGET_BRANCH)

.PHONY: operator-deploy-prereqs
operator-deploy-prereqs: check-prerequisites load-env-secrets ## Run Ansible prerequisites for operator-deploy
	@echo "\n\n***************************** Running Ansible Prerequisites for operator-deploy \n"
	ansible-navigator run \
		ansible/playbooks/operator_deploy_prereqs.yml \
		--container-engine $(CONTAINER_ENGINE) \
		--execution-environment-image $(TARGET_NAME):$(TARGET_TAG) \
		--pull-policy never \
		--mode stdout \
		--eev $(HOME)/.kube:/runner/.kube:Z \
		--set-env KUBECONFIG=/runner/.kube/config \
		--eev $$(pwd):/runner/project:Z \
		--set-env ANSIBLE_ROLES_PATH=/runner/project/ansible/roles \
		$(EXTRA_VARS)

.PHONY: operator-deploy
operator-deploy operator-upgrade: operator-deploy-prereqs validate-prereq $(VALIDATE_ORIGIN) validate-cluster ## Run Ansible prereqs + helm install (RECOMMENDED)
	@echo "\n\n***************************** Running operator-deploy (Helm/VP Operator) \n"
	@common/scripts/deploy-pattern.sh $(NAME) $(PATTERN_INSTALL_CHART) $(HELM_OPTS)
	@echo "\n\n***************************** Running Post-Deployment Validation \n"
	@./scripts/post-deployment-hook.sh || true

.PHONY: operator-deploy-only
operator-deploy-only: validate-prereq $(VALIDATE_ORIGIN) validate-cluster ## Skip Ansible prereqs, run helm install only
	@common/scripts/deploy-pattern.sh $(NAME) $(PATTERN_INSTALL_CHART) $(HELM_OPTS)

.PHONY: uninstall
uninstall: ## runs helm uninstall
	$(eval CSV := $(shell oc get subscriptions -n openshift-operators openshift-gitops-operator -ojsonpath={.status.currentCSV}))
	helm uninstall $(NAME)
	@oc delete csv -n openshift-operators $(CSV)

.PHONY: load-secrets
load-secrets: ## loads the secrets into the backend determined by values-global setting
	common/scripts/process-secrets.sh $(NAME)

.PHONY: validate-deployment
validate-deployment: ## Run post-deployment validation
	@echo "\n\n***************************** Running Post-Deployment Validation \n"
	@./scripts/post-deployment-validation.sh

.PHONY: setup-eso-secrets
setup-eso-secrets: ## Setup secrets for External Secrets Operator (gitea-credentials, model-storage-config, etc.)
	@echo "Setting up External Secrets Operator secrets..."
	scripts/setup-secrets-eso.sh $(NAMESPACE)
	@echo "✅ ESO secrets setup complete"

.PHONY: legacy-load-secrets
legacy-load-secrets: ## loads the secrets into vault (only)
	common/scripts/vault-utils.sh push_secrets $(NAME)

.PHONY: secrets-backend-vault
secrets-backend-vault: ## Edits values files to use default Vault+ESO secrets config
	common/scripts/set-secret-backend.sh vault
	common/scripts/manage-secret-app.sh vault present
	common/scripts/manage-secret-app.sh golang-external-secrets present
	common/scripts/manage-secret-namespace.sh validated-patterns-secrets absent
	@git diff --exit-code || echo "Secrets backend set to vault, please review changes, commit, and push to activate in the pattern"

.PHONY: secrets-backend-kubernetes
secrets-backend-kubernetes: ## Edits values file to use Kubernetes+ESO secrets config
	common/scripts/set-secret-backend.sh kubernetes
	common/scripts/manage-secret-namespace.sh validated-patterns-secrets present
	common/scripts/manage-secret-app.sh vault absent
	common/scripts/manage-secret-app.sh golang-external-secrets present
	@git diff --exit-code || echo "Secrets backend set to kubernetes, please review changes, commit, and push to activate in the pattern"

.PHONY: secrets-backend-none
secrets-backend-none: ## Edits values files to remove secrets manager + ESO
	common/scripts/set-secret-backend.sh none
	common/scripts/manage-secret-app.sh vault absent
	common/scripts/manage-secret-app.sh golang-external-secrets absent
	common/scripts/manage-secret-namespace.sh validated-patterns-secrets absent
	@git diff --exit-code || echo "Secrets backend set to none, please review changes, commit, and push to activate in the pattern"

.PHONY: load-iib
load-iib: ## CI target to install Index Image Bundles
	@set -e; if [ x$(INDEX_IMAGES) != x ]; then \
		ansible-playbook $(EXTRA_PLAYBOOK_OPTS) rhvp.cluster_utils.iib_ci; \
	else \
		echo "No INDEX_IMAGES defined. Bailing out"; \
		exit 1; \
	fi

.PHONY: token-kubeconfig
token-kubeconfig: ## Create a local ~/.kube/config with password (not usually needed)
	common/scripts/write-token-kubeconfig.sh

##@ Validation Tasks

# If the main repoUpstreamURL field is set, then we need to check against
# that and not target_repo
.PHONY: validate-origin
validate-origin: ## verify the git origin is available
	@echo "Checking repository:"
	$(eval UPSTREAMURL := $(shell yq -r '.main.git.repoUpstreamURL // (.main.git.repoUpstreamURL = "")' values-global.yaml))
	@if [ -z "$(UPSTREAMURL)" ]; then\
		echo -n "  $(TARGET_REPO) - branch '$(TARGET_BRANCH)': ";\
		git ls-remote --exit-code --heads $(TARGET_REPO) $(TARGET_BRANCH) >/dev/null &&\
			echo "OK" || (echo "NOT FOUND"; exit 1);\
	else\
		echo "Upstream URL set to: $(UPSTREAMURL)";\
		echo -n "  $(UPSTREAMURL) - branch '$(TARGET_BRANCH)': ";\
		git ls-remote --exit-code --heads $(UPSTREAMURL) $(TARGET_BRANCH) >/dev/null &&\
			echo "OK" || (echo "NOT FOUND"; exit 1);\
	fi

.PHONY: validate-cluster
validate-cluster: ## Do some cluster validations before installing
	@echo "Checking cluster:"
	@echo -n "  cluster-info: "
	@oc cluster-info >/dev/null && echo "OK" || (echo "Error"; exit 1)
	@echo -n "  storageclass: "
	@if [ `oc get storageclass -o go-template='{{printf "%d\n" (len .items)}}'` -eq 0 ]; then\
		echo "WARNING: No storageclass found";\
	else\
		echo "OK";\
	fi


.PHONY: validate-schema
validate-schema: ## validates values files against schema in common/clustergroup
	$(eval VAL_PARAMS := $(shell for i in ./values-*.yaml; do echo -n "$${i} "; done))
	@echo -n "Validating clustergroup schema of: "
	@set -e; for i in $(VAL_PARAMS); do echo -n " $$i"; helm template oci://quay.io/hybridcloudpatterns/clustergroup $(HELM_OPTS) -f "$${i}" >/dev/null; done
	@echo

.PHONY: validate-prereq
validate-prereq: ## verify pre-requisites
	@common/scripts/validate-names-length.sh
	@if [ ! -f /run/.containerenv ]; then\
	  echo "Checking prerequisites:";\
	  echo -n "  Check for python-kubernetes: ";\
	  if ! ansible -m ansible.builtin.command -a "{{ ansible_python_interpreter }} -c 'import kubernetes'" localhost > /dev/null 2>&1; then echo "Not found"; exit 1; fi;\
	  echo "OK";\
	  echo -n "  Check for kubernetes.core collection: ";\
	  if ! ansible-galaxy collection list | grep kubernetes.core > /dev/null 2>&1; then echo "Not found"; exit 1; fi;\
	  echo "OK";\
	else\
		if [ -f values-global.yaml ]; then\
			OUT=`yq -r '.main.multiSourceConfig.enabled // (.main.multiSourceConfig.enabled = "false")' values-global.yaml`;\
			if [ "$${OUT,,}" = "false" ]; then\
				echo "You must set \".main.multiSourceConfig.enabled: true\" in your 'values-global.yaml' file";\
				echo "because your common subfolder is the slimmed down version with no helm charts in it";\
				exit 1;\
			fi;\
		fi;\
	fi

.PHONY: argo-healthcheck
argo-healthcheck: ## Checks if all argo applications are synced
	@echo "Checking argo applications"
	$(eval APPS := $(shell oc get applications.argoproj.io -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{","}{@.metadata.name}{"\n"}{end}'))
	@NOTOK=0; \
	for i in $(APPS); do\
		n=`echo "$${i}" | cut -f1 -d,`;\
		a=`echo "$${i}" | cut -f2 -d,`;\
		STATUS=`oc get -n "$${n}" applications.argoproj.io/"$${a}" -o jsonpath='{.status.sync.status}'`;\
		if [[ $$STATUS != "Synced" ]]; then\
			NOTOK=$$(( $${NOTOK} + 1));\
		fi;\
		HEALTH=`oc get -n "$${n}" applications.argoproj.io/"$${a}" -o jsonpath='{.status.health.status}'`;\
		if [[ $$HEALTH != "Healthy" ]]; then\
			NOTOK=$$(( $${NOTOK} + 1));\
		fi;\
		echo "$${n} $${a} -> Sync: $${STATUS} - Health: $${HEALTH}";\
	done;\
	if [ $${NOTOK} -gt 0 ]; then\
	    echo "Some applications are not synced or are unhealthy";\
	    exit 1;\
	fi


##@ Test and Linters Tasks

.PHONY: qe-tests
qe-tests: ## Runs the tests that QE runs
	@set -e; if [ -f ./tests/interop/run_tests.sh ]; then \
		pushd ./tests/interop; ./run_tests.sh; popd; \
	else \
		echo "No ./tests/interop/run_tests.sh found skipping"; \
	fi

.PHONY: test-deploy-complete-pattern
test-deploy-complete-pattern: ## Run E2E test for complete pattern deployment (development workflow)
	@echo "\n\n***************************** E2E Test: Complete Pattern Deployment \n"
	@./tests/integration/scripts/test-deploy-complete-pattern.sh $(if $(CLEANUP_AFTER_TEST),--cleanup-after) $(if $(DEBUG),--debug)

.PHONY: test-deploy-interactive
test-deploy-interactive: ## Run E2E test in interactive mode
	@echo "\n\n***************************** E2E Test: Interactive Mode \n"
	@./tests/integration/scripts/test-deploy-complete-pattern.sh --mode interactive

.PHONY: super-linter
super-linter: ## Runs super linter locally
	rm -rf .mypy_cache
	podman run -e RUN_LOCAL=true -e USE_FIND_ALGORITHM=true	\
					-e VALIDATE_ANSIBLE=false \
					-e VALIDATE_BASH=false \
					-e VALIDATE_CHECKOV=false \
					-e VALIDATE_DOCKERFILE_HADOLINT=false \
					-e VALIDATE_JSCPD=false \
					-e VALIDATE_JSON_PRETTIER=false \
					-e VALIDATE_MARKDOWN_PRETTIER=false \
					-e VALIDATE_PYTHON_PYLINT=false \
					-e VALIDATE_SHELL_SHFMT=false \
					-e VALIDATE_YAML=false \
					-e VALIDATE_YAML_PRETTIER=false \
					$(DISABLE_LINTERS) \
					-v $(PWD):/tmp/lint:rw,z \
					-w /tmp/lint \
					ghcr.io/super-linter/super-linter@sha256:6c71bd17ab38ceb7acb5b93ef72f5c2288b5456a5c82693ded3ee8bb501bba7f # slim-v8.1.0

.PHONY: deploy upgrade legacy-deploy legacy-upgrade
deploy upgrade legacy-deploy legacy-upgrade:
	@echo "UNSUPPORTED TARGET: please switch to 'operator-deploy'"; exit 1

##@ Execution Environment Build Targets

# Execution Environment Configuration
CONTAINER_ENGINE ?= podman
TARGET_NAME ?= openshift-aiops-platform-ee
TARGET_TAG ?= latest
VERBOSITY ?= 3
SOURCE_HUB ?= registry.redhat.io

.PHONY: build-ee test-ee list-ee clean-ee rebuild-ee push-ee check-token token check-prerequisites load-env-secrets test-openshift-tooling

# Check ANSIBLE_HUB_TOKEN only for targets that need it
# Use .PHONY target with a check that runs at execution time, not parse time
check-token: ## Verify ANSIBLE_HUB_TOKEN is set (from env or token file)
	@if [ -z "$$ANSIBLE_HUB_TOKEN" ]; then \
		if [ -f token ]; then \
			echo "Loading ANSIBLE_HUB_TOKEN from token file..."; \
			export ANSIBLE_HUB_TOKEN=$$(cat token); \
		else \
			echo "ERROR: The environment variable ANSIBLE_HUB_TOKEN is undefined and required for this target"; \
			echo "Set it with: export ANSIBLE_HUB_TOKEN=<your-token>"; \
			echo "Or create a 'token' file containing your token"; \
			exit 1; \
		fi; \
	fi

token: check-token ## Verify ANSIBLE_HUB_TOKEN and generate ansible.cfg from template
	@echo "\n\n***************************** Token Validation and Config Generation \n"
	@if [ -f token ]; then \
		export ANSIBLE_HUB_TOKEN=$$(cat token); \
	fi; \
	if [ -z "$$ANSIBLE_HUB_TOKEN" ]; then \
		echo "ERROR: ANSIBLE_HUB_TOKEN not set"; \
		exit 1; \
	fi; \
	echo "Generating ansible.cfg from template..."; \
	envsubst < files/ansible.cfg.template > ansible.cfg; \
	echo "✅ ansible.cfg generated successfully"; \
	echo "Pre-fetching collections to validate token..."; \
	mkdir -p collections; \
	ansible-galaxy collection download -r files/requirements.yml -p collections/ || (echo "WARNING: Collection pre-fetch failed (this may be normal if collections are already cached)" && exit 0); \
	echo "✅ Token validation complete"

rebuild-ee: clean-ee build-ee ## Clean and rebuild the execution environment image

build-ee: check-token ## Build the execution environment image
	@echo "\n\n***************************** Building Execution Environment \n"
	@if [ ! -f "execution-environment.yml" ]; then \
		echo "Error: execution-environment.yml not found"; \
		exit 1; \
	fi
	@if [ ! -f "ansible.cfg" ]; then \
		echo "Warning: ansible.cfg not found. Generating from template..."; \
		if [ -f token ]; then \
			export ANSIBLE_HUB_TOKEN=$$(cat token); \
		fi; \
		envsubst < files/ansible.cfg.template > ansible.cfg; \
	fi
	@echo "Building image: $(TARGET_NAME):$(TARGET_TAG)"
	ansible-builder build \
		--tag $(TARGET_NAME):$(TARGET_TAG) \
		--verbosity $(VERBOSITY) \
		--container-runtime $(CONTAINER_ENGINE)
	@echo "✅ Execution environment built successfully"
	@echo "Image: $(TARGET_NAME):$(TARGET_TAG)"

test-ee: ## Test the execution environment image
	@echo "\n\n***************************** Testing Execution Environment \n"
	@echo "Verifying image exists locally:"
	$(CONTAINER_ENGINE) images $(TARGET_NAME):$(TARGET_TAG)
	@echo "\nTesting Ansible version:"
	$(CONTAINER_ENGINE) run --rm $(TARGET_NAME):$(TARGET_TAG) ansible --version
	@echo "\nTesting Ansible collections:"
	$(CONTAINER_ENGINE) run --rm $(TARGET_NAME):$(TARGET_TAG) ansible-galaxy collection list
	@echo "\n✅ Execution environment test complete"

list-ee: ## List the built execution environment image
	@echo "\n\n***************************** Execution Environment Images \n"
	$(CONTAINER_ENGINE) images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}" --filter reference=$(TARGET_NAME):$(TARGET_TAG)

clean-ee: ## Clean execution environment build artifacts
	@echo "\n\n***************************** Cleaning Execution Environment \n"
	rm -rf my-pattern/context
	$(CONTAINER_ENGINE) rmi $(TARGET_NAME):$(TARGET_TAG) 2>/dev/null || true
	@echo "✅ Cleanup complete"

push-ee: ## Push execution environment to registry
	@echo "\n\n***************************** Pushing to Registry \n"
	@echo "Tagging $(TARGET_NAME):$(TARGET_TAG) for $(TARGET_HUB)"
	$(CONTAINER_ENGINE) tag $(TARGET_NAME):$(TARGET_TAG) \
		$(TARGET_HUB)/$(TARGET_NAME):$(TARGET_TAG)
	@echo "Pushing $(TARGET_HUB)/$(TARGET_NAME):$(TARGET_TAG)"
	$(CONTAINER_ENGINE) push $(TARGET_HUB)/$(TARGET_NAME):$(TARGET_TAG)
	@if [ "$(PUSH_LATEST)" = "true" ]; then \
		echo "Tagging and pushing latest..."; \
		$(CONTAINER_ENGINE) tag $(TARGET_NAME):$(TARGET_TAG) \
			$(TARGET_HUB)/$(TARGET_NAME):latest; \
		$(CONTAINER_ENGINE) push $(TARGET_HUB)/$(TARGET_NAME):latest; \
	fi
	@echo "✅ Image published to $(TARGET_HUB)/$(TARGET_NAME):$(TARGET_TAG)"

check-prerequisites: ## Validate cluster meets prerequisites (non-destructive check)
	@echo "\n\n***************************** Checking Prerequisites \n"
	ansible-navigator run \
		ansible/playbooks/test_prerequisites.yml \
		--container-engine $(CONTAINER_ENGINE) \
		--execution-environment-image $(TARGET_NAME):$(TARGET_TAG) \
		--pull-policy never \
		--mode stdout \
		--eev $$HOME/.kube:/runner/.kube:Z \
		--set-env KUBECONFIG=/runner/.kube/config

load-env-secrets: ## Load secrets from .env file into OpenShift (creates source secrets for ESO)
	@echo "\n\n***************************** Loading Secrets from .env \n"
	@if [ -f .env ]; then \
		. ./.env; \
		echo "Creating namespace if not exists..."; \
		oc create namespace self-healing-platform --dry-run=client -o yaml | oc apply -f - 2>/dev/null || true; \
		if [ -n "$$GITHUB_PAT" ]; then \
			echo "Creating GitHub PAT source secret..."; \
			oc create secret generic github-pat-credentials-source \
				--from-literal=username=tosin2013 \
				--from-literal=password="$$GITHUB_PAT" \
				-n self-healing-platform \
				--dry-run=client -o yaml | oc apply -f -; \
			echo "✅ GitHub PAT secret created"; \
		else \
			echo "⚠️  GITHUB_PAT not found in .env - skipping GitHub credentials"; \
		fi; \
		echo "Creating Gitea credentials source secret..."; \
		GITEA_USER=$${GITEA_USER:-opentlc-mgr}; \
		GITEA_PASSWORD=$${GITEA_PASSWORD:-openshift}; \
		oc create secret generic gitea-credentials-source \
			--from-literal=username="$$GITEA_USER" \
			--from-literal=password="$$GITEA_PASSWORD" \
			-n self-healing-platform \
			--dry-run=client -o yaml | oc apply -f -; \
		echo "✅ Gitea credentials source secret created"; \
	else \
		echo "⚠️  .env file not found - skipping secret loading"; \
	fi

.PHONY: deployment-help
deployment-help: ## Show recommended deployment workflow (operator-deploy)
	@echo "\n\n***************************** Deployment Workflow \n"
	@echo "============================================================================"
	@echo "RECOMMENDED WORKFLOW (Validated Patterns Framework)"
	@echo "============================================================================"
	@echo ""
	@echo "Step 1 - Build Execution Environment (if needed):"
	@echo "  $$ make build-ee"
	@echo ""
	@echo "Step 2 - Check cluster prerequisites:"
	@echo "  $$ make check-prerequisites"
	@echo ""
	@echo "Step 3 - Deploy pattern using operator-deploy (RECOMMENDED):"
	@echo "  $$ make operator-deploy"
	@echo ""
	@echo "  This will:"
	@echo "    - Run Ansible prerequisites (operator-deploy-prereqs)"
	@echo "    - Validate prerequisites and cluster"
	@echo "    - Deploy pattern via Helm + Validated Patterns Operator"
	@echo ""
	@echo "Step 4 - Load secrets (if needed):"
	@echo "  $$ make load-secrets"
	@echo ""
	@echo "Step 5 - Validate deployment:"
	@echo "  $$ make argo-healthcheck"
	@echo ""
	@echo "Step 6 - Cleanup when done:"
	@echo "  $$ make uninstall"
	@echo ""
	@echo "============================================================================"
	@echo "ALTERNATIVE: Skip Ansible prereqs (if already run):"
	@echo "============================================================================"
	@echo "  $$ make operator-deploy-only"
	@echo ""
	@echo "============================================================================"
	@echo "DOCUMENTATION"
	@echo "============================================================================"
	@echo "  - Validated Patterns: https://validatedpatterns.io/"
	@echo "  - Deployment workflow: my-pattern/DEPLOYMENT-WORKFLOW.md"
	@echo "  - ADR-019: Validated Patterns Framework Adoption"
	@echo ""

test-openshift-tooling: ## Test OpenShift/Kubernetes tooling in built image
	@echo "\n\n***************************** Testing OpenShift Tooling... \n"
	@bash scripts/test-openshift-tooling.sh $(TARGET_NAME):$(TARGET_TAG) $(CONTAINER_ENGINE)

##@ Jupyter Notebook Validator Operator

.PHONY: install-jupyter-validator
install-jupyter-validator: check-prerequisites ## Install Jupyter Notebook Validator Operator (kustomize)
	@echo "\n\n***************************** Installing Jupyter Notebook Validator Operator \n"
	@echo "🔍 Checking if operator is already installed..."
	@if oc get deployment notebook-validator-controller-manager -n jupyter-notebook-validator-operator >/dev/null 2>&1; then \
		READY=$$(oc get deployment notebook-validator-controller-manager -n jupyter-notebook-validator-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"); \
		if [ "$$READY" -ge 1 ]; then \
			echo "✅ Operator already installed and running ($$READY replicas ready)"; \
			echo "   Namespace: jupyter-notebook-validator-operator"; \
			echo "   Deployment: notebook-validator-controller-manager"; \
			echo ""; \
			echo "To reinstall, first run: make uninstall-jupyter-validator"; \
			exit 0; \
		else \
			echo "⚠️  Operator deployment exists but not ready. Proceeding with installation..."; \
		fi \
	fi
	@echo "📦 Method: kustomize (self-contained manifests in k8s/operators/jupyter-notebook-validator)"
	@echo "🎯 Target: OpenShift 4.18"
	@echo "🔧 Overlay: dev-ocp4.18 (image: 1.0.7-ocp4.18, webhooks enabled)"
	ansible-navigator run \
		ansible/playbooks/install_jupyter_validator_operator.yml \
		--container-engine $(CONTAINER_ENGINE) \
		--execution-environment-image $(TARGET_NAME):$(TARGET_TAG) \
		--pull-policy never \
		--mode stdout \
		--eev $(HOME)/.kube:/runner/.kube:Z \
		--set-env KUBECONFIG=/runner/.kube/config \
		--eev $$(pwd):/runner/project:Z \
		--set-env ANSIBLE_ROLES_PATH=/runner/project/ansible/roles \
		$(EXTRA_PLAYBOOK_OPTS)

.PHONY: uninstall-jupyter-validator
uninstall-jupyter-validator: ## Uninstall Jupyter Notebook Validator Operator
	@echo "\n\n***************************** Uninstalling Jupyter Notebook Validator Operator \n"
	ansible-navigator run \
		ansible/playbooks/uninstall_jupyter_validator_operator.yml \
		--container-engine $(CONTAINER_ENGINE) \
		--execution-environment-image $(TARGET_NAME):$(TARGET_TAG) \
		--pull-policy never \
		--mode stdout \
		--eev $(HOME)/.kube:/runner/.kube:Z \
		--set-env KUBECONFIG=/runner/.kube/config \
		--eev $$(pwd):/runner/project:Z \
		--set-env ANSIBLE_ROLES_PATH=/runner/project/ansible/roles \
		$(EXTRA_PLAYBOOK_OPTS)

.PHONY: validate-jupyter-validator
validate-jupyter-validator: ## Validate Jupyter Notebook Validator Operator installation
	@echo "\n\n***************************** Validating Jupyter Notebook Validator Operator \n"
	@echo "🔍 Checking operator components..."
	@echo "\n📁 Namespace:"
	@oc get namespace jupyter-notebook-validator-operator || echo "❌ Namespace not found"
	@echo "\n🚀 Deployment:"
	@oc get deployment -n jupyter-notebook-validator-operator notebook-validator-controller-manager || echo "❌ Deployment not found"
	@echo "\n🐳 Pods:"
	@oc get pods -n jupyter-notebook-validator-operator -l control-plane=controller-manager || echo "❌ Pods not found"
	@echo "\n📋 CRD:"
	@oc get crd notebookvalidationjobs.mlops.mlops.dev || echo "❌ CRD not registered"
	@echo "\n🔒 Cert-Manager (webhooks):"
	@if oc get namespace cert-manager >/dev/null 2>&1; then \
		echo "✅ cert-manager namespace exists"; \
		oc get certificate -n jupyter-notebook-validator-operator >/dev/null 2>&1 && echo "✅ Webhook certificate configured" || echo "⚠️  No webhook certificate found"; \
		oc get secret webhook-server-cert -n jupyter-notebook-validator-operator >/dev/null 2>&1 && echo "✅ Webhook certificate secret exists" || echo "⚠️  No webhook secret found"; \
	else \
		echo "⚠️  cert-manager not found (webhooks disabled)"; \
	fi
	@echo "\n🔌 Webhook Configurations:"
	@oc get validatingwebhookconfigurations 2>/dev/null | grep jupyter-notebook && echo "✅ ValidatingWebhookConfiguration found" || echo "⚠️  No ValidatingWebhookConfiguration"
	@oc get mutatingwebhookconfigurations 2>/dev/null | grep jupyter-notebook && echo "✅ MutatingWebhookConfiguration found" || echo "⚠️  No MutatingWebhookConfiguration"
	@echo "\n✅ Validation complete"

.PHONY: test-jupyter-validator
test-jupyter-validator: ## Test operator with sample notebook validation
	@echo "\n\n***************************** Testing Jupyter Notebook Validator \n"
	@echo "📝 Creating test NotebookValidationJob..."
	@cat <<EOF | oc apply -f -
	apiVersion: mlops.mlops.dev/v1alpha1
	kind: NotebookValidationJob
	metadata:
	  name: test-hello-world
	  namespace: self-healing-platform
	spec:
	  notebook:
	    git:
	      url: "https://github.com/tosin2013/jupyter-notebook-validator-test-notebooks"
	      ref: "main"
	    path: "notebooks/tier1-simple/01-hello-world.ipynb"
	  podConfig:
	    containerImage: "quay.io/jupyter/scipy-notebook:latest"
	    serviceAccountName: "default"
	    resources:
	      requests:
	        memory: "512Mi"
	        cpu: "500m"
	      limits:
	        memory: "1Gi"
	        cpu: "1000m"
	  timeout: "5m"
	EOF
	@echo "\n⏳ Waiting 10 seconds for job to start..."
	@sleep 10
	@echo "\n📊 Job Status:"
	@oc get notebookvalidationjob test-hello-world -n self-healing-platform
	@echo "\n✅ Test job created"
	@echo "📡 Monitor with: oc get notebookvalidationjob test-hello-world -n self-healing-platform -w"
	@echo "📜 View logs with: oc logs -l job-name=test-hello-world -n self-healing-platform"

##@ MCP Server and OpenShift Lightspeed

.PHONY: deploy-mcp-server
deploy-mcp-server: ## Deploy Cluster Health MCP Server (development overlay)
	@echo "\n\n***************************** Deploying MCP Server \n"
	@echo "📦 Deploying Cluster Health MCP Server to self-healing-platform namespace"
	@echo "📖 Architecture: ADR-014 (docs/adrs/014-openshift-aiops-platform-mcp-server.md)"
	@echo "📚 Guide: docs/how-to/deploy-mcp-server-lightspeed.md"
	@echo ""
	@echo "🔧 Using Kustomize overlay: k8s/mcp-server/overlays/development"
	oc apply -k k8s/mcp-server/overlays/development
	@echo ""
	@echo "⏳ Waiting for deployment to be ready (30 seconds)..."
	@sleep 5
	@oc rollout status deployment/cluster-health-mcp-server -n self-healing-platform --timeout=30s || true
	@echo ""
	@echo "✅ MCP Server deployed!"
	@echo ""
	@echo "📊 Verify deployment:"
	@echo "  oc get deployment cluster-health-mcp-server -n self-healing-platform"
	@echo "  oc get service cluster-health-mcp-server -n self-healing-platform"
	@echo "  oc logs deployment/cluster-health-mcp-server -n self-healing-platform"
	@echo ""
	@echo "🔗 Next step: Configure OpenShift Lightspeed"
	@echo "  make configure-lightspeed"

.PHONY: deploy-mcp-server-production
deploy-mcp-server-production: ## Deploy MCP Server (production base overlay)
	@echo "\n\n***************************** Deploying MCP Server (Production) \n"
	@echo "🚀 Deploying production configuration (base overlay)"
	oc apply -k k8s/mcp-server/base
	@echo ""
	@oc rollout status deployment/cluster-health-mcp-server -n self-healing-platform --timeout=60s || true
	@echo "✅ Production MCP Server deployed!"

.PHONY: configure-lightspeed
configure-lightspeed: ## Configure OpenShift Lightspeed with MCP Server
	@echo "\n\n***************************** Configuring OpenShift Lightspeed \n"
	@echo "📖 Official Red Hat Documentation:"
	@echo "   https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/1.0/"
	@echo ""
	@echo "📚 Deployment Guide: docs/how-to/deploy-mcp-server-lightspeed.md"
	@echo ""
	@echo "🔍 Checking for OpenShift Lightspeed operator..."
	@if ! oc get csv -n openshift-operators | grep lightspeed >/dev/null 2>&1; then \
		echo "❌ OpenShift Lightspeed operator not found. Please install it first."; \
		exit 1; \
	fi
	@echo "✅ OpenShift Lightspeed operator found."
	@echo ""
	@echo "🔑 Available LLM Provider Configurations:"
	@echo "  1. OpenAI GPT-4:     k8s/mcp-server/overlays/development/olsconfig-openai.yaml"
	@echo "  2. Google Gemini:    k8s/mcp-server/overlays/development/olsconfig-google.yaml (default)"
	@echo "  3. Anthropic Claude: k8s/mcp-server/overlays/development/olsconfig-anthropic.yaml"
	@echo "  4. Red Hat AI vLLM:  k8s/mcp-server/overlays/development/olsconfig-rhelai-vllm.yaml"
	@echo ""
	@echo "⚠️  PREREQUISITE: Create API Key Secret First"
	@echo "IMPORTANT: Secret key must be 'apitoken' (not 'apiKey')"
	@echo ""
	@echo "Example secret creation commands:"
	@echo ""
	@echo "OpenAI:"
	@echo '  oc create secret generic openai-api-key \'
	@echo '    -n openshift-lightspeed \'
	@echo "    --from-literal=apitoken='sk-proj-...'"
	@echo ""
	@echo "Google Gemini (Recommended - Gemini 3 experimental support):"
	@echo '  oc create secret generic google-api-key \'
	@echo '    -n openshift-lightspeed \'
	@echo "    --from-literal=apitoken='AIzaSy...'"
	@echo ""
	@echo "Anthropic Claude:"
	@echo '  oc create secret generic anthropic-api-key \'
	@echo '    -n openshift-lightspeed \'
	@echo "    --from-literal=apitoken='sk-ant-...'"
	@echo ""
	@echo "Red Hat AI vLLM:"
	@echo '  oc create secret generic rhelai-api-key \'
	@echo '    -n openshift-lightspeed \'
	@echo "    --from-literal=apitoken='YOUR_TOKEN'"
	@echo ""
	@read -p "Press Enter to continue with Google Gemini (Ctrl+C to cancel)..." dummy
	@echo ""
	@echo "🔧 Applying OLSConfig for Google Gemini..."
	oc apply -f k8s/mcp-server/overlays/development/olsconfig-google.yaml
	@echo ""
	@echo "✅ OpenShift Lightspeed configured with Google Gemini!"
	@echo ""
	@echo "💡 To use a different provider, apply its config file manually:"
	@echo "   oc apply -f k8s/mcp-server/overlays/development/olsconfig-openai.yaml"
	@echo "   oc apply -f k8s/mcp-server/overlays/development/olsconfig-anthropic.yaml"
	@echo "   oc apply -f k8s/mcp-server/overlays/development/olsconfig-rhelai-vllm.yaml"
	@echo ""
	@echo "📊 Verify configuration (OLSConfig name must be 'cluster'):"
	@echo "  oc get olsconfig cluster"
	@echo "  oc describe olsconfig cluster"
	@echo ""
	@echo "📈 Check reconciliation status:"
	@echo "  oc get olsconfig cluster -o jsonpath='{.status.conditions[*].type}'"
	@echo "  # Should show: ConsolePluginReady CacheReady ApiReady"
	@echo ""
	@echo "🧪 Test integration:"
	@echo "  make test-mcp-server"

.PHONY: test-mcp-server
test-mcp-server: ## Test MCP Server health and integration
	@echo "\n\n***************************** Testing MCP Server \n"
	@echo "🧪 Testing Cluster Health MCP Server"
	@echo ""
	@echo "1️⃣ Checking deployment status..."
	@oc get deployment cluster-health-mcp-server -n self-healing-platform || \
		(echo "❌ MCP Server not deployed. Run: make deploy-mcp-server" && exit 1)
	@echo ""
	@echo "2️⃣ Checking pod health..."
	@oc get pods -n self-healing-platform -l app=cluster-health-mcp-server
	@echo ""
	@echo "3️⃣ Testing health endpoint..."
	@oc run test-mcp-health --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
		--rm -i --restart=Never -n self-healing-platform -- \
		curl -s http://cluster-health-mcp-server:3000/health 2>/dev/null || \
		echo "⚠️  Health endpoint test skipped (requires curl in test pod)"
	@echo ""
	@echo "4️⃣ Checking MCP Server logs (last 20 lines)..."
	@oc logs deployment/cluster-health-mcp-server -n self-healing-platform --tail=20
	@echo ""
	@echo "5️⃣ Checking OLSConfig (if configured)..."
	@oc get olsconfig cluster 2>/dev/null && \
		echo "✅ OLSConfig found" || \
		echo "⚠️  OLSConfig not configured yet. Run: make configure-lightspeed"
	@echo ""
	@echo "✅ MCP Server test complete!"
	@echo ""
	@echo "📖 Full testing guide: docs/how-to/deploy-mcp-server-lightspeed.md"

.PHONY: uninstall-mcp-server
uninstall-mcp-server: ## Uninstall MCP Server and OLSConfig
	@echo "\n\n***************************** Uninstalling MCP Server \n"
	@echo "🗑️  Removing Cluster Health MCP Server"
	@echo ""
	@echo "1️⃣ Deleting OLSConfig..."
	@oc delete olsconfig cluster --ignore-not-found=true
	@echo ""
	@echo "2️⃣ Deleting MCP Server deployment..."
	@oc delete -k k8s/mcp-server/overlays/development --ignore-not-found=true
	@echo ""
	@echo "3️⃣ Verifying cleanup..."
	@oc get deployment cluster-health-mcp-server -n self-healing-platform 2>/dev/null && \
		echo "⚠️  Deployment still exists (may be terminating)" || \
		echo "✅ Deployment removed"
	@echo ""
	@echo "✅ MCP Server uninstalled!"
	@echo ""
	@echo "Note: OpenAI API key secret NOT removed (manual cleanup if needed):"
	@echo "  oc delete secret openai-api-key -n openshift-lightspeed"

.PHONY: show-mcp-docs
show-mcp-docs: ## Show MCP Server documentation links
	@echo "\n\n***************************** MCP Server Documentation \n"
	@echo "📚 Complete Documentation:"
	@echo ""
	@echo "🏗️  Architecture Decision Record:"
	@echo "  📄 ADR-014: Cluster Health MCP Server"
	@echo "  🔗 docs/adrs/014-openshift-aiops-platform-mcp-server.md"
	@echo ""
	@echo "📖 Deployment Guide:"
	@echo "  📄 How-To: Deploy MCP Server and Configure OpenShift Lightspeed"
	@echo "  🔗 docs/how-to/deploy-mcp-server-lightspeed.md"
	@echo ""
	@echo "🔧 Kustomize Manifests:"
	@echo "  📁 k8s/mcp-server/"
	@echo "  📄 k8s/mcp-server/README.md"
	@echo ""
	@echo "📓 Notebook Integration:"
	@echo "  📄 notebooks/06-mcp-lightspeed-integration/openshift-lightspeed-integration.ipynb"
	@echo ""
	@echo "🚀 Quick Start:"
	@echo "  1. Deploy MCP Server:     make deploy-mcp-server"
	@echo "  2. Configure Lightspeed:  make configure-lightspeed"
	@echo "  3. Test Integration:      make test-mcp-server"
	@echo ""
	@echo "💡 For detailed instructions, see: docs/how-to/deploy-mcp-server-lightspeed.md"

.PHONY: mcp-help
mcp-help: show-mcp-docs ## Alias for show-mcp-docs
