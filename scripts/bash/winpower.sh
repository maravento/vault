#!/bin/bash
# maravento.com
#
# WinPower Monitor Script for Linux
# Controls WinPower UPS software components installed in /opt/MonitorSoftware:
# - Agent: UPS monitoring core
# - Manager2: GUI interface
# - WarnMonitor: Alert/notification handler
#
# Download:
# https://www.salicru.com/us-en/winpower.html
#
# Serial: 511C1-01220-0100-478DF2A
# Admin password: Administrator
#
# Docs:
# Quick Setup: https://d7rh5s3nxmpy4.cloudfront.net/CMP1313/files/2/WinPower_Quick_Installation_and_Setup.pdf
# User Manual: https://d7rh5s3nxmpy4.cloudfront.net/CMP1313/files/1/UserManual_Winpower_ENG.pdf
#
# Usage:
# sudo ./winpower.sh                                      - Interactive menu
# sudo ./winpower.sh {install|remove|start|stop|status|restart}

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

WINPOWER_PATH="/opt/MonitorSoftware"
SERVICE_NAME="winpower.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
SCRIPT_PATH=$(readlink -f "$0")
DOWNLOAD_URL="https://d7rh5s3nxmpy4.cloudfront.net/CMP1313/files/4/Winpower_setup_LinuxAMD64.tar.gz"
TEMP_DIR="/tmp/winpower_install"

# Check for required dependencies
echo "→ Checking dependencies..."
if ! command -v wget &> /dev/null; then
    echo "✗ wget is required but not installed"
    echo "  Install with: apt-get install wget (Debian/Ubuntu)"
    echo "  or: yum install wget (RHEL/CentOS)"
    return 1
fi

if ! command -v tar &> /dev/null; then
    echo "✗ tar is required but not installed"
    return 1
fi

# Function to show menu
show_menu() {
    clear
    echo "════════════════════════════════════════"
    echo "    WinPower UPS Management Menu"
    echo "════════════════════════════════════════"
    echo ""
    echo "  1) Install"
    echo "  2) Remove"
    echo "  3) Start"
    echo "  4) Stop"
    echo "  5) Status"
    echo "  6) Restart"
    echo "  0) Exit"
    echo ""
    echo "════════════════════════════════════════"
    echo -n "Select option: "
}

# Function to pause
pause() {
    echo ""
    read -p "Press Enter to continue..."
}

# Function to install WinPower
install_winpower() {
    echo "════════════════════════════════════════"
    echo "    WinPower Installation"
    echo "════════════════════════════════════════"
    echo ""
    
    # Check if already installed
    if [ -d "$WINPOWER_PATH" ]; then
        echo "⚠ WinPower is already installed at $WINPOWER_PATH"
        read -p "Reinstall? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Installation cancelled"
            return
        fi
        echo "→ Removing existing installation..."
        stop_all
        rm -rf "$WINPOWER_PATH"
    fi
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || {
        echo "✗ Cannot create temp directory"
        return 1
    }
    
    # Download
    echo "→ Downloading WinPower..."
    if ! wget -O Winpower_setup_LinuxAMD64.tar.gz "$DOWNLOAD_URL" 2>/dev/null; then
        echo "✗ Download failed"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Extract (ignore macOS metadata warnings)
    echo "→ Extracting files..."
    tar -xzf Winpower_setup_LinuxAMD64.tar.gz 2>/dev/null
    
    # Check if extraction created expected directory structure
    if [ -d "Winpower_setup_LinuxAMD64" ]; then
        cd "Winpower_setup_LinuxAMD64"
    fi
    
    # Look for LinuxAMD64 directory or install.bin directly
    if [ -d "LinuxAMD64" ]; then
        cd "LinuxAMD64"
    elif [ ! -f "install.bin" ]; then
        echo "✗ Could not find installer structure after extraction"
        echo "Contents of temp directory:"
        ls -la
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Check if installer exists and is executable
    if [ -f "install.bin" ]; then
        chmod +x install.bin
        echo "→ Running installer..."
        echo ""
        echo "NOTE: The installer will now run. Follow its instructions."
        echo "It may show warnings about macOS metadata - this is normal."
        echo ""
        ./install.bin
    else
        echo "✗ Installer not found (install.bin)"
        echo "Available files:"
        ls -la
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Clean up
    cd /
    rm -rf "$TEMP_DIR"
    
    # Copy this script to WinPower directory if installation succeeded
    if [ -d "$WINPOWER_PATH" ]; then
        cp "$SCRIPT_PATH" "$WINPOWER_PATH/"
        chmod +x "$WINPOWER_PATH/winpower.sh"
        echo ""
        echo "✓ WinPower installed successfully"
        echo ""
        read -p "Install systemd service for auto-start? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_service
        fi
    else
        echo ""
        echo "⚠ Important: Please check if installation completed."
        echo "The WinPower installer may require manual interaction."
        echo "Installation directory not automatically created at: $WINPOWER_PATH"
        echo ""
        echo "If installation failed, you may need to:"
        echo "1. Run the installer manually from the extracted files"
        echo "2. Make sure to install to /opt/MonitorSoftware"
        echo "3. Ensure you have sufficient disk space and permissions"
    fi
}

