#!/bin/bash

#=============================================================================
# NVIDIA Driver Install Script for Ubuntu (by Balisard0984)
# Version: 1.4
# Description: 
# - Installs NVIDIA drivers for Ubuntu 
# - Detects environment (desktop/server) and installs appropriate driver
# - fixed install driver version to 535
# - added nvidia-driver-assistant for better GPU detection
# - removed blacklist entries for NVIDIA drivers
# - added automatic nvidia module loading and verification
# - added reboot confirmation dialog
# - modified nvidia-driver-assistant installation (v1.4)
# - check the nvidia-smi command and add nvidia module loading (v1.4)
# - after installation, ask for reboot (v1.4)
#=============================================================================


set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

cleanup() {
    if [[ -f cuda-keyring_1.1-1_all.deb ]]; then
        rm -f cuda-keyring_1.1-1_all.deb
        log "Cleaned up cuda-keyring package file"
    fi
}

detect_environment() {
    # Detect GPU model to determine environment type
    log "Detecting GPU model..."
    
    # Try to get GPU info using lspci
    if command -v lspci &> /dev/null; then
        gpu_info=$(lspci | grep -i "vga\|3d\|display" | grep -i nvidia || true)
        
        if [[ -n "$gpu_info" ]]; then
            log "Found NVIDIA GPU: $gpu_info"
            
            # Check if it's a GeForce series
            if echo "$gpu_info" | grep -qi "geforce"; then
                log "Detected GeForce series GPU"
                echo "desktop"
            else
                log "Detected non-GeForce GPU (likely professional/server series)"
                echo "server"
            fi
        else
            log "No NVIDIA GPU detected via lspci, defaulting to server"
            echo "server"
        fi
    else
        error "lspci command not found. Installing pciutils..."
        apt install -y pciutils
        detect_environment  # Recursive call after installing pciutils
    fi
}

install_nvidia_assistant() {
    log "Installing nvidia-driver-assistant with sudo privileges..."
    
    # Install nvidia-driver-assistant package with sudo
    if ! sudo apt install -y nvidia-driver-assistant; then
        log "Warning: nvidia-driver-assistant not available, trying alternative packages..."
        
        # Try installing ubuntu-drivers-common which provides similar functionality
        if ! sudo apt install -y ubuntu-drivers-common; then
            log "Warning: Could not install GPU detection tools"
            return 1
        fi
    fi
    
    return 0
}

show_nvidia_assistant_info() {
    log "Checking recommended NVIDIA driver using nvidia-driver-assistant..."
    
    # Run nvidia-driver-assistant --distro command
    if command -v nvidia-driver-assistant &> /dev/null; then
        log "Running nvidia-driver-assistant --distro:"
        nvidia-driver-assistant --distro || true
    elif command -v ubuntu-drivers &> /dev/null; then
        log "nvidia-driver-assistant not found, using ubuntu-drivers instead:"
        ubuntu-drivers devices || true
    else
        log "No driver detection tool available, proceeding with default selection"
    fi
    
    echo ""
    log "Above information shows recommended drivers for your system"
    echo ""
}

remove_blacklist() {
    log "Checking and removing NVIDIA driver blacklist if exists..."
    
    blacklist_file="/etc/modprobe.d/nvidia-blacklist.conf"
    
    if [[ -f "$blacklist_file" ]]; then
        log "Found blacklist file: $blacklist_file"
        
        # Create backup before modification
        cp "$blacklist_file" "${blacklist_file}.bak"
        log "Created backup: ${blacklist_file}.bak"
        
        # Comment out all blacklist entries
        sed -i 's/^blacklist /#blacklist /g' "$blacklist_file"
        log "Disabled blacklist entries in $blacklist_file"
        
        # Show the changes
        log "Modified blacklist file contents:"
        cat "$blacklist_file"
    else
        log "No blacklist file found at $blacklist_file"
    fi
    
    # Check for other potential blacklist files
    for file in /etc/modprobe.d/*blacklist*.conf; do
        if [[ -f "$file" ]] && grep -q "nvidia\|nouveau" "$file" 2>/dev/null; then
            log "Found potential NVIDIA-related blacklist in: $file"
            log "You may want to review this file manually"
        fi
    done
}

load_nvidia_module() {
    log "Loading NVIDIA kernel module..."
    
    if sudo modprobe nvidia; then
        log "Successfully loaded NVIDIA kernel module"
    else
        log "Warning: Failed to load NVIDIA kernel module. This may be normal if driver installation requires reboot."
        return 1
    fi
    
    return 0
}

verify_nvidia_installation() {
    log "Verifying NVIDIA driver installation..."
    
    if command -v nvidia-smi &> /dev/null; then
        log "Running nvidia-smi to verify installation..."
        echo "============================================"
        if nvidia-smi; then
            log "NVIDIA driver verification successful!"
            return 0
        else
            log "nvidia-smi command failed. Driver may need system reboot to function properly."
            return 1
        fi
    else
        log "nvidia-smi command not found. Driver installation may be incomplete."
        return 1
    fi
}

ask_reboot() {
    echo ""
    log "NVIDIA driver installation completed!"
    log "=========================================="
    log "It is highly recommended to reboot your system to ensure the new driver is properly loaded."
    log "Some NVIDIA features may not work correctly until after reboot."
    echo ""
    
    read -p "Would you like to reboot now? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Rebooting system in 5 seconds... Press Ctrl+C to cancel."
        sleep 5
        sudo reboot
    else
        log "Reboot skipped. Please remember to reboot your system manually later."
        log "After reboot, verify the installation with: nvidia-smi"
    fi
}

main() {
    trap cleanup EXIT
    
    check_root
    
    log "Starting NVIDIA driver installation for Ubuntu..."
    
    # 1. Install nvidia-detect assistant
    install_nvidia_assistant
    
    # 2. Show nvidia assistant information
    show_nvidia_assistant_info
    
    # 3. Install kernel headers and development packages
    log "Installing kernel headers for $(uname -r)..."
    if ! apt install -y "linux-headers-$(uname -r)"; then
        error "Failed to install kernel headers"
        exit 1
    fi
    
    # 4. Detect OS version and set distribution variable
    log "Detecting OS version..."
    distribution=$(. /etc/os-release; echo "$ID$VERSION_ID" | sed -e 's/\.//g')
    log "Detected distribution: $distribution"
    
    # 5. Download CUDA keyring for the detected distribution
    log "Downloading CUDA keyring for $distribution..."
    keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-keyring_1.1-1_all.deb"

    if ! wget -q --show-progress "$keyring_url"; then
        error "Failed to download CUDA keyring from $keyring_url"
        exit 1
    fi
    
    # 6. Install CUDA keyring
    log "Installing CUDA keyring..."
    if ! dpkg -i cuda-keyring_1.1-1_all.deb; then
        error "Failed to install CUDA keyring"
        exit 1
    fi
    
    # 7. Update package lists (ignore CD-ROM mount issues)
    log "Updating package lists..."
    if ! apt update -o APT::CDROM::NoMount=true 2>/dev/null; then
        log "Warning: Some repositories failed to update, but continuing..."
        # Try alternative approach
        if ! apt update --allow-releaseinfo-change -o APT::CDROM::NoMount=true; then
            error "Failed to update package lists"
            exit 1
        fi
    fi
    
    # 8. Detect environment and install appropriate driver
    environment=$(detect_environment)
    log "Detected environment: $environment"
    
    if [[ "$environment" == "server" ]]; then
        log "Installing NVIDIA driver 535-server for headless/professional environment..."
        driver_package="nvidia-driver-535-server"
    else
        log "Installing NVIDIA driver 535 for desktop environment (GeForce series)..."
        driver_package="nvidia-driver-535"
    fi
    
    if ! apt install -y "$driver_package"; then
        error "Failed to install $driver_package"
        exit 1
    fi
    
    # 9. Remove NVIDIA blacklist entries
    remove_blacklist
    
    # 10. Load NVIDIA kernel module
    load_nvidia_module
    
    # 11. Verify NVIDIA installation
    verify_nvidia_installation
    
    # 12. Ask for reboot
    ask_reboot
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi