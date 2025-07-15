#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


IMG_DIR=./user-apps
TAR_PRX=k3s-images
TAR_SFX=linux-amd64.tar
ARIGAP=true
BINARY_INSTALL=true
IDV_EXTENSIONS=true
INSTALL_TYPE="${1:-IDV}"

if [ "$INSTALL_TYPE" == "IDV" ]; then
	AIRGAP=true
	IDV_EXTENSIONS=true
else
	if [ "$INSTALL_TYPE" == "NON-RT" ]; then
		AIRGAP=true
		IDV_EXTENSIONS=false
	else
		echo "Invalid INSTALL_TYPE. Use 'IDV' or 'NON-RT'."
		exit 1
	fi
fi
# List of pre-downloaded docker images
images=(
	docker.io/calico/cni:v3.30.1
	docker.io/calico/kube-controllers:v3.30.1
	docker.io/calico/node:v3.30.1
	ghcr.io/k8snetworkplumbingwg/multus-cni:v4.2.1
	docker.io/intel/intel-gpu-plugin:0.32.1
)

# Download k3s artifacts
download_k3s_artifacts () {
	echo "Downloading k3s artifacts"
	curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/sha256sum-amd64.txt
	curl -sfL https://get.k3s.io --output install.sh
	curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/k3s
}

# Download airgap images
download_airgap_images () {
	echo "Downloading k3s airgap images"
	cd ${IMG_DIR} && curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/k3s-airgap-images-amd64.tar.zst && cd ..
}

# Download images
download_extension_images () {
	
	echo "Downloading container images"
	mkdir -p ${IMG_DIR}
	for image in "${images[@]}" ; do
		## check if image exists already in podman
		if docker image inspect ${image} > /dev/null 2>&1; then
			echo "Image ${image} already exists, skipping download"
		else
			docker pull ${image}
		fi
		img_name=$(echo ${image##*/} | tr ':' '-')
		DEST=${IMG_DIR}/${TAR_PRX}-${img_name}.${TAR_SFX}
		docker save -o ${DEST}.tmp ${image}
		# Create temp dirs for processing
        mkdir -p /tmp/image_repacking/{manifest,content}
        
        # Extract only manifest.json and repositories first
        tar -xf ${DEST}.tmp -C /tmp/image_repacking/manifest manifest.json repositories 2>/dev/null
        
        # Create initial tar with just the manifest files
        tar -cf ${DEST} -C /tmp/image_repacking/manifest .
        
        # Extract all remaining files (excluding manifest.json and repositories)
        tar -xf ${DEST}.tmp --exclude="manifest.json" --exclude="repositories" -C /tmp/image_repacking/content
        
        # Append all other files to tar
        tar -rf ${DEST} -C /tmp/image_repacking/content .
        
        # Clean up
        rm -rf /tmp/image_repacking
        rm -f ${DEST}.tmp
	done
}

# Install required packages for download the images
install_pkgs () {
    sudo apt update
    sudo apt install -y docker.io
}

# Main
if [ "${BINARY_INSTALL}" = true ]; then
	download_k3s_artifacts
fi
if [ "${ARIGAP}" = true ]; then
	download_airgap_images
fi
if [ "${IDV_EXTENSIONS}" = true ]; then
	download_extension_images
fi

