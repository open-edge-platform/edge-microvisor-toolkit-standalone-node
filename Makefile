# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

.DEFAULT_GOAL := help
.PHONY: build lint license help

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

lint: license yamllint mdlint shellcheck

build:
	@# Help: Runs build stage
	@echo "---MAKEFILE ISO BUILD---"
	echo $@
	cd installation_scripts && ./build-emt-s-install-pkg.sh && cd ..
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

help:	
	@printf "%-20s %s\n" "Target" "Description"
	@printf "%-20s %s\n" "------" "-----------"
	@make -pqR : 2>/dev/null \
        | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' \
        | sort \
        | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' \
        | xargs -I _ sh -c 'printf "%-20s " _; make _ -nB | (grep -i "^# Help:" || echo "") | tail -1 | sed "s/^# Help: //g"'

artifact-publish:
	@# Help: Upload files to the fileserver
	@echo "---MAKEFILE FILESERVER UPLOAD---"
	@for dir in $(SUBPROJECTS); do $(MAKE) -C $$dir artifact-publish; done
	@echo "---END MAKEFILE FILESERVER UPLOAD---"