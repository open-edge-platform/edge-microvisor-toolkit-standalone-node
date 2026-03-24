#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

QEMU_PID=$1

if [ -z "$QEMU_PID" ]; then
  echo "Usage: $0 <QEMU_PID>"
  exit 1
fi

echo "Listing vCPU threads and their current CPU core for QEMU PID $QEMU_PID"
echo "TID    CPU Core    Thread Name"
ps -L -p "$QEMU_PID" -o tid,psr,comm | grep 'CPU'
