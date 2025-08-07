#!/bin/bash

# NVIDIA Container Toolkit Installation Script for Ubuntu (CLI/TUI Version)
# Based on: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

set -euo pipefail

# Constants
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/nvidia-container-toolkit-install.log"
readonly NVIDIA_CONTAINER_TOOLKIT_VERSION="1.17.8-1"
readonly BACKTITLE="NVIDIA Container Toolkit Installer"

# UI Dimensions
readonly HEIGHT=20
readonly WIDTH=70
readonly MENU_HEIGHT=10

# Color codes for log output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Global variables
INSTALL_EXPERIMENTAL=false
SKIP_GPU_CHECK=false
USE_TUI=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ui)
                USE_TUI=true
                shift
                ;;
            #--experimental)
            #    INSTALL_EXPERIMENTAL=true
            #    shift
            #    ;;
            --skip-gpu-check)
                SKIP_GPU_CHECK=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
    --ui                Use TUI (Text User Interface) mode
    --experimental      Enable experimental packages
    --skip-gpu-check    Skip GPU detection check
    -h, --help         Show this help message

Examples:
    $SCRIPT_NAME                    # CLI mode
    $SCRIPT_NAME --ui               # TUI mode
    $SCRIPT_NAME --experimental     # CLI mode with experimental packages

EOF
}

# Check if whiptail is available (only for TUI mode)
check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "whiptail is required for TUI mode but not installed."
        echo "Installing whiptail..."
        sudo apt-get update && sudo apt-get install -y whiptail
    fi
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# CLI helper functions
cli_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

cli_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

cli_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

cli_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cli_yesno() {
    local prompt="$1"
    while true; do
        read -p "$prompt (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# TUI helper functions (only used when USE_TUI=true)
show_info() {
    whiptail --title "Information" --msgbox "$1" $HEIGHT $WIDTH
}

show_success() {
    whiptail --title "Success" --msgbox "$1" $HEIGHT $WIDTH
}

show_warning() {
    whiptail --title "Warning" --msgbox "$1" $HEIGHT $WIDTH
}

show_error() {
    whiptail --title "Error" --msgbox "$1" $HEIGHT $WIDTH
}

show_yesno() {
    whiptail --title "$1" --yesno "$2" $HEIGHT $WIDTH
}

show_gauge() {
    local title="$1"
    local text="$2"
    local percent="$3"
    echo "$percent" | whiptail --title "$title" --gauge "$text" 8 $WIDTH "$percent"
}

# Universal helper functions (works for both CLI and TUI)
display_info() {
    if $USE_TUI; then
        show_info "$1"
    else
        cli_info "$1"
    fi
}

display_success() {
    if $USE_TUI; then
        show_success "$1"
    else
        cli_success "$1"
    fi
}

display_warning() {
    if $USE_TUI; then
        show_warning "$1"
    else
        cli_warning "$1"
    fi
}

display_error() {
    if $USE_TUI; then
        show_error "$1"
    else
        cli_error "$1"
    fi
}

display_yesno() {
    if $USE_TUI; then
        show_yesno "$1" "$2"
    else
        cli_yesno "$2"
    fi
}

# Progress indicator
run_with_progress() {
    local title="$1"
    local text="$2"
    local command="$3"
    local logfile="/tmp/progress.log"
    
    if $USE_TUI; then
        # TUI progress
        (
            eval "$command" &> "$logfile"
            echo $? > /tmp/exit_code
        ) &
        
        local pid=$!
        local progress=0
        
        while kill -0 $pid 2>/dev/null; do
            progress=$((progress + 10))
            if [ $progress -gt 90 ]; then
                progress=90
            fi
            echo "$progress" | whiptail --title "$title" --gauge "$text" 8 $WIDTH 0
            sleep 1
        done
        
        echo "100" | whiptail --title "$title" --gauge "$text" 8 $WIDTH 0
        sleep 1
    else
        # CLI progress
        cli_info "$text"
        eval "$command" &> "$logfile"
        echo $? > /tmp/exit_code
        cli_success "Completed: $text"
    fi
    
    # Check exit code
    local exit_code=$(cat /tmp/exit_code 2>/dev/null || echo 1)
    if [ "$exit_code" -ne 0 ]; then
        if $USE_TUI; then
            show_error "Command failed. Check log: $logfile"
        else
            cli_error "Command failed. Check log: $logfile"
        fi
        return 1
    fi
    
    return 0
}

# Welcome screen (TUI only)
show_welcome() {
    whiptail --title "Welcome" --msgbox \
"NVIDIA Container Toolkit Installer

This script will install and configure the NVIDIA Container Toolkit on your Ubuntu system.

Features:
- System compatibility checks
- Automatic repository configuration
- Container runtime configuration
- Installation verification

Press OK to continue." \
    $HEIGHT $WIDTH
}

# Main menu (TUI only)
show_main_menu() {
    local choice
    choice=$(whiptail --title "Main Menu" --backtitle "$BACKTITLE" --menu \
        "Choose an option:" $HEIGHT $WIDTH $MENU_HEIGHT \
        "1" "Start Installation" \
        "2" "System Check Only" \
        "3" "Configuration Options" \
        "4" "View Log" \
        "5" "Exit" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) start_installation ;;
        2) system_check_only ;;
        3) configuration_menu ;;
        4) view_log ;;
        5) exit 0 ;;
        *) show_main_menu ;;
    esac
}

