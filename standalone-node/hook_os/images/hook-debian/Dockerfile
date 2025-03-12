# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Docker file to prepare the debain image with required pkgs 

FROM debian:latest

RUN apt update && apt install -y \  
                      grub-common \
                      grub-pc-bin \
                      grub-efi-amd64-bin \
                      e2fsprogs \
                      parted \
                      gdisk \
                      procps \
    		      bc \
		      lvm2 \
                      systemd-sysv \
		      busybox \
    		      && rm -rf /var/lib/apt/lists/*
