#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Source the environment variables
# shellcheck disable=SC1091 source=/etc/environment
source /etc/environment

# set -x

# Function to extract paths under the write_files section
extract_write_files_paths() {
  local config_file="$1"
  local in_section=false
  local paths=()

  while IFS= read -r line; do
    [[ "$line" =~ ^write_files: ]] && {
      in_section=true
      continue
    }

    if $in_section; then
      [[ "$line" =~ path:\ (\/[^ ]+) ]] && paths+=("${BASH_REMATCH[1]}")
      [[ "$line" =~ ^[^[:space:]] ]] && in_section=false
    fi
  done <"$config_file"

  echo "${paths[@]}"
}

# Function to convert date string to seconds since epoch
convert_to_epoch() {
  local date_string="$1"
  date -d "${date_string:0:8} ${date_string:8:2}:${date_string:10:2}:${date_string:12:2}" +%s
}

# Detection state holders for image type and source
DETECTED_IMAGE_TYPE="UNKNOWN"
IMAGE_TYPE_SOURCE="unknown"

# infer image type from a name/path/content string
detect_emt_type_from_string() {
  local input_string
  input_string=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  case "$input_string" in
    *edge-readonly-dv-* | */dv/* | *-dv-* | *_dv_*) echo "DV" ;;
    *edge-readonly-rt-* | */rt/* | *-rt-*) echo "RT" ;;
    *edge-readonly-* | */non-rt/* | */non_rt/* | *non-rt* | *non_rt*) echo "NON_RT" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# detect current emt type (RT, NON_RT, or DV)
detect_current_emt_type() {
  local detected_type
  local uname_output

  # Primary source: image metadata from provisioned image
  if [ -r "/etc/image-id" ]; then
    detected_type=$(detect_emt_type_from_string "$(cat /etc/image-id 2>/dev/null)")
    if [ "$detected_type" != "UNKNOWN" ]; then
      echo "$detected_type"
      return
    fi
  fi

  # Secondary source: desktop virtualization user-space components
  if [ -d "/usr/bin/idv" ] || [ -x "/usr/bin/idv/launcher/start_vm.sh" ]; then
    echo "DV"
    return
  fi

  # Fallback: kernel flavor
  uname_output=$(uname -a)
  case "$uname_output" in
    *PREEMPT_RT*) echo "RT" ;;
    *PREEMPT_DYNAMIC*) echo "NON_RT" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# detect image type by inspecting update image partition content
detect_image_type_from_partition() {
  local image_partition="$1"
  local mount_dir="/tmp/emt-image-inspect"
  local detected_type="UNKNOWN"
  local detection_source="unknown"
  local kernel_release=""
  local kernel_config=""

  mkdir -p "$mount_dir" 2>/dev/null || {
    DETECTED_IMAGE_TYPE="UNKNOWN"
    IMAGE_TYPE_SOURCE="partition mount failed"
    return
  }

  if mount -o ro "$image_partition" "$mount_dir" 2>/dev/null; then
    if [ -r "$mount_dir/etc/image-id" ]; then
      detected_type=$(detect_emt_type_from_string "$(cat "$mount_dir/etc/image-id" 2>/dev/null)")
      if [ "$detected_type" != "UNKNOWN" ]; then
        detection_source="partition metadata"
      fi
    fi

    if [ "$detected_type" = "UNKNOWN" ] && [ -d "$mount_dir/usr/bin/idv" ]; then
      detected_type="DV"
      detection_source="partition dv marker"
    fi

    if [ "$detected_type" = "UNKNOWN" ] && [ -x "$mount_dir/usr/bin/idv/launcher/start_vm.sh" ]; then
      detected_type="DV"
      detection_source="partition dv launcher"
    fi

    # Fallback for generic/misnamed images: infer from installed kernel metadata
    if [ "$detected_type" = "UNKNOWN" ] && [ -d "$mount_dir/lib/modules" ]; then
      kernel_release=$(find "$mount_dir/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | head -n 1)

      if [ -n "$kernel_release" ]; then
        if [[ "$kernel_release" == *rt* ]]; then
          detected_type="RT"
          detection_source="kernel release"
        fi
      fi
    fi

    if [ "$detected_type" = "UNKNOWN" ] && [ -d "$mount_dir/boot" ]; then
      kernel_config=$(find "$mount_dir/boot" -maxdepth 1 -type f -name 'config-*' | head -n 1)

      if [ -n "$kernel_config" ] && [ -r "$kernel_config" ]; then
        if grep -q '^CONFIG_PREEMPT_RT=y' "$kernel_config" 2>/dev/null; then
          detected_type="RT"
          detection_source="kernel config"
        elif grep -q '^CONFIG_PREEMPT_DYNAMIC=y' "$kernel_config" 2>/dev/null; then
          detected_type="NON_RT"
          detection_source="kernel config"
        fi
      fi
    fi

    umount "$mount_dir" 2>/dev/null
  fi

  rmdir "$mount_dir" 2>/dev/null
  DETECTED_IMAGE_TYPE="$detected_type"
  IMAGE_TYPE_SOURCE="$detection_source"
}

# detect image type from image content first, then filename/path fallback
detect_image_type() {
  local image_path="$1"
  local image_partition="${2:-}"
  local detected_type="UNKNOWN"
  local detection_source="unknown"
  local lowered_path

  lowered_path=$(echo "$image_path" | tr '[:upper:]' '[:lower:]')

  if [ -n "$image_partition" ]; then
    detect_image_type_from_partition "$image_partition"
    detected_type="$DETECTED_IMAGE_TYPE"
    detection_source="$IMAGE_TYPE_SOURCE"
  fi

  if [ "$detected_type" = "UNKNOWN" ]; then
    detected_type=$(detect_emt_type_from_string "$image_path")

    if [ "$detected_type" != "UNKNOWN" ]; then
      case "$lowered_path" in
        */dv/* | */rt/* | */non-rt/* | */non_rt*) detection_source="path" ;;
        *) detection_source="filename" ;;
      esac
    fi
  fi

  DETECTED_IMAGE_TYPE="$detected_type"
  IMAGE_TYPE_SOURCE="$detection_source"
}

