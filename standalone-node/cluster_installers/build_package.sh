#!/bin/bash
# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


if [ "$1" == "--no-ext-image" ]; then
    tar --exclude './extensions-templates' --exclude './docs' --exclude './charts' --exclude './download_charts_and_images.sh' --exclude './cleanup-artifacts.sh' --exclude 'build_package.sh' --exclude './images' -cvf sen-k3s-package.tar.gz ./*
else
    tar --exclude './extensions-templates' --exclude './docs' --exclude './charts' --exclude './download_charts_and_images.sh' --exclude './cleanup-artifacts.sh' --exclude 'build_package.sh' -cvf sen-k3s-package.tar.gz ./*
fi
