#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Source the environment variables
source /etc/environment

# set -x

# Function to extract paths under the write_files section
extract_write_files_paths() {
  local config_file="$1"
  local in_write_files_section=false
  local paths=()

  while IFS= read -r line; do
    # Check if the line contains the start of the write_files section
    if [[ "$line" =~ ^write_files: ]]; then
      in_write_files_section=true
      continue
    fi

    # If we are in the write_files section, look for paths
    if $in_write_files_section; then
      # Check if the line contains a path
      if [[ "$line" =~ path:\ (\/[^ ]+) ]]; then
        paths+=("${BASH_REMATCH[1]}")
      fi

      # Check for the end of the write_files section (assuming next section starts with a comment or another keyword)
      if [[ "$line" =~ ^[^[:space:]] ]]; then
        in_write_files_section=false
      fi
    fi
  done < "$config_file"

  # Return the list of paths
  echo "${paths[@]}"
}

# Function to convert date string to seconds since epoch
convert_to_epoch() {
    local date_string="$1"
    date -d "${date_string:0:8} ${date_string:8:2}:${date_string:10:2}:${date_string:12:2}" +%s
}

# detect current emt type (RT or Non-RT)
detect_current_emt_type() {
    local uname_output
    uname_output=$(uname -a)

    if echo "$uname_output" | grep -q "PREEMPT_RT"; then
        echo "RT"
    elif echo "$uname_output" | grep -q "PREEMPT_DYNAMIC"; then
        echo "NON_RT"
    else
        # If neither PREEMPT_RT nor PREEMPT_DYNAMIC is found
        echo "UNKNOWN"
    fi
}

# detect image type from filename
detect_image_type() {
    local image_path="$1"
    local image_filename
    image_filename=$(basename "$image_path")

    if echo "$image_filename" | grep -q "edge-readonly-rt-"; then
        echo "RT"
    elif echo "$image_filename" | grep -q "edge-readonly-" && ! echo "$image_filename" | grep -q "edge-readonly-rt-"; then
        echo "NON_RT"
    else
        echo "UNKNOWN"
    fi
}

# validate RT/Non-RT compatibility
validate_emt_compatibility() {
    local image_path="$1"
    local current_emt_type
    local image_type

    current_emt_type=$(detect_current_emt_type)
    image_type=$(detect_image_type "$image_path")

    echo "Current EMT type: $current_emt_type"
    echo "Image type: $image_type"

    # Check if types are known
    if [ "$current_emt_type" = "UNKNOWN" ]; then
        echo "Warning: Unable to determine current EMT type from uname output: $(uname -a)"
        echo "Proceeding with update without RT/Non-RT validation..."
        return 0
    fi

    if [ "$image_type" = "UNKNOWN" ]; then
        echo "Warning: Unable to determine EMT type from filename: $(basename "$image_path")"
        echo "Proceeding with update without RT/Non-RT validation..."
        return 0
    fi

    # Validate compatibility
    if [ "$current_emt_type" != "$image_type" ]; then
        if [ "$current_emt_type" = "RT" ] && [ "$image_type" = "NON_RT" ]; then
            echo "Error: RT EMT detected, but Non-RT image provided."
            echo "Please provide an RT upgrade version instead."
            echo "Current EMT: $(uname -a)"
            exit 1
        elif [ "$current_emt_type" = "NON_RT" ] && [ "$image_type" = "RT" ]; then
            echo "Error: Non-RT EMT detected, but RT image provided."
            echo "Please provide a Non-RT upgrade version instead."
            echo "Current EMT: $(uname -a)"
            exit 1
        fi
    else
        echo "EMT compatibility validated: $current_emt_type EMT with $image_type image"
    fi
}

# Specify the configuration file
config_file="/etc/cloud/config-file"

# Check if the file exists
if [[ ! -f "$config_file" ]]; then
  echo "Configuration file not found: $config_file"
  exit 1
fi

# Function to check the last command's exit status
check_success() {
    if [ "$?" -ne 0 ]; then
        echo "Error: $1 failed."
        exit 1
    fi
}

# Function to exit with an error message
error_exit() {
    echo "Error: $1"
    exit 1
}

