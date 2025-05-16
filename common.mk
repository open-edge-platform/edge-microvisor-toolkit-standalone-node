# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Makefile Style Guide:
# - Help will be generated from ## comments at end of any target line
# - Use smooth parens $() for variables over curly brackets ${} for consistency
# - Continuation lines (after an \ on previous line) should start with spaces
#   not tabs - this will cause editor highligting to point out editing mistakes
# - When creating targets that run a lint or similar testing tool, print the
#   tool version first so that issues with versions in CI or other remote
#   environments can be caught

# Optionally include tool version checks, not used in Docker builds
ifeq ($(TOOL_VERSION_CHECK), 1)
	include ../version.mk
endif

#### Go Targets ####

#### Variables ####
SHELL	:= bash -eu -o pipefail
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

# Path variables
OUT_DIR	   := out
SECRETS_DIR := /var/run/secrets
SCRIPTS_DIR := ./ci_scripts

$(OUT_DIR): ## Create out directory
	mkdir -p $(OUT_DIR)

#### Python venv Target ####
VENV_NAME	:= venv_$(PROJECT_NAME)

$(VENV_NAME): requirements.txt
	python3 -m venv $@ ;\
  set +u; . ./$@/bin/activate; set -u ;\
  python -m pip install --upgrade pip ;\
  python -m pip install -r requirements.txt

#### Lint and Validator Targets ####
# https://github.com/koalaman/shellcheck
SH_FILES := $(shell find . -type f \( -name '*.sh' \) ! -path './cluster_installers/install.sh' -print)
shellcheck: ## lint shell scripts with shellcheck
	shellcheck --version
	shellcheck -x -S style $(SH_FILES) >> shellcheck_report.txt

# https://pypi.org/project/reuse/
license: $(VENV_NAME) ## Check licensing with the reuse tool
	set +u; . ./$</bin/activate; set -u ;\
  reuse --version ;\
  reuse --root . lint 

yamllint: $(VENV_NAME) ## lint YAML files
	. ./$</bin/activate; set -u ;\
	yamllint --version ;\
	yamllint .

mdlint: ## link MD files
	markdownlint --version ;\
	markdownlint "**/*.md" -c ../.markdownlint.yml --ignore venv_standalonenode/

common-clean:
	rm -rf ${OUT_DIR} vendor

clean:
	@# Clean: Remove build files
	@echo "---MAKEFILE CLEAN---"
	cd standalone-node/host_os && rm -f *.gz *.sha256sum *.der cd standalone-node/host_os && rm -f *.gz *.sha256sum *.der edge_microvisor_toolkit.raw.gz.sha256sum
	cd standalone-node/hook_os && make clean
	cd standalone-node/cluster_installers && rm -rf charts images install.sh *.tar.zst *.txt *.tar.gz
	cd standalone-node/cluster_installers/extensions && rm -rf *.yaml
	cd standalone-node/installation_scripts && rm -rf out extensions/*.yaml
	@echo "---END MAKEFILE CLEAN---"

clean-venv:
	rm -rf "$(VENV_NAME)"

clean-all: clean clean-venv ## delete all built artifacts and downloaded tools

#### Help Target ####
help: ## Print help for each target
	@echo $(PROJECT_NAME) make targets
	@echo "Target               Makefile:Line    Description"
	@echo "-------------------- ---------------- -----------------------------------------"
	@grep -H -n '^[[:alnum:]_-]*:.* ##' $(MAKEFILE_LIST) \
    | sort -t ":" -k 3 \
    | awk 'BEGIN  {FS=":"}; {sub(".* ## ", "", $$4)}; {printf "%-20s %-16s %s\n", $$3, $$1 ":" $$2, $$4};'
