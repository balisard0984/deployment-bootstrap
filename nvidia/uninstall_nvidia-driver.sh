#!/bin/bash

#=============================================================================
# NVIDIA Driver Complete Uninstall Script for Ubuntu (Simplified)
# Version: 1.7
# Description: 
# - Checks if running in graphical mode and guides user to text mode
# - Completely removes NVIDIA drivers installed via .run or apt
# - Simple and clean approach without complex systemd services
# - ssh connection detection -> text mode processing
#=============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check current system target
get_current_target() {
    systemctl get-default 2>/dev/null || echo "unknown"
}

# Check if running in graphical environment
is_graphical_mode() {
    # Check if we're actually in a text console (tty1-tty6)
    local current_tty=$(tty 2>/dev/null)
    if [[ "$current_tty" =~ ^/dev/tty[1-6]$ ]]; then
        return 1  # Text mode
    fi
    
    # Check if running via SSH
    if [[ -n "$SSH_CONNECTION" ]] || [[ -n "$SSH_CLIENT" ]] || [[ "$TERM" == "xterm"* && -z "$DISPLAY" ]]; then
        return 1  # SSH connection, treat as text mode
    fi
    
    # Check current systemctl target (active, not default)
    local current_target=$(systemctl is-active graphical.target 2>/dev/null)
    if [[ "$current_target" == "inactive" ]]; then
        return 1  # Graphical target is not active
    fi
    
    # Check for display environment variables
    if [[ -n "$DISPLAY" ]] || [[ -n "$WAYLAND_DISPLAY" ]]; then
        return 0  # Graphical mode
    fi
    
    # Default to text mode if unsure
    return 1
}

# Display instructions for switching to text mode
show_text_mode_instructions() {
    clear
    echo "=========================================="
    echo "   Need to switch to text mode for safe removal"
    echo "=========================================="
    echo
    log_warn "To safely remove the NVIDIA driver, please run this script in text mode."
    echo
    log_info "Follow these steps to proceed:"
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
    log_warn "Executing the first command will terminate all GUI applications!"
    echo
    exit 0
}

# Display GPU information
display_gpu_info() {
    log_info "Checking GPU information..."
    echo "----------------------------------------"
    lspci -k | grep -EA3 'VGA|3D|Display' || log_warn "No GPU information found"
    echo "----------------------------------------"
}

# Check and remove .run file installation
remove_run_installation() {
    log_info "Checking for NVIDIA .run file installation..."
    
    # Check if nvidia-uninstall exists
    if [ -f /usr/bin/nvidia-uninstall ]; then
        log_info "Found NVIDIA .run installation. Attempting to uninstall..."
        
        # Try to run nvidia-uninstall
        if /usr/bin/nvidia-uninstall --silent; then
            log_info "Successfully uninstalled NVIDIA driver via nvidia-uninstall"
        else
            log_warn "nvidia-uninstall failed or partially completed"
        fi
    else
        log_info "No NVIDIA .run installation found"
    fi
    
    # Additional cleanup for .run installations
    if [ -f /usr/bin/nvidia-installer ]; then
        log_info "Attempting alternative uninstall method..."
        /usr/bin/nvidia-installer --uninstall --silent || log_warn "Alternative uninstall method failed"
    fi
}

# Enhanced apt removal function - primary removal
remove_apt_installation() {
    log_info "Starting enhanced NVIDIA driver removal via apt..."
    
    # Primary removal command as requested
    log_info "Step 1: Removing nvidia-driver and libxnvctrl packages with verbose output..."
    if apt remove --autoremove --purge -V nvidia-driver\* libxnvctrl\* -y 2>/dev/null; then
        log_info "Primary nvidia-driver packages removed successfully"
    else
        log_warn "Some nvidia-driver packages may not have been found or failed to remove"
    fi
}

# Enhanced comprehensive package removal
remove_all_nvidia_packages() {
    log_info "Performing comprehensive NVIDIA package cleanup..."
    
    # Execute removal commands in specified order
    log_info "Step 2: Purging all nvidia packages..."
    apt-get purge nvidia* -y 2>/dev/null || log_warn "Some nvidia packages may not exist"
    
    log_info "Step 3: Removing nvidia packages with regex pattern..."
    apt-get remove --purge '^nvidia-.*' -y 2>/dev/null || log_warn "Some nvidia packages may not exist"
    
    log_info "Step 4: Removing libnvidia packages..."
    apt-get remove --purge '^libnvidia-.*' -y 2>/dev/null || log_warn "Some libnvidia packages may not exist"
    
    log_info "Step 5: Removing CUDA packages..."
    apt-get remove --purge '^cuda-.*' -y 2>/dev/null || log_warn "Some cuda packages may not exist"
    
    log_info "Step 6: Final nvidia package cleanup..."
    apt-get --purge remove *nvidia* -y 2>/dev/null || log_warn "Some nvidia packages may not exist"
    
    log_info "Step 7: Removing orphaned dependencies..."
    apt-get autoremove -y
    
    log_info "Step 8: Cleaning package cache..."
    apt-get autoclean -y
    
    log_info "Comprehensive package removal completed"
}

