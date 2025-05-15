#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


IMG_DIR=./images
CHRT_DIR=./charts
EXT_DIR=./extensions
TPL_DIR=./extensions-templates
TAR_PRX=rke2-images
TAR_SFX=linux-amd64.tar

# List of pre-downloaded docker images
images=(
	quay.io/jetstack/cert-manager-controller:v1.16.2
	quay.io/jetstack/cert-manager-cainjector:v1.16.2
	quay.io/jetstack/cert-manager-webhook:v1.16.2
	quay.io/jetstack/cert-manager-startupapicheck:v1.16.2
	docker.io/openpolicyagent/gatekeeper:v3.17.1
	docker.io/openpolicyagent/gatekeeper-crds:v3.17.1
	docker.io/curlimages/curl:8.11.0
	docker.io/openebs/provisioner-localpv:4.2.0
	registry.k8s.io/sig-storage/csi-resizer:v1.8.0
	registry.k8s.io/sig-storage/csi-snapshotter:v6.2.2
	registry.k8s.io/sig-storage/snapshot-controller:v6.2.2
	registry.k8s.io/sig-storage/csi-provisioner:v3.5.0
	docker.io/openebs/lvm-driver:1.6.1
	registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.8.0
	docker.io/bitnami/kubectl:1.25.15
	registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0
	quay.io/brancz/kube-rbac-proxy:v0.19.0
	quay.io/prometheus-operator/prometheus-operator:v0.81.0
	quay.io/prometheus/prometheus:v3.2.1
	docker.io/library/busybox:1.35.0
	docker.io/library/busybox:latest
	quay.io/prometheus-operator/prometheus-config-reloader:v0.81.0
	quay.io/prometheus/node-exporter:v1.9.0
	docker.io/library/telegraf:1.32-alpine
	registry.k8s.io/nfd/node-feature-discovery:v0.17.0
	docker.io/kubernetesui/dashboard:v2.7.0
	docker.io/kubernetesui/metrics-scraper:v1.0.8
	docker.io/grafana/grafana:11.6.0
	docker.io/bats/bats:v1.4.1
)

charts=(
	"cert-manager:jetstack:https://charts.jetstack.io:1.16.2"
	"gatekeeper:gatekeeper:https://open-policy-agent.github.io/gatekeeper/charts:3.17.1"
	"gatekeeper-constraints:intel-rs:oci://registry-rs.edgeorchestration.intel.com/edge-orch/en/charts:1.0.15"
	"openebs:openebs:https://openebs.github.io/openebs:4.2.0"
	"openebs-config:intel-rs:oci://registry-rs.edgeorchestration.intel.com/edge-orch/en/charts:0.0.2"
	"kube-prometheus-stack:prometheus:https://prometheus-community.github.io/helm-charts:70.3.0"
	"observability-config:intel-rs:oci://registry-rs.edgeorchestration.intel.com/edge-orch/en/charts:0.0.2"
	"network-policies:intel-rs:oci://registry-rs.edgeorchestration.intel.com/edge-orch/en/charts:0.1.13"
	"prometheus-node-exporter:node-exporter:https://prometheus-community.github.io/helm-charts:4.45.0"
	"telegraf:telegraf:https://helm.influxdata.com/:1.8.55"
	"node-feature-discovery:node-feature-discovery:https://kubernetes-sigs.github.io/node-feature-discovery/charts:0.17.0"
	"grafana:grafana:https://grafana.github.io/helm-charts:8.11.1"
)

# Download RKE2 artifacts
download_rke2_artifacts () {
	
	echo "Downloading RKE2 artifacts"
	curl -OLs https://github.com/rancher/rke2/releases/download/v1.30.6%2Brke2r1/rke2-images.linux-amd64.tar.zst
	curl -OLs https://github.com/rancher/rke2/releases/download/v1.30.6%2Brke2r1/rke2.linux-amd64.tar.gz
	curl -OLs https://github.com/rancher/rke2/releases/download/v1.30.6%2Brke2r1/rke2-images-calico.linux-amd64.tar.zst
	curl -OLs https://github.com/rancher/rke2/releases/download/v1.30.6%2Brke2r1/rke2-images-multus.linux-amd64.tar.zst
	curl -OLs https://github.com/rancher/rke2/releases/download/v1.30.6%2Brke2r1/sha256sum-amd64.txt
	curl -sfL https://get.rke2.io --output install.sh
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
		# Remove unnecessary files from kube-prometheus-stack, reason:  then base encoded file becomes to big and cannot be consumed when installing via add-on on RKE2
		if [ "${name}" == "kube-prometheus-stack" ]; then
			tar -xzf ${CHRT_DIR}/"${name}"-"${version}".tgz -C ${CHRT_DIR}
			rm -rf ${CHRT_DIR}/"${name}"-"${version}".tgz
			rm ${CHRT_DIR}/"${name}"/README.md
			rm ${CHRT_DIR}/"${name}"/templates/grafana/dashboards-1.14/*windows*
			rm -rf ${CHRT_DIR}/"${name}"/templates/thanos-ruler
			tar -cf ${CHRT_DIR}/"${name}"-"${version}".tgz --use-compress-program="gzip -9" -C ${CHRT_DIR} "${name}"
			base64 -w 0 ${CHRT_DIR}/"${name}"-"${version}".tgz > ${CHRT_DIR}/"${name}".base64
		fi
		# Template HelmChart addon manifets using the base64 chart
		awk "/chartContent:/ {printf \"  chartContent: \"; while ((getline line < \"${CHRT_DIR}/${name}.base64\") > 0) printf \"%s\", line; close(\"${CHRT_DIR}/${name}.base64\"); print \"\"; next} 1" "${TPL_DIR}/${name}.yaml" > "${EXT_DIR}/${name}.yaml"

	done		
}

# Download images
# Note: Docker images are repacked, inspired by https://github.com/rancher/rke2/blob/master/scripts/package-images
# Note2: Simple "podman pull <image> > <image>.tar.gz" images did not work correctly at RKE2 level - the images did not get imported due to missing gzip header (tar.gz) or "magic number" (tar.zst) - did not try with artifacts pulled by docker.

download_extension_images () {
	
	echo "Downloading container images"
	mkdir -p ${IMG_DIR}
	for image in "${images[@]}" ; do
		podman pull "${image}"
		img_name=$(echo "${image##*/}" | tr ':' '-')
		DEST=${IMG_DIR}/${TAR_PRX}-${img_name}.${TAR_SFX}
		podman image save --output "${DEST}".tmp "${image}"
		bsdtar -c -f "${DEST}" --include=manifest.json --include=repositories @"${DEST}".tmp
		bsdtar -r -f "${DEST}" --exclude=manifest.json --exclude=repositories @"${DEST}".tmp
		rm -f "${DEST}".tmp
		zstd -T0 -16 -f --long=25 --no-progress "${DEST}" -o ${IMG_DIR}/${TAR_PRX}-"${img_name}".${TAR_SFX}.zst
		rm -f "${DEST}"
	done
}
# Download K8s dashboard
#download_other_manifests () {
#	
#	echo "Downloading K8s dashboard manifest"
#	mkdir -p ${EXT_DIR}
#	curl -Ls https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml -o ./extensions/dashboard.yaml
#}

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
download_rke2_artifacts
download_extension_charts
download_extension_images
#download_other_manifests
copy_other_manifests_from_template_dir
