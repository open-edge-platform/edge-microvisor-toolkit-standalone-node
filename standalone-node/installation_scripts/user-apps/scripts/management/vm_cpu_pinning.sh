#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# filepath: vm_cpu_pinning.sh

# Advanced QEMU vCPU Thread Management Script for KubeVirt VMs
# Supports dual VM monitoring with automatic re-pinning on restart

usage() {
    echo "Usage: $0 [COMMAND] --vm1 <vm_name1> --cpu1 <cpu_list1> [--vm2 <vm_name2>] [--cpu2 <cpu_list2>] [--namespace <namespace>] [--watch <interval>] [--daemon]"
    echo ""
    echo "Commands:"
    echo "  start       Start CPU pinning (default)"
    echo "  stop        Stop daemon"
    echo "  restart     Restart daemon"
    echo "  status      Show daemon status"
    echo "  check       Show VM status without changing CPU affinity"
    echo ""
    echo "Required arguments:"
    echo "  --vm1 <name>        First VM name (use ub22-vm or emtd-vm)"
    echo "  --cpu1 <list>       CPU list for VM1 (e.g., 0-3 or 0,2,4,6)"
    echo ""
    echo "Optional arguments:"
    echo "  --vm2 <name>        Second VM name (enables dual VM mode)"
    echo "  --cpu2 <list>       CPU list for VM2 (required if --vm2 is specified)"
    echo "  --namespace <ns>    Kubernetes namespace (default: search all user namespaces)"
    echo "  --watch <seconds>   Watch interval in seconds (default: 30, 0 = run once)"
    echo "  --daemon            Run in daemon mode (background, no terminal output)"
    echo ""
    echo "Examples:"
    echo "  # Start CPU pinning for single VM"
    echo "  $0 start --vm1 win11-vm1 --cpu1 0-3"
    echo ""
    echo "  # Start daemon for dual VM monitoring (use --vm1 ub22-vm or emtd-vm, --vm2 win11-vm)"
    echo "  $0 start --vm1 ub22-vm --cpu1 0-3 --vm2 win11-vm --cpu2 4-7 --watch 60 --daemon"
    echo "  $0 start --vm1 emtd-vm --cpu1 0-3 --vm2 win11-vm --cpu2 4-7 --watch 60 --daemon"
    echo ""
    echo "  # Check daemon status"
    echo "  $0 status --vm1 ub22-vm --vm2 win11-vm"
    echo ""
    echo "  # Stop daemon"
    echo "  $0 stop --vm1 ub22-vm --vm2 win11-vm"
    echo ""
    echo "  # Restart daemon"
    echo "  $0 restart --vm1 ub22-vm --cpu1 0-3 --vm2 win11-vm --cpu2 4-7 --watch 60"
    echo ""
    echo "  # Check VM status without changing affinity"
    echo "  $0 check --vm1 test-vm --namespace user-apps"
    exit 1
}

# Global variables for tracking VM state
declare -A VM_PIDS
declare -A VM_THREAD_COUNTS

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$DAEMON_MODE" != "true" ]; then
        echo "[$timestamp] [$level] $message"
    fi
    
    # Always log to syslog if available
    if command -v logger >/dev/null 2>&1; then
        logger -t "vcpu-pinning" "[$level] $message"
    fi
}