# Configuration menu (TUI only)
configuration_menu() {
    local options=()
    
    if $INSTALL_EXPERIMENTAL; then
        options+=("1" "Disable Experimental Packages")
    else
        options+=("1" "Enable Experimental Packages") 
    fi
    
    if $SKIP_GPU_CHECK; then
        options+=("2" "Enable GPU Check")
    else
        options+=("2" "Skip GPU Check")
    fi
    
    options+=("3" "Back to Main Menu")
    
    local choice
    choice=$(whiptail --title "Configuration" --backtitle "$BACKTITLE" --menu \
        "Configuration Options:" $HEIGHT $WIDTH $MENU_HEIGHT \
        "${options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) 
            INSTALL_EXPERIMENTAL=$(! $INSTALL_EXPERIMENTAL)
            configuration_menu
            ;;
        2)
            SKIP_GPU_CHECK=$(! $SKIP_GPU_CHECK)
            configuration_menu
            ;;
        3) show_main_menu ;;
        *) configuration_menu ;;
    esac
}

# View log (TUI only)
view_log() {
    if [ -f "$LOG_FILE" ]; then
        whiptail --title "Installation Log" --textbox "$LOG_FILE" $HEIGHT $WIDTH
    else
        show_info "Log file not found: $LOG_FILE"
    fi
    show_main_menu
}

# CLI configuration menu
cli_configuration_menu() {
    echo
    echo "=== Configuration Options ==="
    echo "1. Experimental packages: $(if $INSTALL_EXPERIMENTAL; then echo "Enabled"; else echo "Disabled"; fi)"
    echo "2. GPU check: $(if $SKIP_GPU_CHECK; then echo "Disabled"; else echo "Enabled"; fi)"
    echo
    
    if cli_yesno "Do you want to change any configuration options?"; then
        if cli_yesno "Enable experimental packages?"; then
            INSTALL_EXPERIMENTAL=true
        else
            INSTALL_EXPERIMENTAL=false
        fi
        
        if cli_yesno "Skip GPU check?"; then
            SKIP_GPU_CHECK=true
        else
            SKIP_GPU_CHECK=false
        fi
    fi
}

# System validation functions
check_ubuntu() {
    log_info "Checking Ubuntu system..."
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "This script is only supported on Ubuntu systems."
        display_error "This script is only supported on Ubuntu systems."
        return 1
    fi
    log_success "Ubuntu system verified"
    return 0
}

check_root_privileges() {
    log_info "Checking user privileges..."
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run this script as root."
        display_error "Do not run this script as root. Required sudo commands are handled within the script."
        return 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        if display_yesno "Sudo Required" "Sudo privileges are required. Continue?"; then
            sudo -v || return 1
        else
            return 1
        fi
    fi
    log_success "User privileges verified"
    return 0
}