# validate RT/NON_RT/DV compatibility
validate_emt_compatibility() {
  local image_path="$1"
  local image_partition="${2:-}"
  local current_emt_type
  local image_type
  local image_type_source

  current_emt_type=$(detect_current_emt_type)
  detect_image_type "$image_path" "$image_partition"
  image_type="$DETECTED_IMAGE_TYPE"
  image_type_source="$IMAGE_TYPE_SOURCE"

  echo "Current EMT type: $current_emt_type"
  echo "Image type: $image_type"
  echo "Image type source: $image_type_source"

  # Check if types are known
  if [ "$current_emt_type" = "UNKNOWN" ]; then
    echo "Error: Unable to determine current EMT type from uname output: $(uname -a)"
    echo "Update blocked: current EMT type must be determinable (DV/RT/NON_RT)."
    return 1
  fi

  if [ "$image_type" = "UNKNOWN" ]; then
    echo "Error: Unable to determine EMT type from image metadata/path/filename: $(basename "$image_path")"
    echo "Update blocked: upgrade image type must be determinable (DV/RT/NON_RT)."
    return 1
  fi

  # Validate compatibility
  if [ "$current_emt_type" != "$image_type" ]; then
    echo "Error: $current_emt_type EMT detected, but $image_type image provided."
    echo "Please provide a $current_emt_type upgrade version instead."
    echo "Current EMT: $(uname -a)"
    return 1
  fi

  echo "EMT compatibility validated: $current_emt_type EMT with $image_type image"
  return 0
}

# Function to check the last command's exit status
check_success() {
  [ "$?" -ne 0 ] && {
    echo "Error: $1 failed."
    exit 1
  }
}

# Function to exit with an error message
error_exit() {
  echo "Error: $1"
  exit 1
}

# Extract SHA256 checksum safely from checksum file
extract_sha256_checksum() {
  local checksum_file="$1"
  local sha_id=""

  [ ! -r "$checksum_file" ] && error_exit "Checksum file is not readable: $checksum_file"

  # Prefer strict sha256sum line format: <64-hex> [whitespace] <filename>
  sha_id=$(grep -aEom1 '^[[:space:]]*[0-9a-fA-F]{64}([[:space:]]+|$)' "$checksum_file" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

  # Fallback: accept a file containing only the 64-hex digest
  if [ -z "$sha_id" ]; then
    sha_id=$(grep -aEom1 '[0-9a-fA-F]{64}' "$checksum_file" | tr '[:upper:]' '[:lower:]')
  fi

  if [ -z "$sha_id" ]; then
    error_exit "Invalid checksum file: $checksum_file. Provide a valid .sha256sum file (not a raw image)."
  fi

  echo "$sha_id"
}

# Function for consistent status logging
log_status() {
  local status="$1"
  local message="$2"
  case "$status" in
    success) echo "  ✓ $message" ;;
    error) echo "  ✗ $message" ;;
    warning) echo "  ⚠ $message" ;;
    info) echo "  • $message" ;;
    skip) echo "  ⊘ $message" ;;
  esac
}

# Print a section banner
print_section() {
  echo "========================================"
  [ -n "$1" ] && echo "$1"
  echo "========================================"
}

# Credential files managed during backup/restore
CREDENTIAL_FILES=(passwd shadow group)

# Function to backup a single file
backup_file() {
  local src="$1"
  local dest="$2"
  local desc="${3:-$(basename "$src")}"

  if [ ! -f "$src" ]; then
    log_status warning "$desc not found, skipping"
    return 1
  fi

  if cp -f "$src" "$dest"; then
    log_status success "$desc backed up"
    return 0
  else
    log_status error "Failed to backup $desc"
    return 1
  fi
}

