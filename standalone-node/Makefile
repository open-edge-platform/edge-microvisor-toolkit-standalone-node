# Standalone Node Makefile

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

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
include ../common.mk

all: 
	@# Help: Runs build, lint, test stages
	build lint test 	

configure:

#lint: license yamllint mdlint shellcheck #uncomment this line and remove next line after shellcheck is fixed
lint: license shellcheck yamllint mdlint

build: configure
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

artifact-publish:
	@# Help: Runs file upload stage
	@echo "---Uploading all build tar files---"
	dest_path="s3://ensp-prod-rs-files/files-edge-orch/repository/standalone-node/non-rt/base"; \
	tar_file="installation_scripts/out/standalone-installation-files.tar.gz"; \
	if [ -f "$$tar_file" ]; then \
		echo "Uploading $$tar_file ..."; \
		aws s3 cp "$$tar_file" "$$dest_path"/standalone-installation-files-$(VERSION).tar.gz || { echo "Upload failed for $$tar_file"; exit 1; }; \
	else \
		echo "Tar file $$tar_file not found!"; \
		exit 1; \
	fi
	@echo "---All uploads done---"
