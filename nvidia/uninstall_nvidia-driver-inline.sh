#!/bin/bash

#=============================================================================
# NVIDIA Driver Complete Uninstall Script for Ubuntu (Sequential Version)
# Version: 1.7-sequential
# Description: 
# - Sequential execution without function calls
# - Completely removes NVIDIA drivers installed via .run or apt
# - Simple and straightforward approach
#=============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

clear
echo "=========================================="
echo "   NVIDIA Driver Complete Uninstall"
echo "   Sequential Execution Version"
echo "=========================================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Root privileges confirmed"

# Check current system environment
current_tty=$(tty 2>/dev/null || echo "unknown")
current_target=$(systemctl get-default 2>/dev/null || echo "unknown")
graphical_active=$(systemctl is-active graphical.target 2>/dev/null || echo "unknown")

echo -e "${GREEN}[INFO]${NC} Current TTY: $current_tty"
echo -e "${GREEN}[INFO]${NC} Current target: $current_target"
echo -e "${GREEN}[INFO]${NC} Graphical target active: $graphical_active"

# Check if running in graphical environment
is_graphical=false

# Check if we're actually in a text console (tty1-tty6)
if [[ "$current_tty" =~ ^/dev/tty[1-6]$ ]]; then
    is_graphical=false
# Check if running via SSH
elif [[ -n "$SSH_CONNECTION" ]] || [[ -n "$SSH_CLIENT" ]] || [[ "$TERM" == "xterm"* && -z "$DISPLAY" ]]; then
    is_graphical=false
# Check if graphical target is inactive
elif [[ "$graphical_active" == "inactive" ]]; then
    is_graphical=false
# Check for display environment variables
elif [[ -n "$DISPLAY" ]] || [[ -n "$WAYLAND_DISPLAY" ]]; then
    is_graphical=true
else
    # Default to text mode if unsure
    is_graphical=false
fi

# Handle graphical mode detection
if [ "$is_graphical" = true ]; then
    echo -e "${GREEN}[INFO]${NC} Detected graphical environment."
    clear
    echo "=========================================="
    echo "   Need to switch to text mode for safe removal"
    echo "=========================================="
    echo
    echo -e "${YELLOW}[WARN]${NC} To safely remove the NVIDIA driver, please run this script in text mode."
    echo
    echo -e "${GREEN}[INFO]${NC} Follow these steps to proceed:"
    echo
    echo "1. Switch to text mode:"
    echo -e "   ${YELLOW}sudo systemctl isolate multi-user.target${NC}"
    echo
    echo "2. After logging in to text mode, run this script again:"
    echo -e "   ${YELLOW}sudo $0${NC}"
    echo
    echo "3. After completing the tasks, return to GUI mode:"
    echo -e "   ${YELLOW}sudo systemctl isolate graphical.target${NC}"
    echo
    echo -e "${YELLOW}[WARN]${NC} Executing the first command will terminate all GUI applications!"
    echo
    exit 0
fi

# Continue in text mode
echo -e "${GREEN}[INFO]${NC} Running in text mode. Proceeding with NVIDIA removal..."
echo

# Display warning
echo -e "${YELLOW}[WARN]${NC} This will completely remove all NVIDIA drivers and related packages!"
echo

read -p "Continue with NVIDIA driver removal? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${GREEN}[INFO]${NC} Operation cancelled by user"
    exit 0
fi

echo -e "${GREEN}[INFO]${NC} =========================================="
echo -e "${GREEN}[INFO]${NC} Starting NVIDIA driver removal in text mode"
echo -e "${GREEN}[INFO]${NC} =========================================="

# Display GPU information
echo -e "${GREEN}[INFO]${NC} Checking GPU information..."
echo "----------------------------------------"
lspci -k | grep -EA3 'VGA|3D|Display' || echo -e "${YELLOW}[WARN]${NC} No GPU information found"
echo "----------------------------------------"
echo

# Check and remove .run file installation
echo -e "${GREEN}[INFO]${NC} Checking for NVIDIA .run file installation..."

if [ -f /usr/bin/nvidia-uninstall ]; then
    echo -e "${GREEN}[INFO]${NC} Found NVIDIA .run installation. Attempting to uninstall..."
    
    if /usr/bin/nvidia-uninstall --silent; then
        echo -e "${GREEN}[INFO]${NC} Successfully uninstalled NVIDIA driver via nvidia-uninstall"
    else
        echo -e "${YELLOW}[WARN]${NC} nvidia-uninstall failed or partially completed"
    fi
else
    echo -e "${GREEN}[INFO]${NC} No NVIDIA .run installation found"
fi

# Additional cleanup for .run installations
if [ -f /usr/bin/nvidia-installer ]; then
    echo -e "${GREEN}[INFO]${NC} Attempting alternative uninstall method..."
    /usr/bin/nvidia-installer --uninstall --silent || echo -e "${YELLOW}[WARN]${NC} Alternative uninstall method failed"
fi
echo

# Enhanced apt removal - primary removal
echo -e "${GREEN}[INFO]${NC} Starting enhanced NVIDIA driver removal via apt..."
echo -e "${GREEN}[INFO]${NC} Step 1: Removing nvidia-driver and libxnvctrl packages with verbose output..."

if apt remove --autoremove --purge -V nvidia-driver\* libxnvctrl\* -y 2>/dev/null; then
    echo -e "${GREEN}[INFO]${NC} Primary nvidia-driver packages removed successfully"