# Function to perform before update
perform_update_check() {
  local image_path="$1"
  local loopdevice
  local mounted_check=false

  cleanup_update_check() {
    if $mounted_check; then
      umount /mnt 2>/dev/null
    fi
    [ -n "$loopdevice" ] && losetup -d "$loopdevice" 2>/dev/null
    rm -f /etc/cloud/input.txt /etc/cloud/update.raw
  }

  trap cleanup_update_check EXIT

  # Mandatory checks before the update
  # Decompress the image
  gunzip -c "$image_path" >/etc/cloud/update.raw

  # Set up the loop device with the decompressed image
  loopdevice=$(losetup --find --partscan --show /etc/cloud/update.raw)

  # Validate EMT compatibility using actual image content
  if ! validate_emt_compatibility "$image_path" "${loopdevice}p2"; then
    exit 1
  fi

  # Extract UUID from the loop device partition
  local uuid
  uuid=$(lsblk -no UUID "${loopdevice}p2")

  # Get boot UUID from bootctl list
  bootctl list | grep -E 'default|boot_uuid' >/etc/cloud/input.txt
  local boot_uuid
  boot_uuid=$(awk '/\(default\)/ {getline; if ($0 ~ /options/) {match($0, /boot_uuid=([a-f0-9-]+)/, arr); print arr[1]; exit}}' /etc/cloud/input.txt)

  # Check #1 Compare UUIDs
  if [ "$uuid" = "$boot_uuid" ]; then
    echo "UUID of update image and provisioned image are the same"
    exit 1
  fi

  # Check #2 Upgrades only with future dates
  # Convert both dates to seconds since epoch
  mount "${loopdevice}p2" /mnt
  mounted_check=true
  IMAGE_BUILD_DATE=$(sed -n 's/^IMAGE_BUILD_DATE=//p' /etc/image-id)
  FUTURE_DATE=$(sed -n 's/^IMAGE_BUILD_DATE=//p' /mnt/etc/image-id)
  image_build_epoch=$(convert_to_epoch "$IMAGE_BUILD_DATE")
  upgrade_image_date_epoch=$(convert_to_epoch "$FUTURE_DATE")
  umount /mnt
  mounted_check=false

  if [ "$upgrade_image_date_epoch" -le "$image_build_epoch" ]; then
    echo "Downgrades and same-build updates are not supported. Only strictly newer images are allowed."
    exit 1
  else
    echo "The upgrade image build date is strictly newer than the provisioned image."
  fi

  trap - EXIT
  cleanup_update_check
}

# Function to display usage information
show_help() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -u <URL>       URL to Microvisor image base"
  echo "  -r <release>   Release version"
  echo "  -v <version>   Build version"
  echo "  -i <image>     Direct path to Microvisor image"
  echo "  -c <checksum>  Path to checksum file"
  echo "  -o             OXM mode"
  echo "  -h             Display this help message"
  exit 0
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Temporary directory for downloads
TEMP_DIR="/tmp/microvisor-update"
mkdir -p "$TEMP_DIR"
check_success "Creating temporary directory"

# Initialize variables
URL_MODE=false
OXM_MODE=false
IMAGE_BASE_URL=""
IMG_VER=""
IMAGE_BUILD=""
IMAGE_PATH=""
SHA_FILE=""

while getopts ":u:r:v:i:c:oh" opt; do
  case $opt in
    u)
      URL_MODE=true
      IMAGE_BASE_URL="$OPTARG"
      ;;
    r)
      IMG_VER="$OPTARG"
      ;;
    v)
      IMAGE_BUILD="$OPTARG"
      ;;
    i)
      IMAGE_PATH="$OPTARG"
      ;;
    c)
      SHA_FILE="$OPTARG"
      ;;
    o)
      OXM_MODE=true
      ;;
    h)
      show_help
      ;;
    \?)
      error_exit "Invalid option: -$OPTARG"
      ;;
    :)
      error_exit "Option -$OPTARG requires an argument."
      ;;
  esac
done

# Specify the configuration file based on mode
config_file=$($OXM_MODE && echo "/etc/cloud/cloud.cfg.d/99_infra.cfg" || echo "/etc/cloud/config-file")

# Validate configuration file exists
[[ ! -f "$config_file" ]] && {
  echo "Configuration file not found: $config_file"
  exit 1
}

# Validate configured user before preparing update (non-OXM mode)
if [ "$OXM_MODE" = false ]; then
  configured_user=$(grep '^user_name=' "$config_file" 2>/dev/null | cut -d '=' -f2 | tr -d '"')
  [ -z "$configured_user" ] && error_exit "user_name not found in $config_file. Cannot proceed with update."
  id "$configured_user" >/dev/null 2>&1 || error_exit "Configured user '$configured_user' does not exist. Cannot proceed with update."
  log_status success "Pre-update user validation passed for '$configured_user'"
else
  log_status info "OXM mode: skipping pre-update user validation"
fi

# URL mode
if $URL_MODE; then
  # Validate required arguments
  [ -z "$IMAGE_BASE_URL" ] || [ -z "$IMG_VER" ] || [ -z "$IMAGE_BUILD" ] &&
    error_exit "Usage: $0 -u <URL_to_Microvisor_image_base> -r <release> -v <build_version>"

  # Check the domain and construct the IMAGE_URL
  case "$IMAGE_BASE_URL" in
    *files-rs.edgeorchestration.intel.com*)
      IMAGE_URL="${IMAGE_BASE_URL}/edge-readonly-${IMG_VER}.${IMAGE_BUILD}-signed.raw.gz"
      ;;
    *af01p-png.devtools.intel.com*)
      IMAGE_URL="${IMAGE_BASE_URL}/${IMG_VER}/${IMAGE_BUILD}/edge-readonly-${IMG_VER}.${IMAGE_BUILD}-signed.raw.gz"
      ;;
    *)
      error_exit "Unsupported domain in URL: $IMAGE_BASE_URL"
      ;;
  esac

  echo "Constructed IMAGE URL: $IMAGE_URL"

  # Download the Microvisor image
  IMAGE_PATH="$TEMP_DIR/edge_microvisor_toolkit.raw.gz"
  echo "Downloading microvisor image from $IMAGE_URL..."
  curl -k "$IMAGE_URL" -o "$IMAGE_PATH" || error_exit "Failed to download microvisor image"

  # Download the SHA256 checksum file
  SHA_FILE="$TEMP_DIR/edge_microvisor_readonly.sha256sum"
  SHA_URL="${IMAGE_URL}.sha256sum"
  echo "Downloading SHA256 checksum from $SHA_URL..."
  curl -k "$SHA_URL" -o "$SHA_FILE" || error_exit "Failed to download SHA256 checksum"

  # Extract the SHA256 checksum
  SHA_ID=$(extract_sha256_checksum "$SHA_FILE")
  echo "Extracted SHA256 checksum: $SHA_ID"
else
  # Direct path mode - validate required arguments
  [ -z "$IMAGE_PATH" ] || [ -z "$SHA_FILE" ] && error_exit "Usage: $0 -i <Direct_path_to_Microvisor_image> -c <Checksum_file>"

  # Verify that the files exist
  [ ! -f "$IMAGE_PATH" ] && error_exit "Microvisor image file not found at $IMAGE_PATH"
  [ ! -f "$SHA_FILE" ] && error_exit "SHA256 checksum file not found at $SHA_FILE"

  case "$SHA_FILE" in
    *.raw | *.raw.gz | *.img | *.img.gz)
      error_exit "Checksum file appears to be an image: $SHA_FILE. Please provide a .sha256sum file with -c."
      ;;
  esac

  # Extract the SHA256 checksum
  SHA_ID=$(extract_sha256_checksum "$SHA_FILE")
  echo "Extracted SHA256 checksum: $SHA_ID"
fi

# Call the function with the path to the image
perform_update_check "$IMAGE_PATH"

# Invoke the os-update-tool.sh script
echo "Initiating OS update..."
/usr/bin/os-update-tool.sh -w -u "$IMAGE_PATH" -s "$SHA_ID"
check_success "Writing OS image"
/usr/bin/os-update-tool.sh -a
check_success "Applying OS image"

# shellcheck disable=SC2034  # INSTALLER_CFG is used later in the script (lines 760, 762, 788)
INSTALLER_CFG="/etc/cloud/cloud.cfg.d/installer.cfg"

# Define paths
TMP_DIR="/etc/cloud"
COMMIT_UPDATE_SCRIPT="$TMP_DIR/commit_update.sh"

# Backup user credentials with error handling
print_section "Backing up user credentials..."

credential_backup_failed=0
for cred_file in "${CREDENTIAL_FILES[@]}"; do
  if ! backup_file "/etc/$cred_file" "/etc/cloud/${cred_file}_backup" "$cred_file"; then
    ((credential_backup_failed++))
  fi
done

if [ "$credential_backup_failed" -gt 0 ]; then
  error_exit "Failed to backup $credential_backup_failed credential file(s). Cannot proceed with update."
fi

echo "User credentials backed up successfully."
print_section

# Extract paths under write_files and store them in a list
print_section "Starting Backup Process"

if paths_list=$(extract_write_files_paths "$config_file"); then
  if [ -z "$paths_list" ]; then
    echo "WARNING: No paths extracted from config file"
  else
    if path_count=$(echo "$paths_list" | wc -w); then
      echo "Extracted $path_count paths from config file"
    else
      echo "WARNING: Could not count extracted paths"
    fi
  fi
else
  error_exit "Failed to extract paths from config file: $config_file"
fi

# Create backup directory with error handling
if ! mkdir -p /etc/cloud/backup; then
  error_exit "Failed to create backup directory /etc/cloud/backup"
fi

paths_file="/etc/cloud/backup/paths_list.txt"
backup_success_count=0
backup_fail_count=0

# Backup files from write_files section
echo "Backing up files from write_files section..."
for path in $paths_list; do
  [ ! -e "$path" ] && {
    log_status skip "$(basename "$path") - not found"
    continue
  }

  echo "  Backing up: $path"
  if cp -rf "$path" "/etc/cloud/backup/"; then
    ((backup_success_count++))
    log_status success "Success"
  else
    ((backup_fail_count++))
    log_status error "Failed to backup $path"
  fi
done

# Backup X11 xorg.conf.d configuration files explicitly from /etc
echo "----------------------------------------"
echo "Backing up X11 xorg.conf.d configuration files..."

for x11_file in 10-extensions.conf 10-serverflags.conf; do
  x11_path="/etc/X11/xorg.conf.d/$x11_file"
  if [ -f "$x11_path" ]; then
    echo "  Backing up: $x11_file"
    if cp -f "$x11_path" "/etc/cloud/backup/$x11_file"; then
      paths_list="$paths_list $x11_path"
      ((backup_success_count++))
      log_status success "Success"
    else
      ((backup_fail_count++))
      log_status error "Failed to backup $x11_file"
    fi
  else
    log_status warning "$x11_file not found - will be skipped"
  fi
done

# Save paths to a file with error handling
echo "----------------------------------------"
if echo "$paths_list" >"$paths_file" 2>/dev/null; then
  if [ -f "$paths_file" ]; then
    file_size=$(stat -c%s "$paths_file" 2>/dev/null || echo "0")
    echo "✓ Paths list saved to $paths_file (size: $file_size bytes)"
  else
    error_exit "Paths file created but cannot be verified: $paths_file"
  fi