check_nvidia_gpu() {
    if $SKIP_GPU_CHECK; then
        log_info "Skipping GPU check as requested"
        return 0
    fi
    
    log_info "Checking for NVIDIA GPU..."
    if ! lspci | grep -i nvidia > /dev/null; then
        log_warning "No NVIDIA GPU detected"
        if display_yesno "No GPU Detected" "No NVIDIA GPU detected. Do you want to continue anyway?"; then
            return 0
        else
            return 1
        fi
    else
        log_success "NVIDIA GPU detected"
        return 0
    fi
}

check_nvidia_driver() {
    log_info "Checking NVIDIA driver..."
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "NVIDIA driver is not installed."
        display_error "NVIDIA driver is not installed.\n\nPlease install the driver first:\nsudo apt update && sudo apt install -y nvidia-driver-535"
        return 1
    fi
    log_success "NVIDIA driver installation verified"
    return 0
}

# System check
system_check_only() {
    local results=""
    local all_passed=true
    
    if $USE_TUI; then
        echo "10" | whiptail --title "System Check" --gauge "Checking Ubuntu..." 8 $WIDTH 0
    else
        echo "=== System Check ==="
    fi
    
    if check_ubuntu; then
        results+="✓ Ubuntu system: OK\n"
    else
        results+="✗ Ubuntu system: FAILED\n"
        all_passed=false
    fi
    
    if $USE_TUI; then
        echo "30" | whiptail --title "System Check" --gauge "Checking privileges..." 8 $WIDTH 0
    fi
    
    if check_root_privileges; then
        results+="✓ User privileges: OK\n"
    else
        results+="✗ User privileges: FAILED\n"
        all_passed=false
    fi
    
    if $USE_TUI; then
        echo "60" | whiptail --title "System Check" --gauge "Checking GPU..." 8 $WIDTH 0
    fi
    
    if check_nvidia_gpu; then
        results+="✓ NVIDIA GPU: OK\n"
    else
        results+="✗ NVIDIA GPU: FAILED\n"
        all_passed=false
    fi
    
    if $USE_TUI; then
        echo "90" | whiptail --title "System Check" --gauge "Checking driver..." 8 $WIDTH 0
    fi
    
    if check_nvidia_driver; then
        results+="✓ NVIDIA driver: OK\n"
    else
        results+="✗ NVIDIA driver: FAILED\n"
        all_passed=false
    fi
    
    if $USE_TUI; then
        echo "100" | whiptail --title "System Check" --gauge "Check complete" 8 $WIDTH 0
        sleep 1
        whiptail --title "System Check Results" --msgbox "$results" $HEIGHT $WIDTH
        show_main_menu
    else
        echo -e "\n=== System Check Results ==="
        echo -e "$results"
        if $all_passed; then
            cli_success "All system checks passed!"
        else
            cli_error "Some system checks failed. Please resolve the issues before installation."
        fi
    fi
}

# Repository configuration
configure_nvidia_repository() {
    log_info "Configuring NVIDIA Container Toolkit repository..."
    
    # Add GPG key
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    # Configure repository
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    
    # Enable experimental if requested
    if $INSTALL_EXPERIMENTAL; then
        log_info "Enabling experimental package repository..."
        sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list
        log_success "Experimental package repository enabled"
    fi
    
    log_success "Repository configuration completed"
}

# Package installation
update_package_list() {
    log_info "Updating package list..."
    sudo apt-get update
    log_success "Package list update completed"
}

install_nvidia_container_toolkit() {
    log_info "Installing NVIDIA Container Toolkit..."
    
    export NVIDIA_CONTAINER_TOOLKIT_VERSION
    sudo apt-get install -y \
        nvidia-container-toolkit="${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
        nvidia-container-toolkit-base="${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
        libnvidia-container-tools="${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
        libnvidia-container1="${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
    
    log_success "NVIDIA Container Toolkit installation completed"
}

# Container runtime configuration
configure_docker() {
    if command -v docker &> /dev/null; then
        log_info "Configuring Docker runtime..."
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
        log_success "Docker configuration completed"
        return 0
    fi
    return 1
}

configure_containerd() {
    if command -v containerd &> /dev/null; then
        log_info "Configuring containerd runtime..."
        sudo nvidia-ctk runtime configure --runtime=containerd
        sudo systemctl restart containerd
        log_success "containerd configuration completed"
        return 0
    fi
    return 1
}