else
    echo -e "${YELLOW}[WARN]${NC} Some nvidia-driver packages may not have been found or failed to remove"
fi
echo

# Comprehensive package removal
echo -e "${GREEN}[INFO]${NC} Performing comprehensive NVIDIA package cleanup..."

echo -e "${GREEN}[INFO]${NC} Step 2: Purging all nvidia packages..."
apt-get purge nvidia* -y 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} Some nvidia packages may not exist"

echo -e "${GREEN}[INFO]${NC} Step 3: Removing nvidia packages with regex pattern..."
apt-get remove --purge '^nvidia-.*' -y 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} Some nvidia packages may not exist"

echo -e "${GREEN}[INFO]${NC} Step 4: Removing libnvidia packages..."
apt-get remove --purge '^libnvidia-.*' -y 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} Some libnvidia packages may not exist"

echo -e "${GREEN}[INFO]${NC} Step 5: Removing CUDA packages..."
apt-get remove --purge '^cuda-.*' -y 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} Some cuda packages may not exist"

echo -e "${GREEN}[INFO]${NC} Step 6: Final nvidia package cleanup..."
apt-get --purge remove *nvidia* -y 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} Some nvidia packages may not exist"

echo -e "${GREEN}[INFO]${NC} Step 7: Removing orphaned dependencies..."
apt-get autoremove -y

echo -e "${GREEN}[INFO]${NC} Step 8: Cleaning package cache..."
apt-get autoclean -y

echo -e "${GREEN}[INFO]${NC} Comprehensive package removal completed"
echo

# Remove NVIDIA kernel modules
echo -e "${GREEN}[INFO]${NC} Removing NVIDIA kernel modules..."

modules=("nvidia_drm" "nvidia_modeset" "nvidia_uvm" "nvidia")

for module in "${modules[@]}"; do
    if lsmod | grep -q "^$module"; then
        echo -e "${GREEN}[INFO]${NC} Removing module: $module"
        modprobe -r "$module" 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} Could not remove module $module (may be in use)"
    fi
done
echo

# Create blacklist configuration
echo -e "${GREEN}[INFO]${NC} Creating NVIDIA blacklist configuration..."

BLACKLIST_FILE="/etc/modprobe.d/nvidia-blacklist.conf"

cat > "$BLACKLIST_FILE" << EOF
# Blacklist NVIDIA drivers
blacklist nvidia
blacklist nvidia-drm
blacklist nvidia-modeset
blacklist nvidia-uvm
blacklist nvidiafb
blacklist nouveau
blacklist rivafb
blacklist rivatv
EOF

echo -e "${GREEN}[INFO]${NC} Blacklist configuration created at $BLACKLIST_FILE"
echo

# Clean up NVIDIA files and directories
echo -e "${GREEN}[INFO]${NC} Cleaning up NVIDIA files and directories..."

# Directories to clean
dirs=("/usr/local/cuda*" "/opt/cuda*" "/usr/lib/nvidia*" "/var/lib/nvidia*" "/etc/nvidia*")

for dir in "${dirs[@]}"; do
    if ls $dir 1> /dev/null 2>&1; then
        echo -e "${GREEN}[INFO]${NC} Removing $dir"
        rm -rf $dir
    fi
done

# Remove NVIDIA related files in /etc/X11
if [ -f /etc/X11/xorg.conf ]; then
    echo -e "${YELLOW}[WARN]${NC} Found /etc/X11/xorg.conf - backing up to xorg.conf.backup"
    mv /etc/X11/xorg.conf /etc/X11/xorg.conf.backup
fi
echo

# Update system configurations
echo -e "${GREEN}[INFO]${NC} Updating system configurations..."

echo -e "${GREEN}[INFO]${NC} Updating initramfs..."
update-initramfs -u

echo -e "${GREEN}[INFO]${NC} Updating GRUB..."
update-grub

echo -e "${GREEN}[INFO]${NC} Updating dynamic linker cache..."
ldconfig
echo

# Remove blacklist after all operations are complete
echo -e "${GREEN}[INFO]${NC} Removing NVIDIA blacklist configuration..."

if [ -f "$BLACKLIST_FILE" ]; then
    echo -e "${GREEN}[INFO]${NC} Commenting out blacklist entries in $BLACKLIST_FILE"
    sed -i 's/^blacklist /#blacklist /g' "$BLACKLIST_FILE"
    echo -e "${GREEN}[INFO]${NC} Blacklist entries have been commented out (disabled)"
else
    echo -e "${GREEN}[INFO]${NC} No blacklist file found at $BLACKLIST_FILE"
fi
echo

# Final completion message
echo -e "${GREEN}[INFO]${NC} =========================================="
echo -e "${GREEN}[INFO]${NC} NVIDIA driver removal completed successfully!"
echo -e "${GREEN}[INFO]${NC} Blacklist has been disabled for future installations."
echo -e "${GREEN}[INFO]${NC} =========================================="

echo -e "${GREEN}[INFO]${NC} The system needs to be rebooted to complete the process."

read -p "Do you want to reboot now? (yes/no): " -r
echo

if [[ $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${GREEN}[INFO]${NC} Rebooting system..."
    reboot
else
    echo -e "${GREEN}[INFO]${NC} Please remember to reboot your system manually."
    echo -e "${GREEN}[INFO]${NC} Run 'sudo reboot' when ready."
    echo -e "${GREEN}[INFO]${NC} After reboot, you can return to GUI mode with:"
    echo -e "${GREEN}[INFO]${NC} sudo systemctl isolate graphical.target"
fi
