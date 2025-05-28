# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# SUBPROJECTS := standalone-node

# .DEFAULT_GOAL := help
# .PHONY: all clean clean-all help lint build license

# all: lint mdlint build
# 	@# Help: Runs build, lint, test stages for all subprojects


# #### Python venv Target ####
# VENV_DIR := venv_standalonenode

# $(VENV_DIR): requirements.txt ## Create Python venv
# 	python3 -m venv $@ ;\
#   set +u; . ./$@/bin/activate; set -u ;\
#   python -m pip install --upgrade pip ;\
#   python -m pip install -r requirements.txt

# dependency-check: $(VENV_DIR)

# license:
# 	@echo "---LICENSE CHECK---"
# 	@for dir in $(SUBPROJECTS); do $(MAKE) -C $$dir license; done
# 	@echo "---END LICENSE CHECK---"

# lint:
# 	@# Help: Runs lint stage in all subprojects
# 	@echo "---MAKEFILE LINT---"
# 	@for dir in $(SUBPROJECTS); do $(MAKE) -C $$dir lint; done
# 	@echo "---END MAKEFILE LINT---"

# build:
# 	@# Help: Runs build stage in all subprojects
# 	@echo "---MAKEFILE BUILD---"
# 	for dir in $(SUBPROJECTS); do $(MAKE) -C $$dir build; done
# 	@echo "---END MAKEFILE Build---"

# mdlint:
# 	@echo "---MAKEFILE LINT README---"
# 	@for dir in $(SUBPROJECTS); do $(MAKE) -C $$dir mdlint; done
# 	@echo "---END MAKEFILE LINT README---"

# clean:
# 	@# Help: Runs clean stage in all subprojects
# 	@echo "---MAKEFILE CLEAN---"
# 	@# Clean: Remove build files
# 	for dir in $(SUBPROJECTS); do $(MAKE) -C $$dir clean; done
# 	@echo "---END MAKEFILE CLEAN---"

# clean-all:
# 	@# Help: Runs clean-all stage in all subprojects
# 	@echo "---MAKEFILE CLEAN-ALL---"
# 	for dir in $(SUBPROJECTS); do $(MAKE) -C $$dir clean-all; done
# 	@echo "---END MAKEFILE CLEAN-ALL---"

# help:	
# 	@printf "%-20s %s\n" "Target" "Description"
# 	@printf "%-20s %s\n" "------" "-----------"
# 	@make -pqR : 2>/dev/null \
#         | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' \
#         | sort \
#         | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' \
#         | xargs -I _ sh -c 'printf "%-20s " _; make _ -nB | (grep -i "^# Help:" || echo "") | tail -1 | sed "s/^# Help: //g"'

.DEFAULT_GOAL := help
.PHONY: build lint license help fuzz

# Optionally include tool version checks, not used in Docker builds
TOOL_VERSION_CHECK ?= 0

##### Variables #####

# Defining the shell, users and groups
SHELL       := bash -e -o pipefail
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

# Project variables
PROJECT_NAME := standalonenode
BINARY_NAME  := $(PROJECT_NAME)

# Code versions, tags, and so on
VERSION       ?= $(shell cat VERSION)
VERSION_MAJOR ?= $(shell cut -c 1 VERSION)
IMG_NAME      ?= ${PROJECT_NAME}
IMG_VERSION   ?= $(VERSION)
GIT_COMMIT    ?= $(shell git rev-parse HEAD)

# Yamllint variables
YAML_FILES           := $(shell find . -path './venv_$(PROJECT_NAME)' -path './vendor' -prune -o -type f \( -name '*.yaml' -o -name '*.yml' \) -print )
YAML_IGNORE          := vendor, .github/workflows

# Include shared makefile
include common.mk

all: 
	@# Help: Runs build, lint, test stages
	build lint test 	

configure:
	echo 'http_proxy=$(http_proxy)' > hook_os/config
	echo 'https_proxy=$(http_proxy)' >> hook_os/config
	echo 'ftp_proxy=$(ftp_proxy)' >> hook_os/config
	echo 'socks_proxy=$(socks_proxy)' >> hook_os/config
	echo 'no_proxy=$(no_proxy)' >> hook_os/config

lint: license yamllint mdlint shellcheck

build: configure
	@# Help: Runs build stage
	@echo "---MAKEFILE ISO BUILD---"
	echo $@
	cd installation_scripts && ./build-hook-os-iso.sh && cd ..
	@echo "---END MAKEFILE Build---"
	
image:
	@# Help: Runs build stage
	@echo "---MAKEFILE BUILD---"
	echo $@
	cd host_os && ./download_tmv.sh && cd ..
	@echo "---END MAKEFILE Build---"

dependency-check:
	@# Help: Runs dependency-check stage
	@echo "---MAKEFILE TEST---"
	echo $@
	@echo "---END MAKEFILE TEST---"

docker-build: 
	@# Help: Runs docker-build stage
	@echo "---MAKEFILE BUILD---"
	echo $@
	@echo "---END MAKEFILE Build---"

test:
	@# Help: Runs test stage
	@echo "---MAKEFILE TEST---"
	echo $@
	@echo "---END MAKEFILE TEST---"

list: 
	@# Help: displays make targets
	help