# Function to perform before update 
perform_update_check() {
    local image_path="$1"

    # Validate RT/Non-RT emt compatibility
    validate_emt_compatibility "$image_path"

    # Mandatory checks before the update

    # Decompress the image
    gunzip -c "$image_path" > /etc/cloud/update.raw

    # Set up the loop device with the decompressed image
    loopdevice=$(losetup --find --partscan --show /etc/cloud/update.raw)

    # Extract UUID from the loop device partition
    local uuid
    uuid=$(lsblk -no UUID "$loopdevice"p2)

    # Get boot UUID from bootctl list
    bootctl list | grep -E 'default|boot_uuid' > /etc/cloud/input.txt
    local boot_uuid
    boot_uuid=$(awk '/\(default\)/ {getline; if ($0 ~ /options/) {match($0, /boot_uuid=([a-f0-9-]+)/, arr); print arr[1]; exit}}' /etc/cloud/input.txt)

    # Clean up temporary files
    rm -rf /etc/cloud/input.txt /etc/cloud/update.raw

    # Check #1 Compare UUIDs
    if [ "$uuid" = "$boot_uuid" ]; then
        echo "UUID of update image and provisioned image are the same"
	losetup -d "$loopdevice"
        exit 1
    fi

    # Check #2 Upgrades only with future dates
    # Convert both dates to seconds since epoch
    mount "$loopdevice"p2 /mnt
    IMAGE_BUILD_DATE=$(sed -n 's/^IMAGE_BUILD_DATE=//p' /etc/image-id)
    FUTURE_DATE=$(sed -n 's/^IMAGE_BUILD_DATE=//p' /mnt/etc/image-id)
    image_build_epoch=$(convert_to_epoch "$IMAGE_BUILD_DATE")
    upgrade_image_date_epoch=$(convert_to_epoch "$FUTURE_DATE")
    umount /mnt

    if [ "$upgrade_image_date_epoch" -lt "$image_build_epoch" ]; then
       echo "Downgrades are not supported. Only upgrades with images having a future build date are allowed."
       losetup -d "$loopdevice"
       exit 1 
    else
       echo "The image build date is on or after the future date."
    fi

    # Detach the loop device
    losetup -d "$loopdevice"
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
IMAGE_BASE_URL=""
IMG_VER=""
IMAGE_BUILD=""
IMAGE_PATH=""
SHA_FILE=""

while getopts ":u:r:v:i:c:h" opt; do
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

# URL mode
if $URL_MODE; then
    # Check if all required arguments are provided for URL mode
    if [ -z "$IMAGE_BASE_URL" ] || [ -z "$IMG_VER" ] || [ -z "$IMAGE_BUILD" ]; then
        # Example usage: ./os-update.sh -u https://af01p-png.devtools.intel.com/artifactory/tiberos-png-local/non-rt -r 3.0 -v 20250608.2200
        error_exit "Usage: $0 -u <URL_to_Microvisor_image_base> -r <release> -v <build_version>"
    fi

    # Check the domain and construct the IMAGE_URL
    if [[ "$IMAGE_BASE_URL" == *"files-rs.edgeorchestration.intel.com"* ]]; then
        IMAGE_URL="${IMAGE_BASE_URL}/edge-readonly-${IMG_VER}.${IMAGE_BUILD}-signed.raw.gz"
    elif [[ "$IMAGE_BASE_URL" == *"af01p-png.devtools.intel.com"* ]]; then
        IMAGE_URL="${IMAGE_BASE_URL}/${IMG_VER}/${IMAGE_BUILD}/edge-readonly-${IMG_VER}.${IMAGE_BUILD}-signed.raw.gz"
    else
        error_exit "Unsupported domain in URL: $IMAGE_BASE_URL"
    fi

    echo "Constructed IMAGE URL: $IMAGE_URL"
    # Download the Microvisor image
    IMAGE_PATH="$TEMP_DIR/edge_microvisor_toolkit.raw.gz"
    echo "Downloading microvisor image from $IMAGE_URL..."
    curl -k "$IMAGE_URL" -o "$IMAGE_PATH" || error_exit "Failed to download microvisor image"

    # Construct the SHA URL
    SHA_URL="${IMAGE_URL}.sha256sum"

    # Download the SHA256 checksum file
    SHA_FILE="$TEMP_DIR/edge_microvisor_readonly.sha256sum"
    echo "Downloading SHA256 checksum from $SHA_URL..."
    curl -k "$SHA_URL" -o "$SHA_FILE" || error_exit "Failed to download SHA256 checksum"

    # Extract the SHA256 checksum
    SHA_ID=$(awk '{print $1}' "$SHA_FILE")
    echo "Extracted SHA256 checksum: $SHA_ID"

else
    # Direct path mode
    if [ -z "$IMAGE_PATH" ] || [ -z "$SHA_FILE" ]; then
        # Example usage: ./os-update.sh  -i /path/to/microvisor_image.raw.gz -c /path/to/microvisor_image.sha256sum
        error_exit "Usage: $0 -i <Direct_path_to_Microvisor_image> -c <Checksum_file>"
    fi

    # Verify that the image file exists
    if [ ! -f "$IMAGE_PATH" ]; then
        error_exit "Microvisor image file not found at $IMAGE_PATH"
    fi

    # Verify that the SHA file exists
    if [ ! -f "$SHA_FILE" ]; then
        error_exit "SHA256 checksum file not found at $SHA_FILE"
    fi

    # Extract the SHA256 checksum
    SHA_ID=$(awk '{print $1}' "$SHA_FILE")
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

INSTALLER_CFG="/etc/cloud/cloud.cfg.d/installer.cfg"

# Define paths
TMP_DIR="/etc/cloud"
COMMIT_UPDATE_SCRIPT="$TMP_DIR/commit_update.sh"
INSTALLER_CFG="/etc/cloud/cloud.cfg.d/installer.cfg"

cp /etc/passwd /etc/cloud/passwd_backup
cp /etc/shadow /etc/cloud/shadow_backup
cp /etc/group /etc/cloud/group_backup

# Extract paths under write_files and store them in a list
paths_list=$(extract_write_files_paths "$config_file")
mkdir -p /etc/cloud/backup
paths_file="/etc/cloud/backup/paths_list.txt"

# Print the list of paths
echo "Paths under write_files in $config_file:"
for path in $paths_list; do
  cp -rf "$path" "/etc/cloud/backup/"
done

# Save paths to a file
echo "$paths_list" > "$paths_file"

# Create commit_update.sh only if it doesn't already exist
if [ ! -f "$COMMIT_UPDATE_SCRIPT" ]; then
    cat << 'EOF' > "$COMMIT_UPDATE_SCRIPT"
#!/bin/bash

if [ -e /etc/cloud/passwd_backup ] && [ -e /etc/cloud/shadow_backup ]; then
  cp /etc/cloud/passwd_backup /etc/passwd
  cp /etc/cloud/shadow_backup /etc/shadow
  cp /etc/cloud/group_backup /etc/group
  # Read paths from the file
  paths_list=$(cat "/etc/cloud/backup/paths_list.txt")
  for file_path in $paths_list; do
    name=$(basename "$file_path")
    if [ "$name" = "paths_list.txt" ]; then
      continue
    else
      mv "/etc/cloud/backup/$name" "$file_path"
    fi
  done
  rm -rf /etc/cloud/backup
fi

# Add user
CONFIG_FILE="/etc/cloud/config-file"
user_name=$(grep '^user_name=' "$CONFIG_FILE" | cut -d '=' -f2)
user_name=${user_name//\"/}
usermod -aG sudo "$user_name"

bootctl_output=$(bootctl list)
# Check if linux-2.efi or linux.efi is selected
# Make the updated image persistent for future boots
if [ "$(cat "/etc/cloud/upgrade_status" 2>/dev/null)" == "true" ]; then
  if os-update-tool.sh -c; then
     echo "Commit update successful."
  else
     echo "Failed to commit update."
     exit 1
  fi
fi

# After the commit, resetting the upgrade status
sudo tee /etc/cloud/upgrade_status <<<'false'

# Fetch and echo IMAGE_BUILD_DATE from /etc/image-id
IMAGE_BUILD_DATE=$(grep '^IMAGE_BUILD_DATE=' /etc/image-id | cut -d '=' -f2)
echo "IMAGE_BUILD_DATE: $IMAGE_BUILD_DATE"
EOF

    # Ensure the new script is executable
    chmod +x "$COMMIT_UPDATE_SCRIPT"
fi

# Check if installer.cfg exists and update it if necessary
if [ -f "$INSTALLER_CFG" ]; then
    # Check if the commit_update.sh entry is already present
    if ! grep -q "bash $COMMIT_UPDATE_SCRIPT" "$INSTALLER_CFG"; then
        # Use awk to find the end of the runcmd block and append new content
        awk -v script="$COMMIT_UPDATE_SCRIPT" '
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

        ' "$INSTALLER_CFG" > "${INSTALLER_CFG}.tmp" && mv "${INSTALLER_CFG}.tmp" "$INSTALLER_CFG"
    else
        echo "Entry for commit_update.sh already exists in installer.cfg."
    fi
else
    echo "Error: installer.cfg not found."
    exit 1
fi

bootctl install

# Reboot the system
echo "Rebooting the system..."
check_success "Rebooting the system"
sudo tee /etc/cloud/upgrade_status <<<'true'
sleep 5s
reboot