# Function to remove WinPower completely
remove_winpower() {
    echo "════════════════════════════════════════"
    echo "    WinPower Complete Removal"
    echo "════════════════════════════════════════"
    echo ""
    
    # Check if WinPower is installed
    if [ ! -d "$WINPOWER_PATH" ]; then
        echo "⚠ WinPower is not installed at $WINPOWER_PATH"
        echo ""
        echo "No action required - nothing to remove."
        return 0
    fi
    
    echo "⚠ WARNING: This will:"
    echo "  - Stop all WinPower components"
    echo "  - Remove systemd service"
    echo "  - Delete all files from $WINPOWER_PATH"
    echo ""
    read -p "Continue? (y/n): " confirm
    
    # yY/nN
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "yes" ]; then
        echo "Removal cancelled"
        return 0
    fi
    
    echo ""
    echo "→ Stopping all components..."
    stop_all
    
    if [ -f "$SERVICE_PATH" ]; then
        echo "→ Removing systemd service..."
        systemctl stop $SERVICE_NAME 2>/dev/null
        systemctl disable $SERVICE_NAME 2>/dev/null
        rm -f "$SERVICE_PATH"
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null
        echo "  ✓ Service removed"
    fi
    
    if [ -d "$WINPOWER_PATH" ]; then
        echo "→ Removing WinPower directory..."
        rm -rf "$WINPOWER_PATH"
        echo "  ✓ Directory removed"
    fi
    
    echo ""
    echo "✓ WinPower completely removed from system"
}

# Function to start all components
start_all() {
    if [ ! -d "$WINPOWER_PATH" ]; then
        echo "✗ WinPower not installed at $WINPOWER_PATH"
        return 1
    fi
    
    cd "$WINPOWER_PATH" || {
        echo "✗ Cannot access $WINPOWER_PATH"
        return 1
    }
    
    echo "Starting WinPower..."
    
    # Start via systemd service if exists
    if [ -f "$SERVICE_PATH" ]; then
        echo "→ Starting via systemd service..."
        systemctl start $SERVICE_NAME
        sleep 3
        
        # Check if service started successfully
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo "✓ Service started successfully"
        else
            echo "⚠ Service may have issues. Check status with: systemctl status $SERVICE_NAME"
        fi
    else
        # Start processes directly with proper detachment
        echo "→ Starting components directly..."
        
        # Check if components are already running
        local agent_running=$(pgrep -f "Agent.lax")
        local manager_running=$(pgrep -f "Manager2.lax")
        local warn_running=$(pgrep -f "WarnMonitor.lax")
        
        if [ -n "$agent_running" ] || [ -n "$manager_running" ] || [ -n "$warn_running" ]; then
            echo "⚠ Some components are already running"
            echo "  Stopping them first..."
            stop_all
            sleep 2
        fi
        
        # Start components with nohup and redirect output
        echo "  Starting Agent..."
        nohup ./Agent > /dev/null 2>&1 &
        sleep 2
        
        echo "  Starting Manager2..."
        nohup ./Manager2 > /dev/null 2>&1 &
        sleep 2
        
        echo "  Starting WarnMonitor..."
        nohup ./WarnMonitor > /dev/null 2>&1 &
        sleep 1
        
        # Verify processes are running
        echo ""
        echo "Verifying processes..."
        local count=0
        
        if pgrep -f "Agent.lax" > /dev/null; then
            echo "  ✓ Agent running (PID: $(pgrep -f 'Agent.lax'))"
            ((count++))
        else
            echo "  ✗ Agent failed to start"
        fi
        
        if pgrep -f "Manager2.lax" > /dev/null; then
            echo "  ✓ Manager2 running (PID: $(pgrep -f 'Manager2.lax'))"
            ((count++))
        else
            echo "  ✗ Manager2 failed to start"
        fi
        
        if pgrep -f "WarnMonitor.lax" > /dev/null; then
            echo "  ✓ WarnMonitor running (PID: $(pgrep -f 'WarnMonitor.lax'))"
            ((count++))
        else
            echo "  ✗ WarnMonitor failed to start"
        fi
        
        if [ $count -eq 3 ]; then
            echo ""
            echo "✓ All components started successfully"
            echo "Note: Components are running in background."
            echo "Output is redirected to /dev/null to prevent terminal blocking."
        else
            echo ""
            echo "⚠ Only $count out of 3 components started"
        fi
    fi
}

