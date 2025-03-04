# SPDX-FileCopyrightText: (C) 2024 Intel Corporation
# SPDX-License-Identifier: LicenseRef-Intel

#!/bin/bash

if [ "$1" == "--no-ext-image" ]; then
    tar --exclude './charts' --exclude './download_charts_and_images.sh' --exclude './cleanup-artifacts.sh' --exclude 'build_package.sh' --exclude './images' -cvf sen-rke2-package.tar.gz ./*
else
    tar --exclude './charts' --exclude './download_charts_and_images.sh' --exclude './cleanup-artifacts.sh' --exclude 'build_package.sh'  -cvf sen-rke2-package.tar.gz ./*
fi
