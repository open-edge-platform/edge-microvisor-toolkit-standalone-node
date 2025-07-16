#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


OUT_DIR=./user-apps
IMG_DIR=images
MANIFEST_DIR=manifests
ARTIFACT_DIR=artifacts
TAR_PRX=k3s-images
TAR_SFX=linux-amd64.tar
AIRGAP=true
BINARY_INSTALL=true
IDV_EXTENSIONS=true
IDV_KUBEVIRT=true
IDV_DEVICE_PLUGINS=true
INSTALL_TYPE="${1:-NON-RT}"

# Help function
show_help() {
    echo "Usage: $0 [DV|NON-RT]"
    echo "  DV     : Download images and manifests for Desktop Virtualization (kubernetes and addon images and manifest)."
    echo "  NON-RT  : Download images and manifests for Default EMT image without Desktop Virtualization and Realtime kernel (kubernetes and addon images and manifest). (default)"
    echo "If no argument is given, NON-RT is used by default."
    exit 0
}

# Parse help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

if [ "$INSTALL_TYPE" == "DV" ]; then
	AIRGAP=true
	IDV_EXTENSIONS=true
	IDV_KUBEVIRT=true
	IDV_DEVICE_PLUGINS=true
else
	if [ "$INSTALL_TYPE" == "NON-RT" ]; then
		AIRGAP=true
		IDV_EXTENSIONS=false
		IDV_KUBEVIRT=false
		IDV_DEVICE_PLUGINS=false
	else
		echo "Invalid INSTALL_TYPE. Use 'DV' or 'NON-RT'."
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

manifests=(
	https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.2.1/deployments/multus-daemonset.yml
	https://raw.githubusercontent.com/intel/intel-device-plugins-for-kubernetes/v0.32.1/deployments/gpu_plugin/base/intel-gpu-plugin.yaml
	https://raw.githubusercontent.com/projectcalico/calico/v3.30.1/manifests/calico.yaml
)

# Download k3s artifacts
download_k3s_artifacts () {
	echo "Downloading k3s artifacts"
	mkdir -p ${OUT_DIR}/${ARTIFACT_DIR}
	cd ${OUT_DIR}/${ARTIFACT_DIR}
	curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/sha256sum-amd64.txt
	curl -sfL https://get.k3s.io --output install.sh
	curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/k3s
	cd ../../
}

# Download airgap images
download_airgap_images () {
	echo "Downloading kubernetes container images"
	mkdir -p ${OUT_DIR}/${IMG_DIR}
	cd ${OUT_DIR}/${IMG_DIR} && curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/k3s-airgap-images-amd64.tar.zst && cd ../../
}

# Download extension manifests
download_extension_manifests () {
	echo "Downloading addons manifests"
	mkdir -p ${OUT_DIR}/${MANIFEST_DIR}
	cd ${OUT_DIR}/${MANIFEST_DIR}
	for manifest in "${manifests[@]}" ; do
		name=$(basename "${manifest}")
		curl -OLs "${manifest}" -o "${OUT_DIR}/${MANIFEST_DIR}/${name}"
		if [ $? -ne 0 ]; then
			echo "Failed to download ${name}"
			exit 1			
		fi
		if [[ "${name}" == "multus-daemonset.yml" ]]; then
			# Replace the image tag in the multus manifest
			sed -i 's|ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot|ghcr.io/k8snetworkplumbingwg/multus-cni:v4.2.1|g' "${name}"		
		fi
	done
	cd ../../
}
# Download images
download_extension_images () {
	
	echo "Downloading container images"
	mkdir -p ${OUT_DIR}/${IMG_DIR}
	for image in "${images[@]}" ; do
		## check if image exists already in podman
		if docker image inspect ${image} > /dev/null 2>&1; then
			echo "Image ${image} already exists, skipping download"
		else
			docker pull ${image}
		fi
		img_name=$(echo ${image##*/} | tr ':' '-')
		DEST=${OUT_DIR}/${IMG_DIR}/${TAR_PRX}-${img_name}.${TAR_SFX}
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

# Download Intel IDV kubevirt images and manifests
download_idv_kubevirt_images_and_manifests () {
	echo "Downloading idv kubevirt artifacts"
	# download the artifacts
	mkdir -p ${OUT_DIR}/${ARTIFACT_DIR}
	cd ${OUT_DIR}/${ARTIFACT_DIR}
	curl -OLs https://github.com/open-edge-platform/edge-desktop-virtualization/releases/download/1.0.0-rc2/intel-idv-kubevirt-1.0.0-rc2.tar.gz
	# untar
	tar -xzf intel-idv-kubevirt-1.0.0-rc2.tar.gz -C .
	# copy all the images (.zst) to required destination
	mkdir -p ../../${OUT_DIR}/${IMG_DIR}
	cp intel-idv-kubevirt-1.0.0-rc2/*.zst ../../${OUT_DIR}/${IMG_DIR}
	# copy all manifests to required destination
	mkdir -p ../../${OUT_DIR}/${MANIFEST_DIR}
	cp intel-idv-kubevirt-1.0.0-rc2/*.yaml ../../${OUT_DIR}/${MANIFEST_DIR}
	rm -rf intel-idv-kubevirt-1.0.0-rc2.tar.gz
	rm -rf intel-idv-kubevirt-1.0.0-rc2
	cd ../../
}

# Download Intel IDV device plugin images and manifests
download_idv_device_plugins_images_and_manifests () {
	echo "Downloading idv device plugin artifacts"
	# download the artifacts
	mkdir -p ${OUT_DIR}/${ARTIFACT_DIR}
	cd ${OUT_DIR}/${ARTIFACT_DIR}
	curl -OLs https://github.com/open-edge-platform/edge-desktop-virtualization/releases/download/1.0.0-rc2/intel-idv-device-plugin-1.0.0-rc2.tar.gz
	# untar
	tar -xzf intel-idv-device-plugin-1.0.0-rc2.tar.gz -C .
	# copy all the images (.zst) to required destination
	mkdir -p ../../${OUT_DIR}/${IMG_DIR}
	cp intel-idv-device-plugin-1.0.0-rc2/*.zst ../../${OUT_DIR}/${IMG_DIR}
	# copy all manifests to required destination
	mkdir -p ../../${OUT_DIR}/${MANIFEST_DIR}
	cp intel-idv-device-plugin-1.0.0-rc2/*.yaml ../../${OUT_DIR}/${MANIFEST_DIR}
	rm -rf intel-idv-device-plugin-1.0.0-rc2.tar.gz
	rm -rf intel-idv-device-plugin-1.0.0-rc2
	cd ../../
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
	download_extension_manifests
fi
if [ "${IDV_KUBEVIRT}" = true ]; then
	download_idv_kubevirt_images_and_manifests
fi
if [ "${IDV_DEVICE_PLUGINS}" = true ]; then
	download_idv_device_plugins_images_and_manifests
fi