# Function to stop all components
stop_all() {
    # Check if WinPower is installed
    if [ ! -d "$WINPOWER_PATH" ]; then
        echo "✗ WinPower is not installed"
        return 1
    fi
    
    echo "Stopping WinPower..."
    
    # Stop systemd service if exists and running
    if [ -f "$SERVICE_PATH" ]; then
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo "→ Stopping systemd service..."
            systemctl stop $SERVICE_NAME
            sleep 2
        fi
    fi
    
    # Stop processes directly
    local stopped=false
    
    # First try graceful SIGTERM
    echo "→ Sending stop signals to components..."
    
    if pgrep -f "Agent.lax" > /dev/null; then
        echo "  Stopping Agent..."
        pkill -f "Agent.lax"
        stopped=true
    fi
    
    if pgrep -f "Manager2.lax" > /dev/null; then
        echo "  Stopping Manager2..."
        pkill -f "Manager2.lax"
        stopped=true
    fi
    
    if pgrep -f "WarnMonitor.lax" > /dev/null; then
        echo "  Stopping WarnMonitor..."
        pkill -f "WarnMonitor.lax"
        stopped=true
    fi
    
    # Wait a moment for graceful shutdown
    if [ "$stopped" = true ]; then
        sleep 3
        
        # Force kill if still running
        if pgrep -f "Agent.lax" > /dev/null; then
            echo "  Force killing Agent..."
            pkill -9 -f "Agent.lax"
        fi
        
        if pgrep -f "Manager2.lax" > /dev/null; then
            echo "  Force killing Manager2..."
            pkill -9 -f "Manager2.lax"
        fi
        
        if pgrep -f "WarnMonitor.lax" > /dev/null; then
            echo "  Force killing WarnMonitor..."
            pkill -9 -f "WarnMonitor.lax"
        fi
        
        echo "✓ Components stopped"
    else
        echo "✓ No components were running"
    fi
}

# Function to show status
show_status() {
    echo "════════════════════════════════════════"
    echo "    WinPower Status"
    echo "════════════════════════════════════════"
    echo ""
    
    # Check installation path
    if [ -d "$WINPOWER_PATH" ]; then
        echo "Installation: ✓ Found at $WINPOWER_PATH"
    else
        echo "Installation: ✗ Not found at $WINPOWER_PATH"
        echo ""
        return
    fi
    
    echo ""
    echo "Components:"
    if pgrep -f "Agent.lax" > /dev/null; then
        echo "  ✓ Agent running (PID: $(pgrep -f 'Agent.lax'))"
    else
        echo "  ✗ Agent stopped"
    fi
    
    if pgrep -f "Manager2.lax" > /dev/null; then
        echo "  ✓ Manager2 running (PID: $(pgrep -f 'Manager2.lax'))"
    else
        echo "  ✗ Manager2 stopped"
    fi
    
    if pgrep -f "WarnMonitor.lax" > /dev/null; then
        echo "  ✓ WarnMonitor running (PID: $(pgrep -f 'WarnMonitor.lax'))"
    else
        echo "  ✗ WarnMonitor stopped"
    fi
    
    echo ""
    echo "Service:"
    if [ -f "$SERVICE_PATH" ]; then
        echo "  Status: Installed"
        if systemctl is-enabled --quiet $SERVICE_NAME 2>/dev/null; then
            echo "  Auto-start: Enabled"
        else
            echo "  Auto-start: Disabled"
        fi
        if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
            echo "  State: Active"
        else
            echo "  State: Inactive"
        fi
    else
        echo "  Status: Not installed"
    fi
}

# Function to restart
restart_all() {
    # Check if WinPower is installed
    if [ ! -d "$WINPOWER_PATH" ]; then
        echo "✗ WinPower is not installed"
        return 1
    fi
    
    echo "Restarting WinPower..."
    
    # If service exists, use systemctl restart
    if [ -f "$SERVICE_PATH" ]; then
        echo "→ Restarting via systemd service..."
        systemctl restart $SERVICE_NAME
        sleep 3
        echo "✓ Service restarted"
    else
        # Manual restart
        stop_all
        sleep 3
        start_all
    fi
}

# Function to install service
install_service() {
    if [ -f "$SERVICE_PATH" ]; then
        echo "Service already installed"
        return
    fi
    
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=WinPower UPS Monitoring Service
After=network.target

[Service]
Type=forking
ExecStart=$WINPOWER_PATH/winpower.sh start
ExecStop=$WINPOWER_PATH/winpower.sh stop
RemainAfterExit=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SERVICE_PATH"
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    
    echo "✓ Service installed and enabled"
}

# Check if running with parameters (command mode)
if [ $# -gt 0 ]; then
    case "$1" in
        install)
            install_winpower
            ;;
        remove)
            remove_winpower
            ;;
        start)
            start_all
            ;;
        stop)
            stop_all
            ;;
        status)
            show_status
            ;;
        restart)
            restart_all
            ;;
        *)
            echo "Usage: $0 {install|remove|start|stop|status|restart}"
            echo "Or run without parameters for menu"
            exit 1
            ;;
    esac
    exit 0
fi

# Interactive menu mode
while true; do
    show_menu
    read option
    
    case $option in
        1)
            install_winpower
            pause
            ;;
        2)
            remove_winpower
            pause
            ;;
        3)
            start_all
            pause
            ;;
        4)
            stop_all
            pause
            ;;
        5)
            show_status
            pause
            ;;
        6)
            restart_all
            pause
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option"
            pause
            ;;
    esac
done
