#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

case "$1" in
  non-rt-k8s) echo "non_rt/edge-readonly-3.0.20250413.2200-prod-signed" ;;
  non-rt-docker) echo "non_rt/edge-readonly-3.0.20250601.2200" ;;
  rt-docker) echo "rt/edge-readonly-rt-3.0.20250601.2058" ;;
  *) echo "Unknown profile: $1" >&2; exit 1 ;;
esac