else
  error_exit "Failed to save paths list to $paths_file (check disk space and permissions)"
fi

# Verify backup directory and files
echo "========================================"
echo "Backup Summary:"
echo "  Files backed up successfully: $backup_success_count"
echo "  Files failed to backup: $backup_fail_count"
echo "----------------------------------------"
echo "Backup directory contents:"
ls -lah /etc/cloud/backup/
echo "========================================"

# Exit if critical backups failed
if [ "$backup_fail_count" -gt 0 ]; then
  echo "WARNING: $backup_fail_count files failed to backup"
  echo "Review errors above. Continuing with update, but some files may not be restored."
fi

# Always recreate commit_update.sh to ensure latest logic is used
print_section "Creating commit_update.sh script..."
if cat <<'EOF' >"$COMMIT_UPDATE_SCRIPT"; then
#!/bin/bash

# Log file for debugging
LOG_FILE="/var/log/os-update-commit.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "OS Update Commit Script Started: $(date)"
echo "========================================"

# Helper function for consistent status logging
log_status() {
  local status="$1" message="$2"
  case "$status" in
    success) echo "  ✓ $message" ;;
    error) echo "  ✗ $message" ;;
    warning) echo "  ⚠ $message" ;;
    info) echo "  • $message" ;;
    skip) echo "  ⊘ $message" ;;
  esac
}

# Print a section banner
print_section() {
  echo "========================================"
  [ -n "$1" ] && echo "$1"
  echo "========================================"
}

# Credential files managed during backup/restore
CREDENTIAL_FILES=(passwd shadow group)

# Determine if an A/B upgrade commit is pending
# NOTE: Credential/file restoration and user configuration must run on EVERY boot
# because the read-only rootfs uses an ephemeral overlay — changes to /etc/passwd,
# /etc/shadow, /etc/group do NOT persist across reboots.
# Only the os-update-tool.sh -c commit step is gated by upgrade_pending.
upgrade_pending=false
if [ -f "/etc/cloud/upgrade_status" ]; then
  if upgrade_status=$(cat "/etc/cloud/upgrade_status" 2>/dev/null); then
    if [ "$upgrade_status" = "true" ]; then
      upgrade_pending=true
      log_status info "Pending upgrade detected (upgrade_status=true); will commit after restore"
    else
      log_status info "upgrade_status='$upgrade_status' - no pending upgrade commit"
    fi
  else
    log_status warning "Unable to read upgrade_status file"
  fi
else
  log_status info "upgrade_status file not found - no pending upgrade commit"
fi

# Validate required backup files exist
print_section "Validating Backup Files"

missing_backups=0
for required_file in "${CREDENTIAL_FILES[@]/%/_backup}"; do
  backup_path="/etc/cloud/$required_file"
  if [ ! -e "$backup_path" ]; then
    log_status error "$required_file not found at $backup_path"
    ((missing_backups++))
  elif file_size=$(stat -c%s "$backup_path" 2>/dev/null) && [ "$file_size" -eq 0 ]; then
    log_status error "$required_file is empty (0 bytes)"
    ((missing_backups++))
  else
    log_status success "$required_file validated (${file_size:-unknown} bytes)"
  fi
done

has_credential_backups=true
if [ $missing_backups -gt 0 ]; then
  has_credential_backups=false
  echo "========================================"
  echo "WARNING: $missing_backups credential backup file(s) missing or invalid"
  echo "Expected backup files:"
  echo "  - /etc/cloud/passwd_backup"
  echo "  - /etc/cloud/shadow_backup"
  echo "  - /etc/cloud/group_backup"
  if [ "$upgrade_pending" = true ]; then
    echo "CRITICAL: Credential backups required for pending upgrade commit."
    echo "========================================"
    exit 1
  else
    echo "No pending upgrade - skipping credential restore."
    echo "========================================"
  fi
else
  log_status success "All required backup files validated"
fi
echo "========================================"

# Restore user credentials (runs on every boot if backups exist)
print_section "Restoring user credentials..."

credential_restore_failed=0

if [ "$has_credential_backups" = false ]; then
  log_status skip "No credential backups available - skipping restore"
else

for cred_file in "${CREDENTIAL_FILES[@]}"; do
  src="/etc/cloud/${cred_file}_backup"
  dest="/etc/$cred_file"

  if [ ! -f "$src" ]; then
    log_status warning "$cred_file backup not found at $src"
    ((credential_restore_failed++))
    continue
  fi

  # Verify source file is readable and non-empty
  if [ ! -r "$src" ]; then
    log_status error "$cred_file backup not readable: $src"
    ((credential_restore_failed++))
    continue
  fi

  src_size=$(stat -c%s "$src" 2>/dev/null || echo "0")
  if [ "$src_size" -eq 0 ]; then
    log_status error "$cred_file backup is empty (0 bytes)"
    ((credential_restore_failed++))
    continue
  fi

  # Backup existing file before overwriting and restore
  [ -f "$dest" ] && cp "$dest" "${dest}.pre-update" 2>/dev/null

  # Restore with verification
  if cp "$src" "$dest" 2>/dev/null && [ -f "$dest" ]; then
    if dest_size=$(stat -c%s "$dest" 2>/dev/null) && [ "$dest_size" -eq "$src_size" ]; then
      log_status success "$cred_file restored and verified ($dest_size bytes)"
    else
      log_status error "$cred_file size mismatch (expected: $src_size, got: ${dest_size:-unknown})"
      ((credential_restore_failed++))
    fi
  else
    log_status error "Failed to restore $cred_file (check permissions)"
    ((credential_restore_failed++))
  fi