configure_crio() {
    if command -v crio &> /dev/null; then
        log_info "Configuring CRI-O runtime..."
        sudo nvidia-ctk runtime configure --runtime=crio
        sudo systemctl restart crio
        log_success "CRI-O configuration completed"
        return 0
    fi
    return 1
}

configure_container_runtimes() {
    log_info "Configuring container runtimes..."
    
    local configured=false
    local results=""
    
    if configure_docker; then
        configured=true
        results+="✓ Docker configured\n"
    fi
    
    if configure_containerd; then
        configured=true
        results+="✓ containerd configured\n"
    fi
    
    if configure_crio; then
        configured=true
        results+="✓ CRI-O configured\n"
    fi
    
    if ! $configured; then
        log_warning "No supported container runtime detected."
        results="⚠ No supported container runtime detected.\n\nAfter installing Docker, containerd, or CRI-O, run:\nsudo nvidia-ctk runtime configure --runtime=<runtime-name>"
        display_warning "$results"
    else
        if $USE_TUI; then
            show_info "$results"
        else
            echo -e "$results"
        fi
    fi
}

# Verification
verify_installation() {
    log_info "Verifying installation..."
    local results=""
    
    if command -v nvidia-ctk &> /dev/null; then
        log_success "nvidia-ctk command available"
        results+="✓ nvidia-ctk: Available\n"
        results+="Version: $(nvidia-ctk --version)\n\n"
    else
        log_error "nvidia-ctk command not found"
        results+="✗ nvidia-ctk: Not found\n"
        display_error "$results"
        return 1
    fi
    
    if command -v docker &> /dev/null; then
        log_info "Running Docker test..."
        
        local test_images=(
            "nvidia/cuda:12.2-base-ubuntu22.04"
            "nvidia/cuda:11.8-base-ubuntu22.04"
            "nvidia/cuda:12.1-base-ubuntu20.04"
            "nvidia/cuda:11.8-base-ubuntu20.04"
        )
        
        local test_success=false
        for image in "${test_images[@]}"; do
            log_info "Testing with image: $image"
            if timeout 30 sudo docker run --rm --gpus all "$image" nvidia-smi &>/dev/null; then
                log_success "Docker GPU access test successful with $image"
                results+="✓ Docker GPU Test: PASSED ($image)\n"
                test_success=true
                break
            else
                log_warning "Test failed with $image"
            fi
        done
        
        if ! $test_success; then
            log_warning "Docker GPU access test failed"
            results+="⚠ Docker GPU Test: FAILED\n"
            results+="Manual test: sudo docker run --rm --gpus all nvidia/cuda:<tag> nvidia-smi\n"
        fi
    else
        results+="⚠ Docker not installed - Cannot test GPU access\n"
    fi
    
    if $USE_TUI; then
        whiptail --title "Installation Verification" --msgbox "$results" $HEIGHT $WIDTH
    else
        echo -e "\n=== Installation Verification ==="
        echo -e "$results"
    fi
}

# CLI installation process
cli_installation() {
    echo "=== NVIDIA Container Toolkit Installation ==="
    echo
    
    # Configuration
    cli_configuration_menu
    
    # System checks
    echo
    echo "=== Step 1: System Checks ==="
    if ! check_ubuntu || ! check_root_privileges || ! check_nvidia_gpu || ! check_nvidia_driver; then
        cli_error "System check failed. Please resolve the issues and try again."
        return 1
    fi
    
    # Repository configuration
    echo
    echo "=== Step 2: Repository Configuration ==="
    if ! run_with_progress "Repository Setup" "Configuring NVIDIA repository..." "configure_nvidia_repository"; then
        return 1
    fi
    
    # Package list update
    echo
    echo "=== Step 3: Package Update ==="
    if ! run_with_progress "Package Update" "Updating package list..." "update_package_list"; then
        return 1
    fi
    
    # Install toolkit
    echo
    echo "=== Step 4: Package Installation ==="
    if ! run_with_progress "Package Installation" "Installing NVIDIA Container Toolkit..." "install_nvidia_container_toolkit"; then
        return 1
    fi
    
    # Configure runtimes
    echo
    echo "=== Step 5: Runtime Configuration ==="
    configure_container_runtimes
    
    # Verify installation
    echo
    echo "=== Step 6: Verification ==="
    verify_installation
    
    # Complete
    echo
    cli_success "NVIDIA Container Toolkit installation completed successfully!"
    echo
    cli_info "It is recommended to reboot the system."
    
    if cli_yesno "Would you like to reboot the system now?"; then
        sudo reboot
    fi
}

# TUI installation process
start_installation() {
    local step=0
    local total_steps=7
    
    # Step 1: System checks
    step=$((step + 1))
    echo "$((step * 100 / total_steps))" | whiptail --title "Installation Progress" --gauge "Checking system compatibility..." 8 $WIDTH 0
    
    if ! check_ubuntu || ! check_root_privileges || ! check_nvidia_gpu || ! check_nvidia_driver; then
        show_error "System check failed. Please resolve the issues and try again."
        show_main_menu
        return
    fi
    
    # Step 2: Repository configuration
    step=$((step + 1))
    echo "$((step * 100 / total_steps))" | whiptail --title "Installation Progress" --gauge "Configuring repository..." 8 $WIDTH 0
    
    if ! run_with_progress "Repository Setup" "Configuring NVIDIA repository..." "configure_nvidia_repository"; then
        show_main_menu
        return
    fi
    
    # Step 3: Package list update
    step=$((step + 1))
    echo "$((step * 100 / total_steps))" | whiptail --title "Installation Progress" --gauge "Updating package list..." 8 $WIDTH 0
    
    if ! run_with_progress "Package Update" "Updating package list..." "update_package_list"; then
        show_main_menu
        return
    fi
    
    # Step 4: Install toolkit
    step=$((step + 1))
    echo "$((step * 100 / total_steps))" | whiptail --title "Installation Progress" --gauge "Installing NVIDIA Container Toolkit..." 8 $WIDTH 0
    
    if ! run_with_progress "Package Installation" "Installing NVIDIA Container Toolkit..." "install_nvidia_container_toolkit"; then
        show_main_menu
        return
    fi
    
    # Step 5: Configure runtimes
    step=$((step + 1))
    echo "$((step * 100 / total_steps))" | whiptail --title "Installation Progress" --gauge "Configuring container runtimes..." 8 $WIDTH 0
    configure_container_runtimes
    
    # Step 6: Verify installation
    step=$((step + 1))
    echo "$((step * 100 / total_steps))" | whiptail --title "Installation Progress" --gauge "Verifying installation..." 8 $WIDTH 0
    verify_installation
    
    # Step 7: Complete
    step=$((step + 1))
    echo "$((step * 100 / total_steps))" | whiptail --title "Installation Progress" --gauge "Installation complete!" 8 $WIDTH 0
    sleep 1
    
    show_success "NVIDIA Container Toolkit installation completed successfully!\n\nIt is recommended to reboot the system."
    
    if show_yesno "Reboot System" "Would you like to reboot the system now?"; then
        sudo reboot
    else
        show_main_menu
    fi
}

# Error handling
handle_error() {
    if $USE_TUI; then
        show_error "An unexpected error occurred. Please check the log file: $LOG_FILE"
    else
        cli_error "An unexpected error occurred. Please check the log file: $LOG_FILE"
    fi
    exit 1
}

trap 'handle_error' ERR

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize log
    echo "=== NVIDIA Container Toolkit Installation Started ===" > "$LOG_FILE"
    log_info "$SCRIPT_NAME started with UI mode: $USE_TUI"
    
    if $USE_TUI; then
        # TUI mode requires whiptail
        check_whiptail
        
        # Show welcome screen
        show_welcome
        
        # Start main menu loop
        show_main_menu
    else
        # CLI mode
        echo "NVIDIA Container Toolkit Installer (CLI Mode)"
        echo "Use --ui flag for interactive TUI mode"
        echo
        
        # Ask for system check or direct installation
        if cli_yesno "Do you want to run system check only? (Choose 'n' for full installation)"; then
            system_check_only
        else
            cli_installation
        fi
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi