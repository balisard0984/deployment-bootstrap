#!/bin/bash

# 
# Based on: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

#=============================================================================
# NVIDIA Container Toolkit Installation Script for Ubuntu (Balisard0984)
# Version: 1.2-inline
# Description: 
# - first relase (v1.0)
# - fixed nvidia container toolkit version : 1.17.8-1 (v1.0)
# - support OS : Ubuntu 20.04, 22.04, 24.04 LTS (v1.0)
# - Sequential execution without function calls (v1.2)
# - non root execution (v1.2)
# - erase : TUI , only CLI (v1.2)
# - erase : experimental option, complex log print, test run with docker process (v1.2)
#=============================================================================

set -euo pipefail

# Constants
readonly SCRIPT_NAME="$(basename "$0")"
readonly NVIDIA_CONTAINER_TOOLKIT_VERSION="1.17.8-1"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Global variables
SKIP_GPU_CHECK=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-gpu-check)
            SKIP_GPU_CHECK=true
            shift
            ;;
        -h|--help)
            echo "Usage: $SCRIPT_NAME [OPTIONS]"
            echo "Options:"
            echo "    --skip-gpu-check    Skip GPU detection check"
            echo "    -h, --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

ask_yes_no() {
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

# Main installation process
echo "=== NVIDIA Container Toolkit Installation ==="
echo

# Step 1: Check Ubuntu system
info "Checking Ubuntu system..."
if ! grep -q "Ubuntu" /etc/os-release; then
    error "This script is only supported on Ubuntu systems."
    exit 1
fi
success "Ubuntu system verified"

# Step 2: Check user privileges
info "Checking user privileges..."
if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root. Required sudo commands are handled within the script."
    exit 1
fi

if ! sudo -n true 2>/dev/null; then
    if ask_yes_no "Sudo privileges are required. Continue?"; then
        sudo -v || exit 1
    else
        exit 1
    fi
fi
success "User privileges verified"

# Step 3: Check NVIDIA GPU (optional)
if ! $SKIP_GPU_CHECK; then
    info "Checking for NVIDIA GPU..."
    if ! lspci | grep -i nvidia > /dev/null; then
        warning "No NVIDIA GPU detected"
        if ! ask_yes_no "No NVIDIA GPU detected. Do you want to continue anyway?"; then
            exit 1
        fi
    else
        success "NVIDIA GPU detected"
    fi
else
    info "Skipping GPU check as requested"
fi

# Step 4: Check NVIDIA driver
info "Checking NVIDIA driver..."
if ! command -v nvidia-smi &> /dev/null; then
    error "NVIDIA driver is not installed."
    error "Please install the driver first: sudo apt update && sudo apt install -y nvidia-driver-535"
    exit 1
fi
success "NVIDIA driver installation verified"

# Step 5: Configure NVIDIA Container Toolkit repository
info "Configuring NVIDIA Container Toolkit repository..."

# Add GPG key
info "Adding NVIDIA GPG key..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# Configure repository
info "Adding repository configuration..."
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

success "Repository configuration completed"

# Step 6: Update package list
info "Updating package list..."
sudo apt-get update
success "Package list update completed"

# Step 7: Install NVIDIA Container Toolkit
info "Installing NVIDIA Container Toolkit..."
export NVIDIA_CONTAINER_TOOLKIT_VERSION
sudo apt-get install -y \
    nvidia-container-toolkit="${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
    nvidia-container-toolkit-base="${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
    libnvidia-container-tools="${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
    libnvidia-container1="${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
success "NVIDIA Container Toolkit installation completed"

# Step 8: Configure container runtimes
info "Configuring container runtimes..."

configured=false

# Configure Docker if available
if command -v docker &> /dev/null; then
    info "Configuring Docker runtime..."
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    success "Docker configuration completed"
    configured=true
fi

# Configure containerd if available
if command -v containerd &> /dev/null; then
    info "Configuring containerd runtime..."
    sudo nvidia-ctk runtime configure --runtime=containerd
    sudo systemctl restart containerd
    success "containerd configuration completed"
    configured=true
fi

# Configure CRI-O if available
if command -v crio &> /dev/null; then
    info "Configuring CRI-O runtime..."
    sudo nvidia-ctk runtime configure --runtime=crio
    sudo systemctl restart crio
    success "CRI-O configuration completed"
    configured=true
fi

if ! $configured; then
    warning "No supported container runtime detected."
    warning "After installing Docker, containerd, or CRI-O, run:"
    warning "sudo nvidia-ctk runtime configure --runtime=<runtime-name>"
fi

# Step 9: Verify installation
info "Verifying installation..."

if command -v nvidia-ctk &> /dev/null; then
    success "nvidia-ctk command available"
    info "Version: $(nvidia-ctk --version)"
else
    error "nvidia-ctk command not found"
    exit 1
fi

# Step 10: Installation complete
echo
success "NVIDIA Container Toolkit installation completed successfully!"
echo
info "It is recommended to reboot the system."

if ask_yes_no "Would you like to reboot the system now?"; then
    sudo reboot
fi

echo "Installation finished. You can now use NVIDIA GPUs in containers."