done

if [ $credential_restore_failed -gt 0 ]; then
  echo "========================================"
  echo "WARNING: Failed to restore $credential_restore_failed credential file(s)"
  if [ "$upgrade_pending" = true ]; then
    echo "CRITICAL: Credential restore required for pending upgrade commit."
    echo "Commit workflow aborted to avoid inconsistent user state."
    echo "Manual intervention required."
    echo "========================================"
    exit 1
  else
    echo "No pending upgrade - continuing despite restore failures."
    echo "========================================"
  fi
fi

fi  # end of has_credential_backups else block

# Restore config files (runs on every boot if backup exists)
if [ ! -f "/etc/cloud/backup/paths_list.txt" ]; then
  echo "========================================"
  if [ "$upgrade_pending" = true ]; then
    echo "CRITICAL ERROR: paths_list.txt not found at /etc/cloud/backup/paths_list.txt"
    echo "File restoration cannot proceed without paths list."
    echo "This may indicate a backup failure during update preparation."
    echo "========================================"
    exit 1
  else
    log_status info "paths_list.txt not found - no config files to restore (normal on non-upgrade boot)"
    echo "========================================"
  fi
else
  echo "========================================"
  echo "Starting File Restoration"
  echo "========================================"

  # Validate paths_list.txt is readable
  if [ ! -r "/etc/cloud/backup/paths_list.txt" ]; then
    echo "ERROR: paths_list.txt exists but is not readable (check permissions)"
    exit 1
  fi

  if paths_list=$(cat "/etc/cloud/backup/paths_list.txt" 2>/dev/null); then
    if [ -z "$paths_list" ]; then
      log_status warning "paths_list.txt is empty - no files to restore"
    elif path_count=$(echo $paths_list | wc -w 2>/dev/null) && [ "$path_count" -gt 0 ]; then
      echo "Found $path_count paths to restore"
    else
      log_status warning "Could not count paths to restore"
    fi
  else
    echo "ERROR: Failed to read paths_list.txt"
    exit 1
  fi

  echo "----------------------------------------"
  echo "Backup directory contents:"
  ls -lah /etc/cloud/backup/
  echo "----------------------------------------"

  restore_success_count=0
  restore_fail_count=0
  restore_skip_count=0

  echo "Restoring backed up files..."
  for file_path in $paths_list; do
    name=$(basename "$file_path")

    # Skip paths_list.txt
    [ "$name" = "paths_list.txt" ] && { log_status skip "Skipping paths_list.txt"; ((restore_skip_count++)); continue; }

    # Check backup file exists
    [ ! -f "/etc/cloud/backup/$name" ] && { log_status warning "Backup file not found: $name"; ((restore_fail_count++)); continue; }

    echo "Processing: $file_path"

    # Ensure parent directory exists
    parent_dir=$(dirname "$file_path")
    if [ ! -d "$parent_dir" ]; then
      mkdir -p "$parent_dir" || { log_status error "Failed to create directory: $parent_dir"; ((restore_fail_count++)); continue; }
    fi

    # Restore file with ownership and permissions
    if cp -fp "/etc/cloud/backup/$name" "$file_path" && chown root:root "$file_path" 2>/dev/null && chmod 644 "$file_path" 2>/dev/null; then
      if [ -f "$file_path" ]; then
        owner=$(stat -c '%U:%G' "$file_path" 2>/dev/null || echo "unknown")
        perms=$(stat -c '%a' "$file_path" 2>/dev/null || echo "unknown")
        log_status success "Restored: $file_path (owner: $owner, perms: $perms)"
        ((restore_success_count++))
      else
        log_status error "File not found after copy: $file_path"
        ((restore_fail_count++))
      fi
    else
      log_status error "Failed to copy/set permissions: $name"
      ((restore_fail_count++))
    fi
  done

  echo "========================================"
  echo "File Restoration Summary:"
  echo "  Successfully restored: $restore_success_count"
  echo "  Failed to restore: $restore_fail_count"
  echo "  Skipped: $restore_skip_count"
  echo "========================================"

  if [ $restore_fail_count -gt 0 ]; then
    echo "WARNING: $restore_fail_count file(s) failed to restore."
    echo "Check logs above for details. System may require manual intervention."
  else
    log_status success "All files restored successfully"
  fi
fi

# Do not delete backup directory or credential backups here.
# commit_update.sh will clean them up after a successful restore on the next boot.

# Add user to sudo group
print_section "Configuring User Permissions"

CONFIG_FILE="/etc/cloud/config-file"
OXM_CONFIG_FILE="/etc/cloud/cloud.cfg.d/99_infra.cfg"

if [ -f "$CONFIG_FILE" ]; then
  ACTIVE_CONFIG_FILE="$CONFIG_FILE"
elif [ -f "$OXM_CONFIG_FILE" ]; then
  ACTIVE_CONFIG_FILE="$OXM_CONFIG_FILE"
else
  log_status error "No user config file found (checked $CONFIG_FILE and $OXM_CONFIG_FILE)"
  exit 1
fi

user_name=$(grep '^user_name=' "$ACTIVE_CONFIG_FILE" 2>/dev/null | cut -d '=' -f2 | tr -d '"')

if [ -z "$user_name" ]; then
  log_status error "user_name not found in $ACTIVE_CONFIG_FILE"
  exit 1
fi

echo "User name: $user_name"
if id "$user_name" >/dev/null 2>&1; then
  if usermod -aG sudo "$user_name" 2>/dev/null; then
    log_status success "User '$user_name' added to sudo group"
  else
    log_status error "Failed to add user to sudo group"
    exit 1
  fi
else
  log_status error "User '$user_name' does not exist after credential restore"
  if [ "$upgrade_pending" = true ]; then
    exit 1
  fi
fi
echo "========================================"

# Commit the update (ONLY when upgrade is pending)
if [ "$upgrade_pending" = true ]; then

# Check boot configuration
print_section "Verifying Boot Configuration"

if bootctl list >/dev/null 2>&1; then
  log_status success "Boot configuration verified"
  bootctl list 2>&1
else
  log_status error "bootctl list command failed (exit code: $?)"
  echo "WARNING: Boot configuration may have issues"
fi
echo "========================================"

print_section "Committing OS Update"

echo "Upgrade status is true, committing update..."

if os-update-tool.sh -c 2>&1; then
  log_status success "Commit update successful"
  commit_success=true
else
  commit_exit_code=$?
  log_status error "Failed to commit update (exit code: $commit_exit_code)"
  commit_success=false
fi

if [ "$commit_success" = false ]; then
  echo "========================================"
  echo "CRITICAL ERROR: OS update commit failed!"
  echo "System may be in an inconsistent state."
  echo "Exit code: ${commit_exit_code:-unknown}"
  echo "Manual intervention required."
  echo "========================================"
  exit 1
fi
echo "========================================"

# Reset upgrade status and verify image build date
print_section "Post-Commit Validation"

echo "Resetting upgrade status..."
if sudo tee /etc/cloud/upgrade_status <<<'false' >/dev/null 2>&1; then
  # Verify the file was actually updated
  new_status=$(cat /etc/cloud/upgrade_status 2>/dev/null)
  if [ "$new_status" = "false" ]; then
    log_status success "Upgrade status reset to false"
  else
    log_status warning "Upgrade status file written but contains: '$new_status'"
  fi
else
  log_status warning "Failed to reset upgrade_status (non-critical)"
fi

fi  # end of upgrade_pending block

# Always display IMAGE_BUILD_DATE
echo "----------------------------------------"
if [ -f "/etc/image-id" ]; then
  IMAGE_BUILD_DATE=$(grep '^IMAGE_BUILD_DATE=' /etc/image-id 2>/dev/null | cut -d '=' -f2)
  if [ -n "$IMAGE_BUILD_DATE" ]; then
    echo "Current IMAGE_BUILD_DATE: $IMAGE_BUILD_DATE"
    log_status success "Image build date retrieved"
  else
    log_status warning "IMAGE_BUILD_DATE not found in /etc/image-id"
  fi
else
  log_status warning "/etc/image-id file not found"
fi

echo "========================================"
echo "OS Update Commit Script Completed: $(date)"
echo "========================================"
EOF

  log_status success "commit_update.sh script created successfully"
else
  error_exit "Failed to create commit_update.sh script - update cannot proceed"
fi

# Validate commit_update.sh was created successfully
print_section "Validating commit_update.sh script..."

# Check file exists
if [ ! -f "$COMMIT_UPDATE_SCRIPT" ]; then
  error_exit "CRITICAL: $COMMIT_UPDATE_SCRIPT not found after creation"
fi
log_status success "Script file exists"

# Ensure the new script is executable
if chmod +x "$COMMIT_UPDATE_SCRIPT" 2>/dev/null; then
  log_status success "Script made executable"
else
  error_exit "Failed to make $COMMIT_UPDATE_SCRIPT executable (check permissions)"
fi

# Verify script size (should be non-empty)
if script_size=$(stat -c%s "$COMMIT_UPDATE_SCRIPT" 2>/dev/null); then
  if [ "$script_size" -gt 0 ]; then
    log_status success "Script size validated: $script_size bytes"
  else
    error_exit "CRITICAL: commit_update.sh is empty (0 bytes) - update cannot proceed"
  fi
else
  error_exit "Cannot stat $COMMIT_UPDATE_SCRIPT - file system error"
fi

# Verify script has bash shebang
first_line=$(head -n 1 "$COMMIT_UPDATE_SCRIPT" 2>/dev/null)
if [ "$first_line" = "#!/bin/bash" ]; then
  log_status success "Script shebang validated"
else
  error_exit "Invalid script format - expected '#!/bin/bash' shebang"
fi

echo "========================================="

# Check if installer.cfg exists and update it if necessary (skip in OXM mode)
print_section "Configuring installer.cfg..."