# Function to expand CPU range/list into individual CPUs
expand_cpu_list() {
    local cpu_input="$1"
    local cpu_array=()
    
    if [[ "$cpu_input" =~ ^[0-9]+-[0-9]+$ ]]; then
        local start=${cpu_input%-*}
        local end=${cpu_input#*-}
        for ((i=start; i<=end; i++)); do
            cpu_array+=("$i")
        done
    elif [[ "$cpu_input" =~ ^[0-9,]+$ ]]; then
        IFS=',' read -ra cpu_array <<< "$cpu_input"
    else
        log_message "ERROR" "Invalid CPU format: $cpu_input. Use '0-3' or '0,1,2,3'"
        return 1
    fi
    
    echo "${cpu_array[@]}"
}

# Function to validate CPU list
validate_cpu_list() {
    local cpu_list="$1"
    local max_cpu
    max_cpu=$(nproc --all)
    max_cpu=$((max_cpu - 1))
    
    local cpu_array
    if ! mapfile -t cpu_array < <(expand_cpu_list "$cpu_list"); then
        return 1
    fi
    
    for cpu in "${cpu_array[@]}"; do
        if [ "$cpu" -gt "$max_cpu" ]; then
            log_message "ERROR" "CPU $cpu exceeds maximum available CPU $max_cpu"
            return 1
        fi
    done
    
    return 0
}

# Function to find VM across namespaces and return PID and namespace
find_vm_pid() {
    local vm_name="$1"
    local target_namespace="$2"
    
    # Get all namespaces or use specified one
    local namespaces
    if [ -n "$target_namespace" ]; then
        namespaces="$target_namespace"
    else
        # Get all namespaces, excluding system ones
        namespaces=$(/var/lib/rancher/k3s/bin/k3s kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -v -E '^(kube-system|kube-public|kube-node-lease|kubevirt)$' | tr '\n' ' ')
    fi
    
    # Try to find QEMU process in each namespace
    for ns in $namespaces; do        
        # Try primary pattern
        local qemu_pid
        qemu_pid=$(pgrep -f "guest=${ns}_${vm_name}")
        
        # Try alternative patterns if primary fails
        if [ -z "$qemu_pid" ]; then
            qemu_pid=$(pgrep -f "guest=${ns}_${vm_name}-vm") || \
            qemu_pid=$(pgrep -f "guest=${ns}_${vm_name}_vm") || \
            qemu_pid=$(pgrep -f "${ns}_${vm_name}")
        fi
        
        if [ -n "$qemu_pid" ]; then
            # Return PID and namespace separated by space
            echo "$qemu_pid $ns"
            return 0
        fi
    done
    
    return 1
}

# Function to set CPU affinity for a VM
set_vm_cpu_affinity() {
    local vm_name="$1"
    local namespace="$2"
    local cpu_list="$3"
    local is_initial="$4"
    
    # Find the VM and get its PID
    local vm_info
    if ! vm_info=$(find_vm_pid "$vm_name" "$namespace"); then
        log_message "ERROR" "Could not find VM '$vm_name'"
        return 1
    fi
    
    # Extract PID and actual namespace from returned string
    local qemu_pid
    qemu_pid=$(echo "$vm_info" | awk '{print $1}')
    local found_namespace
    found_namespace=$(echo "$vm_info" | awk '{print $2}')
    
    # Check if PID has changed (VM restart detected)
    local pid_changed=false
    if [ -n "${VM_PIDS[$vm_name]}" ] && [ "${VM_PIDS[$vm_name]}" != "$qemu_pid" ]; then
        pid_changed=true
        log_message "INFO" "VM restart detected for '$vm_name': PID changed from ${VM_PIDS[$vm_name]} to $qemu_pid"
    fi
    
    # Update tracking variables
    VM_PIDS[$vm_name]="$qemu_pid"
    
    # Get vCPU thread IDs
    local vcpu_threads
    vcpu_threads=$(ps -L -p "$qemu_pid" -o tid,comm --no-headers | grep -E 'CPU|vcpu' | awk '{print $1}')
    
    if [ -z "$vcpu_threads" ]; then
        log_message "WARN" "No vCPU threads found with 'CPU' pattern for VM '$vm_name'. Using all threads."
        vcpu_threads=$(ps -L -p "$qemu_pid" -o tid --no-headers | tr -d ' ')
    fi
    
    # Convert to array
    local thread_array
    mapfile -t thread_array <<< "$vcpu_threads"
    local thread_count=${#thread_array[@]}
    
    # Track thread count changes
    if [ -n "${VM_THREAD_COUNTS[$vm_name]}" ] && [ "${VM_THREAD_COUNTS[$vm_name]}" != "$thread_count" ]; then
        log_message "INFO" "Thread count changed for VM '$vm_name': ${VM_THREAD_COUNTS[$vm_name]} -> $thread_count"
    fi
    VM_THREAD_COUNTS[$vm_name]="$thread_count"
    
    if [ "$is_initial" = "true" ] || [ "$pid_changed" = "true" ]; then
        log_message "INFO" "VM '$vm_name' found in namespace '$found_namespace' with PID: $qemu_pid (threads: $thread_count)"
    fi
    
    # Expand CPU list into array
    local cpu_array
    mapfile -t cpu_array < <(expand_cpu_list "$cpu_list")
    local cpu_count=${#cpu_array[@]}
    
    if [ "$cpu_count" -lt "$thread_count" ]; then
        log_message "WARN" "More threads ($thread_count) than available CPUs ($cpu_count) for VM '$vm_name'. Some CPUs will be assigned to multiple threads."
    fi
    
    # Assign each thread to a specific CPU
    local success=0
    local failed_threads=()
    
    for i in "${!thread_array[@]}"; do
        local tid="${thread_array[i]}"
        local cpu_index=$((i % cpu_count))
        local assigned_cpu="${cpu_array[cpu_index]}"
        
        if taskset -cp "$assigned_cpu" "$tid" >/dev/null 2>&1; then
            success=$((success + 1))
        else
            failed_threads+=("$tid")
        fi
    done
    
    if [ ${#failed_threads[@]} -gt 0 ]; then
        log_message "ERROR" "Failed to set affinity for ${#failed_threads[@]} threads of VM '$vm_name': ${failed_threads[*]}"
    fi
    
    if [ "$is_initial" = "true" ] || [ "$pid_changed" = "true" ]; then
        log_message "INFO" "CPU affinity set for $success/$thread_count threads of VM '$vm_name' (CPUs: ${cpu_array[*]})"
    fi
    
    return 0
}

# Function to monitor and maintain CPU affinity
monitor_vms() {
    local vm1_name="$1"
    local vm1_cpu_list="$2"
    local vm2_name="$3"
    local vm2_cpu_list="$4"
    local namespace="$5"
    local watch_interval="$6"
    
    log_message "INFO" "Starting VM monitoring service"
    log_message "INFO" "VM1: $vm1_name (CPUs: $vm1_cpu_list) [Use ub22-vm or emtd-vm]"
    if [ -n "$vm2_name" ]; then
        log_message "INFO" "VM2: $vm2_name (CPUs: $vm2_cpu_list) [Windows]"
    fi
    log_message "INFO" "Namespace: ${namespace:-'All user namespaces'}"
    log_message "INFO" "Watch interval: ${watch_interval}s"
    
    # Initial setup
    local vm1_success=false
    local vm2_success=false
    
    # Set initial CPU affinity for VM1
    if set_vm_cpu_affinity "$vm1_name" "$namespace" "$vm1_cpu_list" "true"; then
        vm1_success=true
    fi
    
    # Set initial CPU affinity for VM2 if specified
    if [ -n "$vm2_name" ]; then
        if set_vm_cpu_affinity "$vm2_name" "$namespace" "$vm2_cpu_list" "true"; then
            vm2_success=true
        fi
    else
        vm2_success=true  # No second VM, consider it successful
    fi
    
    # If watch interval is 0, run once and exit
    if [ "$watch_interval" -eq 0 ]; then
        if [ "$vm1_success" = "true" ] && [ "$vm2_success" = "true" ]; then
            log_message "INFO" "Single run completed successfully"
            return 0
        else
            log_message "ERROR" "Single run failed"
            return 1
        fi
    fi
    
    # Continuous monitoring loop
    local iteration=0
    while true; do
        sleep "$watch_interval"
        iteration=$((iteration + 1))
        
        # Check and maintain VM1
        if ! set_vm_cpu_affinity "$vm1_name" "$namespace" "$vm1_cpu_list" "false"; then
            log_message "ERROR" "Failed to maintain CPU affinity for VM '$vm1_name' (iteration: $iteration)"
        fi
        
        # Check and maintain VM2 if specified
        if [ -n "$vm2_name" ]; then
            if ! set_vm_cpu_affinity "$vm2_name" "$namespace" "$vm2_cpu_list" "false"; then
                log_message "ERROR" "Failed to maintain CPU affinity for VM '$vm2_name' (iteration: $iteration)"
            fi
        fi
        
        # Log periodic status (every 10 iterations)
        if [ $((iteration % 10)) -eq 0 ]; then
            log_message "INFO" "Monitoring active - iteration: $iteration"
        fi
    done
}

# Function to show current VM status
show_vm_status() {
    local vm_name="$1"
    local namespace="$2"
    
    echo "============================================"
    echo "VM Status: $vm_name"
    echo "============================================"
    
    local vm_info
    if ! vm_info=$(find_vm_pid "$vm_name" "$namespace"); then
        echo "Status: NOT FOUND"
        echo "Searched namespace: ${namespace:-'All user namespaces'}"
        echo ""
        echo "Available QEMU processes:"
        local qemu_procs
        qemu_procs=$(pgrep -fa qemu | grep 'guest=' | grep -o 'guest=[^[:space:]]*' | sort -u)
        if [ -n "$qemu_procs" ]; then
            echo "$qemu_procs"
        else
            echo "  No QEMU processes found"
        fi
        echo ""
        return 1
    fi
    
    local qemu_pid
    qemu_pid=$(echo "$vm_info" | awk '{print $1}')
    local found_namespace
    found_namespace=$(echo "$vm_info" | awk '{print $2}')
    
    echo "Status: RUNNING"
    echo "PID: $qemu_pid"
    echo "Namespace: $found_namespace"
    
    # Get vCPU thread IDs
    local vcpu_threads
    vcpu_threads=$(ps -L -p "$qemu_pid" -o tid,comm --no-headers 2>/dev/null | grep -E 'CPU|vcpu' | awk '{print $1}')
    
    if [ -z "$vcpu_threads" ]; then
        echo "Warning: No vCPU threads found with 'CPU' pattern. Using all threads."
        vcpu_threads=$(ps -L -p "$qemu_pid" -o tid --no-headers 2>/dev/null | tr -d ' ')
    fi
    
    local thread_array
    mapfile -t thread_array <<< "$vcpu_threads"
    local thread_count=${#thread_array[@]}
    
    echo "vCPU Threads: $thread_count"
    
    if [ "$thread_count" -gt 0 ]; then
        echo "Current CPU assignments:"
        echo "TID        CPU Core    Thread Name"
        echo "--------------------------------"
        for tid in "${thread_array[@]}"; do
            local thread_info
            thread_info=$(ps -L -p "$qemu_pid" -o tid,psr,comm --no-headers 2>/dev/null | grep "^[[:space:]]*$tid")
            if [ -n "$thread_info" ]; then
                echo "$thread_info"
            else
                echo "  $tid   (thread info unavailable)"
            fi
        done
    else
        echo "No threads found for this process"
    fi
    echo
}

# Signal handlers for graceful shutdown
cleanup() {
    log_message "INFO" "Received shutdown signal, cleaning up..."
    exit 0
}

# Set signal handlers
trap cleanup SIGTERM SIGINT

# Function to check daemon status
check_daemon_status() {
    local vm1_name="$1"
    local vm2_name="$2"
    
    local pid_file="/var/run/vcpu-pinning-${vm1_name}"
    if [ -n "$vm2_name" ]; then
        pid_file="${pid_file}-${vm2_name}"
    fi
    pid_file="${pid_file}.pid"
    
    if [ ! -f "$pid_file" ]; then
        echo "Daemon is not running (no PID file found)"
        return 1
    fi
    
    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    if [ -z "$pid" ]; then
        echo "Invalid PID file"
        return 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        echo "Daemon is running (PID: $pid)"
        echo "PID file: $pid_file"
        
        # Show process info
        echo "Process info:"
        ps -p "$pid" -o pid,ppid,cmd,etime,pcpu,pmem --no-headers 2>/dev/null || echo "  Process details unavailable"
        
        # Show recent log entries
        echo ""
        echo "Recent log entries:"
        if command -v journalctl >/dev/null 2>&1; then
            journalctl -t "vcpu-pinning" --since "5 minutes ago" --no-pager -n 10 2>/dev/null || echo "  No recent log entries"
        else
            tail -n 10 /var/log/syslog 2>/dev/null | grep "vcpu-pinning" || echo "  No recent log entries"
        fi
        
        return 0
    else
        echo "Daemon is not running (stale PID file)"
        rm -f "$pid_file"
        return 1
    fi
}

# Function to stop daemon
stop_daemon() {
    local vm1_name="$1"
    local vm2_name="$2"
    
    local pid_file="/var/run/vcpu-pinning-${vm1_name}"
    if [ -n "$vm2_name" ]; then
        pid_file="${pid_file}-${vm2_name}"
    fi
    pid_file="${pid_file}.pid"
    
    if [ ! -f "$pid_file" ]; then
        echo "Daemon is not running (no PID file found)"
        return 1
    fi
    
    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    if [ -z "$pid" ]; then
        echo "Invalid PID file"
        rm -f "$pid_file"
        return 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        echo "Stopping daemon (PID: $pid)..."
        
        # Try graceful shutdown first
        if kill -TERM "$pid" 2>/dev/null; then
            # Wait up to 10 seconds for graceful shutdown
            local count=0
            while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
                sleep 1
                count=$((count + 1))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                echo "Graceful shutdown failed, forcing termination..."
                kill -KILL "$pid" 2>/dev/null
            fi
        fi
        
        # Clean up PID file
        rm -f "$pid_file"
        
        if kill -0 "$pid" 2>/dev/null; then
            echo "Failed to stop daemon"
            return 1
        else
            echo "Daemon stopped successfully"
            return 0
        fi
    else
        echo "Daemon is not running (removing stale PID file)"
        rm -f "$pid_file"
        return 1
    fi
}

# Function to restart daemon
restart_daemon() {
    local vm1_name="$1"
    local vm1_cpu_list="$2"
    local vm2_name="$3"
    local vm2_cpu_list="$4"
    local namespace="$5"
    local watch_interval="$6"
    
    echo "Restarting daemon..."
    
    # Stop existing daemon
    stop_daemon "$vm1_name" "$vm2_name"
    
    # Wait a moment
    sleep 2
    
    # Start new daemon
    echo "Starting daemon..."
    
    # Build command arguments
    local cmd_args="start --vm1 $vm1_name --cpu1 $vm1_cpu_list"
    if [ -n "$vm2_name" ]; then
        cmd_args="$cmd_args --vm2 $vm2_name --cpu2 $vm2_cpu_list"
    fi
    if [ -n "$namespace" ]; then
        cmd_args="$cmd_args --namespace $namespace"
    fi
    cmd_args="$cmd_args --watch $watch_interval --daemon"
    
    # Start daemon
    "$0" "$cmd_args" &
    
    # Wait to ensure it started
    sleep 3
    
    # Check if it's running
    if check_daemon_status "$vm1_name" "$vm2_name"; then
        echo "Daemon restarted successfully"
        return 0
    else
        echo "Failed to restart daemon"
        return 1
    fi
}

# Parse command line arguments
parse_arguments() {
    # Set default command
    COMMAND="start"
    
    # Check if first argument is a command
    if [ $# -gt 0 ]; then
        case $1 in
            start|stop|restart|status|check)
                COMMAND="$1"
                shift
                ;;
        esac
    fi
    
    VM1_NAME=""
    VM1_CPU_LIST=""
    VM2_NAME=""
    VM2_CPU_LIST=""
    NAMESPACE=""
    WATCH_INTERVAL=30
    DAEMON_MODE=false
    SHOW_STATUS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vm1)
                VM1_NAME="$2"
                shift 2
                ;;
            --cpu1)
                VM1_CPU_LIST="$2"
                shift 2
                ;;
            --vm2)
                VM2_NAME="$2"
                shift 2
                ;;
            --cpu2)
                VM2_CPU_LIST="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --watch)
                WATCH_INTERVAL="$2"
                shift 2
                ;;
            --daemon)
                DAEMON_MODE=true
                shift
                ;;
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Validate required arguments based on command
    if [ -z "$VM1_NAME" ]; then
        echo "Error: --vm1 is required"
        usage
    fi
    
    if [ "$COMMAND" != "stop" ] && [ "$COMMAND" != "status" ] && [ "$COMMAND" != "check" ]; then
        if [ -z "$VM1_CPU_LIST" ]; then
            echo "Error: --cpu1 is required for command '$COMMAND'"
            usage
        fi
        
        if [ -n "$VM2_NAME" ] && [ -z "$VM2_CPU_LIST" ]; then
            echo "Error: --cpu2 is required when --vm2 is specified"
            usage
        fi
        
        if [ -n "$VM2_CPU_LIST" ] && [ -z "$VM2_NAME" ]; then
            echo "Error: --vm2 is required when --cpu2 is specified"
            usage
        fi
    fi
    
    # Handle legacy --status flag
    if [ "$SHOW_STATUS" = "true" ]; then
        COMMAND="check"
    fi
    
    # Validate watch interval
    if ! [[ "$WATCH_INTERVAL" =~ ^[0-9]+$ ]]; then
        echo "Error: --watch must be a number"
        usage
    fi
    
    # Validate CPU lists
    if [ -n "$VM1_CPU_LIST" ] && ! validate_cpu_list "$VM1_CPU_LIST"; then
        echo "Error: Invalid CPU list for --cpu1: $VM1_CPU_LIST"
        exit 1
    fi
    
    if [ -n "$VM2_CPU_LIST" ] && ! validate_cpu_list "$VM2_CPU_LIST"; then
        echo "Error: Invalid CPU list for --cpu2: $VM2_CPU_LIST"
        exit 1
    fi
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Handle different commands
    case "$COMMAND" in
        status)
            check_daemon_status "$VM1_NAME" "$VM2_NAME"
            exit $?
            ;;
        stop)
            if [ "$EUID" -ne 0 ]; then
                echo "Error: This command must be run as root (use sudo)"
                exit 1
            fi
            stop_daemon "$VM1_NAME" "$VM2_NAME"
            exit $?
            ;;
        restart)
            if [ "$EUID" -ne 0 ]; then
                echo "Error: This command must be run as root (use sudo)"
                exit 1
            fi
            restart_daemon "$VM1_NAME" "$VM1_CPU_LIST" "$VM2_NAME" "$VM2_CPU_LIST" "$NAMESPACE" "$WATCH_INTERVAL"
            exit $?
            ;;
        check)
            show_vm_status "$VM1_NAME" "$NAMESPACE"
            if [ -n "$VM2_NAME" ]; then
                show_vm_status "$VM2_NAME" "$NAMESPACE"
            fi
            exit 0
            ;;
        start)
            # Continue with normal execution
            ;;
        *)
            echo "Unknown command: $COMMAND"
            usage
            ;;
    esac
    
    # Check if running as root (only for actual operations)
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Handle daemon mode
    if [ "$DAEMON_MODE" = "true" ]; then
        # Redirect output to avoid terminal attachment
        exec >/dev/null 2>&1
        
        # Create PID file
        local pid_file="/var/run/vcpu-pinning-${VM1_NAME}"
        if [ -n "$VM2_NAME" ]; then
            pid_file="${pid_file}-${VM2_NAME}"
        fi
        pid_file="${pid_file}.pid"
        
        echo $$ > "$pid_file"
        
        # Set process name
        exec -a "vcpu-pinning-daemon" "$0" start --vm1 "$VM1_NAME" --cpu1 "$VM1_CPU_LIST" \
            ${VM2_NAME:+--vm2 "$VM2_NAME"} ${VM2_CPU_LIST:+--cpu2 "$VM2_CPU_LIST"} \
            ${NAMESPACE:+--namespace "$NAMESPACE"} --watch "$WATCH_INTERVAL"
    fi
    
    # Start monitoring
    monitor_vms "$VM1_NAME" "$VM1_CPU_LIST" "$VM2_NAME" "$VM2_CPU_LIST" "$NAMESPACE" "$WATCH_INTERVAL"
}

# Run main function
main "$@"
