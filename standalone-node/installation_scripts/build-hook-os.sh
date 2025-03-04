#!/bin/sh
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

HOOK_OS_YAML_PATH="../hook_os/"
# Install linuxkit binary
install_linuxkit() {
    # Install linuxkit binary
    echo "Installing linuxkit binary..."
    # Add linuxkit binary installation steps here
    LINUXKIT_VERSION="v1.5.3"
    # Check if linuxkit binary is already installed
    if [ -x "$(command -v linuxkit)" ]; then
        echo "Linuxkit binary is already installed"
        return
    else
        curl -Lo linuxkit https://github.com/linuxkit/linuxkit/releases/download/${LINUXKIT_VERSION}/linuxkit-linux-amd64 && chmod +x linuxkit && sudo mv linuxkit /usr/local/bin/
        echo "Linuxkit binary installed successfully"
    fi
}

# Build hook-os image
build_hook_os_image() {
    # Build hook-os image
    echo "Building hook-os image..."
    pushd "$HOOK_OS_YAML_PATH" > /dev/null
    linuxkit build --format iso-bios "$HOOK_OS_YAML_PATH/hook-os.yaml"
    popd > /dev/null
    echo "Hook-os image built successfully"
}

# main function
main() {
    install_linuxkit
    build_hook_os_image
}

main