# Create blacklist configuration
create_blacklist() {
    log_info "Creating NVIDIA blacklist configuration..."
    
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
    
    log_info "Blacklist configuration created at $BLACKLIST_FILE"
}

# Remove blacklist configuration
remove_blacklist() {
    log_info "Removing NVIDIA blacklist configuration..."
    
    BLACKLIST_FILE="/etc/modprobe.d/nvidia-blacklist.conf"
    
    if [ -f "$BLACKLIST_FILE" ]; then
        log_info "Commenting out blacklist entries in $BLACKLIST_FILE"
        sed -i 's/^blacklist /#blacklist /g' "$BLACKLIST_FILE"
        log_info "Blacklist entries have been commented out (disabled)"
    else
        log_info "No blacklist file found at $BLACKLIST_FILE"
    fi
}

# Remove NVIDIA kernel modules
remove_kernel_modules() {
    log_info "Removing NVIDIA kernel modules..."
    
    # List of NVIDIA modules to remove
    modules=("nvidia_drm" "nvidia_modeset" "nvidia_uvm" "nvidia")
    
    for module in "${modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            log_info "Removing module: $module"
            modprobe -r "$module" 2>/dev/null || log_warn "Could not remove module $module (may be in use)"
        fi
    done
}

# Clean up NVIDIA files and directories
cleanup_nvidia_files() {
    log_info "Cleaning up NVIDIA files and directories..."
    
    # Directories to clean
    declare -a dirs=(
        "/usr/local/cuda*"
        "/opt/cuda*"
        "/usr/lib/nvidia*"
        "/var/lib/nvidia*"
        "/etc/nvidia*"
    )
    
    for dir in "${dirs[@]}"; do
        if ls $dir 1> /dev/null 2>&1; then
            log_info "Removing $dir"
            rm -rf $dir
        fi
    done
    
    # Remove NVIDIA related files in /etc/X11
    if [ -f /etc/X11/xorg.conf ]; then
        log_warn "Found /etc/X11/xorg.conf - backing up to xorg.conf.backup"
        mv /etc/X11/xorg.conf /etc/X11/xorg.conf.backup
    fi
}

# Update system configurations
update_system() {
    log_info "Updating system configurations..."
    
    # Update initramfs
    log_info "Updating initramfs..."
    update-initramfs -u
    
    # Update GRUB
    log_info "Updating GRUB..."
    update-grub
    
    # Update dynamic linker cache
    log_info "Updating dynamic linker cache..."
    ldconfig
}

# Execute the main NVIDIA removal process
execute_nvidia_removal() {
    log_info "=========================================="
    log_info "Starting NVIDIA driver removal in text mode"
    log_info "=========================================="
    
    # Display current system information
    display_gpu_info
    echo
    
    # Execute removal steps
    remove_run_installation
    echo
    
    remove_apt_installation
    echo
    
    remove_all_nvidia_packages
    echo
    
    remove_kernel_modules
    echo
    
    create_blacklist
    echo
    
    cleanup_nvidia_files
    echo
    
    update_system
    echo
    
    # Remove blacklist after all operations are complete
    remove_blacklist
    echo
    
    log_info "=========================================="
    log_info "NVIDIA driver removal completed successfully!"
    log_info "Blacklist has been disabled for future installations."
    log_info "=========================================="
    
    log_info "The system needs to be rebooted to complete the process."
    
    read -p "Do you want to reboot now? (yes/no): " -r
    echo
    
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        log_info "Rebooting system..."
        reboot
    else
        log_info "Please remember to reboot your system manually."
        log_info "Run 'sudo reboot' when ready."
        log_info "After reboot, you can return to GUI mode with:"
        log_info "sudo systemctl isolate graphical.target"
    fi
}

# Main execution function
main() {
    clear
    echo "=========================================="
    echo "   NVIDIA Driver Complete Uninstall"
    echo "   Simple Text Mode Approach"
    echo "=========================================="
    echo
    
    # Check root privileges
    check_root
    
    # Check if we're in graphical mode
    if is_graphical_mode; then
        log_info "Detected graphical environment."
        log_info "Current TTY: $(tty 2>/dev/null || echo 'unknown')"
        log_info "Current target: $(get_current_target)"
        log_info "Graphical target active: $(systemctl is-active graphical.target 2>/dev/null || echo 'unknown')"
        show_text_mode_instructions
        # This will exit the script
    else
        log_info "Running in text mode. Proceeding with NVIDIA removal..."
        log_info "Current TTY: $(tty 2>/dev/null || echo 'unknown')"
        log_info "Current target: $(get_current_target)"
        log_info "Graphical target active: $(systemctl is-active graphical.target 2>/dev/null || echo 'unknown')"
        echo
        
        # Display warning
        log_warn "This will completely remove all NVIDIA drivers and related packages!"
        echo
        
        read -p "Continue with NVIDIA driver removal? (yes/no): " -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
            log_info "Operation cancelled by user"
            exit 0
        fi
        
        # Execute the removal process
        execute_nvidia_removal
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi