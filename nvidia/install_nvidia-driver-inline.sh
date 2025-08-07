#!/bin/bash

#=============================================================================
# NVIDIA Driver Install Script for Ubuntu (Inline Version)
# Version: 1.4-inline
# Description: 
# - Installs NVIDIA drivers for Ubuntu 
# - Detects environment (desktop/server) and installs appropriate driver
# - Fixed install driver version to 535
# - Converted from function-based to inline sequential execution
#=============================================================================

set -euo pipefail

# Check root privileges
if [[ $EUID -ne 0 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: This script must be run as root" >&2
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting NVIDIA driver installation for Ubuntu..."

# Cleanup function for EXIT trap
cleanup_files() {
    if [[ -f cuda-keyring_1.1-1_all.deb ]]; then
        rm -f cuda-keyring_1.1-1_all.deb
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaned up cuda-keyring package file"
    fi
}
trap cleanup_files EXIT

# 1. Install nvidia-driver-assistant
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing nvidia-driver-assistant with sudo privileges..."

if ! sudo apt install -y nvidia-driver-assistant; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: nvidia-driver-assistant not available, trying alternative packages..."
    
    # Try installing ubuntu-drivers-common which provides similar functionality
    if ! sudo apt install -y ubuntu-drivers-common; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: Could not install GPU detection tools"
    fi
fi

# 2. Show nvidia assistant information
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking recommended NVIDIA driver using nvidia-driver-assistant..."

if command -v nvidia-driver-assistant &> /dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running nvidia-driver-assistant --distro:"
    nvidia-driver-assistant --distro || true
elif command -v ubuntu-drivers &> /dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] nvidia-driver-assistant not found, using ubuntu-drivers instead:"
    ubuntu-drivers devices || true
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No driver detection tool available, proceeding with default selection"
fi

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Above information shows recommended drivers for your system"
echo ""

# 3. Install kernel headers and development packages
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing kernel headers for $(uname -r)..."
if ! apt install -y "linux-headers-$(uname -r)"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to install kernel headers" >&2
    exit 1
fi

# 4. Detect OS version and set distribution variable
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detecting OS version..."
distribution=$(. /etc/os-release; echo "$ID$VERSION_ID" | sed -e 's/\.//g')
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detected distribution: $distribution"

# 5. Download CUDA keyring for the detected distribution
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Downloading CUDA keyring for $distribution..."
keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-keyring_1.1-1_all.deb"

if ! wget -q --show-progress "$keyring_url"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to download CUDA keyring from $keyring_url" >&2
    exit 1
fi

# 6. Install CUDA keyring
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing CUDA keyring..."
if ! dpkg -i cuda-keyring_1.1-1_all.deb; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to install CUDA keyring" >&2
    exit 1
fi

# 7. Update package lists (ignore CD-ROM mount issues)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updating package lists..."
if ! apt update -o APT::CDROM::NoMount=true 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: Some repositories failed to update, but continuing..."
    # Try alternative approach
    if ! apt update --allow-releaseinfo-change -o APT::CDROM::NoMount=true; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to update package lists" >&2
        exit 1
    fi
fi

# 8. Detect GPU environment and install appropriate driver
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detecting GPU model..."

# Install pciutils if not available
if ! command -v lspci &> /dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: lspci command not found. Installing pciutils..." >&2
    apt install -y pciutils
fi

# Try to get GPU info using lspci
gpu_info=$(lspci | grep -i "vga\|3d\|display" | grep -i nvidia || true)

if [[ -n "$gpu_info" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found NVIDIA GPU: $gpu_info"
    
    # Check if it's a GeForce series
    if echo "$gpu_info" | grep -qi "geforce"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detected GeForce series GPU"
        environment="desktop"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detected non-GeForce GPU (likely professional/server series)"
        environment="server"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No NVIDIA GPU detected via lspci, defaulting to server"
    environment="server"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detected environment: $environment"

if [[ "$environment" == "server" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing NVIDIA driver 535-server for headless/professional environment..."
    driver_package="nvidia-driver-535-server"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing NVIDIA driver 535 for desktop environment (GeForce series)..."
    driver_package="nvidia-driver-535"
fi

if ! apt install -y "$driver_package"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to install $driver_package" >&2
    exit 1
fi

# 9. Remove NVIDIA blacklist entries
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking and removing NVIDIA driver blacklist if exists..."

blacklist_file="/etc/modprobe.d/nvidia-blacklist.conf"

if [[ -f "$blacklist_file" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found blacklist file: $blacklist_file"
    
    # Create backup before modification
    cp "$blacklist_file" "${blacklist_file}.bak"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Created backup: ${blacklist_file}.bak"
    
    # Comment out all blacklist entries
    sed -i 's/^blacklist /#blacklist /g' "$blacklist_file"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Disabled blacklist entries in $blacklist_file"
    
    # Show the changes
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Modified blacklist file contents:"
    cat "$blacklist_file"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No blacklist file found at $blacklist_file"
fi

# Check for other potential blacklist files
for file in /etc/modprobe.d/*blacklist*.conf; do
    if [[ -f "$file" ]] && grep -q "nvidia\|nouveau" "$file" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found potential NVIDIA-related blacklist in: $file"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] You may want to review this file manually"
    fi
done

# 10. Load NVIDIA kernel module
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Loading NVIDIA kernel module..."

if sudo modprobe nvidia; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Successfully loaded NVIDIA kernel module"
    module_loaded=true
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: Failed to load NVIDIA kernel module. This may be normal if driver installation requires reboot."
    module_loaded=false
fi

# 11. Verify NVIDIA installation
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verifying NVIDIA driver installation..."

if command -v nvidia-smi &> /dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running nvidia-smi to verify installation..."
    echo "============================================"
    if nvidia-smi; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NVIDIA driver verification successful!"
        verification_success=true
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] nvidia-smi command failed. Driver may need system reboot to function properly."
        verification_success=false
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] nvidia-smi command not found. Driver installation may be incomplete."
    verification_success=false
fi

# 12. Ask for reboot
echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] NVIDIA driver installation completed!"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] =========================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] It is highly recommended to reboot your system to ensure the new driver is properly loaded."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Some NVIDIA features may not work correctly until after reboot."
echo ""

read -p "Would you like to reboot now? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Rebooting system in 5 seconds... Press Ctrl+C to cancel."
    sleep 5
    sudo reboot
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Reboot skipped. Please remember to reboot your system manually later."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] After reboot, verify the installation with: nvidia-smi"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Script execution completed."
