# Standalone Edgenode Makefile

# SPDX-FileCopyrightText: (C) 2023 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

.DEFAULT_GOAL := help
.PHONY: build test lint license help generate fuzz

##### Variables #####

# Defining the shell, users and groups
SHELL       := bash -e -o pipefail
CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

# Project variables
PROJECT_NAME := std-edgenode
BINARY_NAME  := std-edgenode

# Code versions, tags, and so on
VERSION       ?= $(shell cat VERSION)
VERSION_MAJOR ?= $(shell cut -c 1 VERSION)
IMG_NAME      ?= ${PROJECT_NAME}
IMG_VERSION   ?= $(VERSION)
GIT_COMMIT    ?= $(shell git rev-parse HEAD)
DOCKER_ENV              := DOCKER_BUILDKIT=1
DOCKER_REGISTRY         ?= amr-registry.caas.intel.com
DOCKER_REPOSITORY       ?= one-intel-edge/maestro-i
DOCKER_TAG              := ${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/${IMG_NAME}

# Create the virtualenv with python tools installed
VENV_NAME = venv_stden

$(VENV_NAME): requirements.txt
	echo "Creating virtualenv $@"
	python3 -m venv $@;\
	. ./$@/bin/activate; set -u;\
	python3 -m pip install --upgrade pip;\
	python3 -m pip install -r requirements.txt

all: 
	@# Help: Runs build, lint, test stages
	build lint test 	

build:
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

license: $(VENV_NAME) ## Check licensing with the reuse tool.
	. ./$</bin/activate; set -u;\
	reuse --version;\
        reuse download --all
	reuse --root . lint

YAML_FILES := $(shell find . -path './.github' -prune -o -type f -name "*.yaml" -print )

lint: $(VENV_NAME)
	@. $(VENV_NAME)/bin/activate; flake8 --exclude=venv_stden
	yamllint --version;\
	yamllint $(YAML_FILES)
	@echo "---END MAKEFILE LINT---"

#lint:
#	@# Help: Runs lint stage
#	@echo "---MAKEFILE LINT---"
#	echo $@
#	@echo "---END MAKEFILE LINT---"

test:
	@# Help: Runs test stage
	@echo "---MAKEFILE TEST---"
	echo $@
	@echo "---END MAKEFILE TEST---"
	
coverage:
	@# Help: Runs coverage stage
	@echo "---MAKEFILE COVERAGE---"
	echo $@
	@echo "---END MAKEFILE COVERAGE---"

clean:
	@# Clean: Remove build files
	@echo "---MAKEFILE CLEAN---"
	cd host_os && rm -f *.gz *.sha256sum *.der && cd ..
	cd hook_os && make clean && cd ..
	cd installation_scripts && rm -rf out && cd ..
	rm -rf ./out
	rm -rf .hypothesis
	@echo "---END MAKEFILE CLEAN---"

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

fuzz: $(VENV_NAME)
	@# Help: Runs fuzz testing for 60 seconds
	@echo "---MAKEFILE FUZZ TEST---"
	mkdir -p ./out
	@. $(VENV_NAME)/bin/activate; $(VENV_NAME)/bin/python ./esc/fuzz_Edge_microvisor.py 60 > ./out/fuzz_repor_4hr.logs 2>&1
	@echo "---END MAKEFILE FUZZ TEST---"