if [ "$OXM_MODE" = false ]; then
  if [ ! -f "$INSTALLER_CFG" ]; then
    error_exit "CRITICAL: installer.cfg not found at $INSTALLER_CFG (required for non-OXM mode)"
  fi

  # Check if the commit_update.sh entry is already present
  if grep -q "bash $COMMIT_UPDATE_SCRIPT" "$INSTALLER_CFG" 2>/dev/null; then
    log_status success "commit_update.sh entry already exists in installer.cfg"
  else
    echo "Adding commit_update.sh to installer.cfg..."

    # Backup installer.cfg before modification
    if cp "$INSTALLER_CFG" "${INSTALLER_CFG}.backup" 2>/dev/null; then
      log_status success "Created backup: ${INSTALLER_CFG}.backup"
    else
      error_exit "Failed to backup installer.cfg before modification"
    fi

    # Use awk to find the end of the runcmd block and append new content
    if awk -v script="$COMMIT_UPDATE_SCRIPT" '
      BEGIN {
        line = "    bash " script
        added = 0
      }
      /^runcmd:/ { runcmd = 1 }

      runcmd && /source \/etc\/environment/ {
        print
        print line
        added = 1
        next
      }

      {
        print
      }

      END {
        if (!added) {
          print line
        }
      }
    ' "$INSTALLER_CFG" > "${INSTALLER_CFG}.tmp" 2>/dev/null; then
      if [ -s "${INSTALLER_CFG}.tmp" ]; then
        if mv "${INSTALLER_CFG}.tmp" "$INSTALLER_CFG" 2>/dev/null; then
          log_status success "installer.cfg updated successfully"
        else
          rm -f "${INSTALLER_CFG}.tmp"
          error_exit "Failed to replace installer.cfg with updated version"
        fi
      else
        rm -f "${INSTALLER_CFG}.tmp"
        error_exit "Generated installer.cfg is empty - aborting update"
      fi
    else
      rm -f "${INSTALLER_CFG}.tmp"
      error_exit "Failed to process installer.cfg with awk"
    fi
  fi
else
  log_status info "OXM mode: Skipping installer.cfg configuration"
fi
echo "========================================="

# Install boot loader entries
print_section "Installing boot loader entries..."

if bootctl install 2>&1; then
  log_status success "bootctl install successful"
else
  boot_exit_code=$?
  if [ $boot_exit_code -eq 1 ]; then
    log_status warning "bootctl install failed (exit code: $boot_exit_code) - may already be installed"
  else
    log_status error "bootctl install failed with exit code: $boot_exit_code"
    echo "WARNING: Boot loader installation issue detected, but continuing..."
  fi
fi
echo "========================================="

# Set upgrade status and reboot
print_section "Finalizing Update and Preparing Reboot"

echo "Setting upgrade status to true..."
if sudo tee /etc/cloud/upgrade_status <<<'true' >/dev/null 2>&1; then
  log_status success "Upgrade status set successfully"

  # Verify upgrade status was set
  if [ -f /etc/cloud/upgrade_status ]; then
    if actual_status=$(cat /etc/cloud/upgrade_status 2>/dev/null); then
      if [ "$actual_status" = "true" ]; then
        log_status success "Verified upgrade status: $actual_status"
      else
        log_status error "Upgrade status verification failed - expected 'true', got: '$actual_status'"
        error_exit "CRITICAL: Upgrade status mismatch - cannot proceed with reboot"
      fi
    else
      error_exit "Cannot read upgrade_status file after creation"
    fi
  else
    error_exit "Upgrade status file not created at /etc/cloud/upgrade_status"
  fi
else
  error_exit "Cannot proceed with reboot - failed to set upgrade status (check permissions)"
fi

echo "========================================="
echo "UPDATE PREPARATION SUCCESSFUL!"
echo "========================================="
echo "Summary:"
echo "  ✓ OS image written and applied"
echo "  ✓ User credentials backed up"
echo "  ✓ Configuration files backed up ($backup_success_count files)"
echo "  ✓ Commit script created and validated"
echo "  ✓ Installer configuration updated"
echo "  ✓ Boot loader configured"
echo "  ✓ Upgrade status set"
echo "========================================="
echo "System will reboot in 5 seconds..."
echo "After reboot, commit_update.sh will:"
echo "  • Restore user credentials"
echo "  • Restore configuration files"
echo "  • Commit the A/B update"
echo "========================================="

# Final validation before reboot
echo "Performing final pre-reboot validation..."
validation_errors=0

[ ! -f "$COMMIT_UPDATE_SCRIPT" ] && {
  log_status error "commit_update.sh missing"
  ((validation_errors++))
}
[ ! -x "$COMMIT_UPDATE_SCRIPT" ] && {
  log_status error "commit_update.sh not executable"
  ((validation_errors++))
}
[ ! -f /etc/cloud/upgrade_status ] && {
  log_status error "upgrade_status file missing"
  ((validation_errors++))
}
[ ! -f /etc/cloud/backup/paths_list.txt ] && {
  log_status error "paths_list.txt missing"
  ((validation_errors++))
}
[ ! -d /etc/cloud/backup ] && {
  log_status error "backup directory missing"
  ((validation_errors++))
}

for cred_file in "${CREDENTIAL_FILES[@]}"; do
  [ ! -s "/etc/cloud/${cred_file}_backup" ] && {
    log_status error "required credential backup missing or empty: /etc/cloud/${cred_file}_backup"
    ((validation_errors++))
  }
done

if [ "$validation_errors" -gt 0 ]; then
  error_exit "Pre-reboot validation failed with $validation_errors error(s) - aborting reboot"
fi

log_status success "Pre-reboot validation passed"
echo "========================================="

sleep 5

if reboot; then
  # This will not execute if reboot is successful
  :
else
  error_exit "Reboot command failed - please reboot manually"
fi
