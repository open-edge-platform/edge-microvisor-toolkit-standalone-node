#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


IMG_DIR=./images
CHRT_DIR=./charts
EXT_DIR=./extensions
TPL_DIR=./extensions-templates
TAR_PRX=k3s-images
TAR_SFX=linux-amd64.tar
DOWNLOAD_ARTIFACTS=true

# List of pre-downloaded docker images
images=(
	docker.io/calico/apiserver:v3.30.0
	docker.io/calico/cni:v3.30.0
	docker.io/calico/csi:v3.30.0
	docker.io/calico/kube-controllers:v3.30.0
	docker.io/calico/node-driver-registrar:v3.30.0
	docker.io/calico/node:v3.30.0
	docker.io/calico/pod2daemon-flexvol:v3.30.0
	docker.io/calico/typha:v3.30.0
	docker.io/kubernetesui/dashboard-api:1.10.1
	docker.io/kubernetesui/dashboard-auth:1.2.2
	docker.io/kubernetesui/dashboard-metrics-scraper:1.2.1
	docker.io/kubernetesui/dashboard-web:1.6.0
	kong:3.6
	quay.io/tigera/operator:v1.38.0
	registry.k8s.io/e2e-test-images/agnhost:2.39
)

charts=(
	kubernetes-dashboard:kubernetes:https://kubernetes.github.io/dashboard/:7.10.0
)
# Download k3s artifacts
download_k3s_artifacts () {
	echo "Downloading k3s artifacts"
	curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/k3s-airgap-images-amd64.tar.zst
	curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/sha256sum-amd64.txt
	curl -sfL https://get.k3s.io --output install.sh
	curl -OLs https://github.com/k3s-io/k3s/releases/download/v1.32.4%2Bk3s1/k3s
}

# Download charts and convert to base64 - the charts do not end up in installation package but the encoded base64 will be part of helmchart addon definition elswhere in extensions directory.
download_extension_charts () {
	echo "Downloading extension charts"
	helm repo update
	unset no_proxy && unset NO_PROXY
	mkdir -p ${CHRT_DIR}
	mkdir -p ${EXT_DIR}
	for chart in "${charts[@]}" ; do
		# Separate fields
		name=$(echo "${chart}" | awk -F':' '{print $1}')
		repo=$(echo "${chart}" | awk -F':' '{print $2}')
		url=$(echo "${chart}" | awk -F':' '{print $3":"$4}')
		version=$(echo "${chart}" | awk -F':' '{print $5}')
	
		if [ "${repo}" == "intel-rs" ]; then
			echo Fetching "${name}" chart
			helm fetch -d ${CHRT_DIR} "${url}"/"${name}" --version "${version}"
			base64 -w 0 ${CHRT_DIR}/"${name}"-"$version".tgz > ${CHRT_DIR}/"$name".base64
	
		else
			echo Fetching "${name}" chart
			helm repo add "${repo}" "${url}"
			helm fetch -d ${CHRT_DIR} "${repo}"/"${name}" --version "${version}"
			if [ "${name}" == "cert-manager" ]; then version="v${version}"; fi
			if [ "${name}" == "node-feature-discovery" ]; then version="chart-${version}"; fi
			base64 -w 0 ${CHRT_DIR}/"${name}"-"${version}".tgz > ${CHRT_DIR}/"${name}".base64
		fi
		# Template HelmChart addon manifets using the base64 chart
		awk "/chartContent:/ {printf \"  chartContent: \"; while ((getline line < \"${CHRT_DIR}/${name}.base64\") > 0) printf \"%s\", line; close(\"${CHRT_DIR}/${name}.base64\"); print \"\"; next} 1" "${TPL_DIR}/${name}.yaml" > "${EXT_DIR}/${name}.yaml"

	done		
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

#This function exists to ensure that if somebody accidentaly deletes additional manifests from extensions directory the manifests will be backed up from extensions-template dir
copy_other_manifests_from_template_dir () {
	mkdir -p ${EXT_DIR}
	find ${TPL_DIR} -type f ! -exec grep -q "kind: HelmChart" {} \; -exec cp {} ${EXT_DIR} \;
}
# Install required packages for download the images
install_pkgs () {
    sudo apt update
    sudo apt install -y podman libarchive-tools
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    sudo apt install apt-transport-https --yes
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt update
    sudo apt install helm
}

# Main
install_pkgs
if [ "${DOWNLOAD_ARTIFACTS}" = true ]; then
	download_k3s_artifacts
fi
download_extension_charts
download_extension_images
copy_other_manifests_from_template_dir
