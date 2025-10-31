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
# Install:
# wget -O Winpower_setup_LinuxAMD64.tar.gz "https://d7rh5s3nxmpy4.cloudfront.net/CMP1313/files/4/Winpower_setup_LinuxAMD64.tar.gz"
# tar -xvzf Winpower_setup_LinuxAMD64.tar.gz && cd Winpower_setup_LinuxAMD64/LinuxAMD64
# chmod +x install.bin && sudo ./install.bin
#
# Serial: 511C1-01220-0100-478DF2A
# Admin password: Administrator
#
# Docs:
# Quick Setup: https://d7rh5s3nxmpy4.cloudfront.net/CMP1313/files/2/WinPower_Quick_Installation_and_Setup.pdf
# User Manual: https://d7rh5s3nxmpy4.cloudfront.net/CMP1313/files/1/UserManual_Winpower_ENG.pdf
#
# Usage:
# sudo ./winpower.sh {start|stop|status|restart}
#
# Manual check:
# ps aux | grep -E 'Agent|Manager2|WarnMonitor' | grep -v grep
# pgrep -af 'Agent.lax|Manager2.lax|WarnMonitor.lax'
#
# Cron example:
# @reboot /opt/MonitorSoftware/winpower.sh start

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

WINPOWER_PATH="/opt/MonitorSoftware"
AGENT_NAME="Agent"
MANAGER_NAME="Manager2"
WARN_MONITOR_NAME="WarnMonitor"

SCRIPT_PATH=$(readlink -f "$0")

cd "$WINPOWER_PATH" || {
    echo "Error: Cannot change directory to $WINPOWER_PATH"
    exit 1
}

case "$1" in
    start)
        echo "Starting WinPower..."
        echo "Starting Agent..."
        ./Agent &
        sleep 2
        echo "Starting Manager2..."
        ./Manager2 &
        sleep 2
        echo "Starting WarnMonitor..."
        ./WarnMonitor &
        echo "WinPower started successfully"
        ;;
    stop)
        echo "Stopping WinPower..."
        
        # Check and stop Agent
        if pgrep -f "Agent.lax" > /dev/null; then
            echo "Stopping Agent..."
            pkill -f "Agent.lax"
        else
            echo "Agent is not running"
        fi
        
        # Check and stop Manager2
        if pgrep -f "Manager2.lax" > /dev/null; then
            echo "Stopping Manager2..."
            pkill -f "Manager2.lax"
        else
            echo "Manager2 is not running"
        fi
        
        # Check and stop WarnMonitor
        if pgrep -f "WarnMonitor.lax" > /dev/null; then
            echo "Stopping WarnMonitor..."
            pkill -f "WarnMonitor.lax"
        else
            echo "WarnMonitor is not running"
        fi
        
        echo "Stop operation completed"
        ;;
    status)
        echo "=== WinPower Status ==="
        
        if pgrep -f "Agent.lax" > /dev/null; then
            echo "✓ Agent is running (PID: $(pgrep -f 'Agent.lax'))"
        else
            echo "✗ Agent is not running"
        fi
        
        if pgrep -f "Manager2.lax" > /dev/null; then
            echo "✓ Manager2 is running (PID: $(pgrep -f 'Manager2.lax'))"
        else
            echo "✗ Manager2 is not running"
        fi
        
        if pgrep -f "WarnMonitor.lax" > /dev/null; then
            echo "✓ WarnMonitor is running (PID: $(pgrep -f 'WarnMonitor.lax'))"
        else
            echo "✗ WarnMonitor is not running"
        fi
        ;;
    restart)
        echo "Restarting WinPower..."
        "$SCRIPT_PATH" stop
        sleep 3
        "$SCRIPT_PATH" start
        ;;
    agent)
        case "$2" in
            start)
                echo "Starting Agent only..."
                ./Agent &
                ;;
            stop)
                if pgrep -f "Agent.lax" > /dev/null; then
                    echo "Stopping Agent..."
                    pkill -f "Agent.lax"
                else
                    echo "Agent is not running"
                fi
                ;;
            status)
                if pgrep -f "Agent.lax" > /dev/null; then
                    echo "Agent is running (PID: $(pgrep -f 'Agent.lax'))"
                else
                    echo "Agent is not running"
                fi
                ;;
            *)
                echo "Invalid action for 'agent'"
                exit 1
                ;;
        esac
        ;;
    manager)
        case "$2" in
            start)
                echo "Starting Manager2 only..."
                ./Manager2 &
                ;;
            stop)
                if pgrep -f "Manager2.lax" > /dev/null; then
                    echo "Stopping Manager2..."
                    pkill -f "Manager2.lax"
                else
                    echo "Manager2 is not running"
                fi
                ;;
            status)
                if pgrep -f "Manager2.lax" > /dev/null; then
                    echo "Manager2 is running (PID: $(pgrep -f 'Manager2.lax'))"
                else
                    echo "Manager2 is not running"
                fi
                ;;
            *)
                echo "Invalid action for 'Manager2'"
                exit 1
                ;;
        esac
        ;;
    monitor)
        case "$2" in
            start)
                echo "Starting WarnMonitor only..."
                ./WarnMonitor &
                ;;
            stop)
                if pgrep -f "WarnMonitor.lax" > /dev/null; then
                    echo "Stopping WarnMonitor..."
                    pkill -f "WarnMonitor.lax"
                else
                    echo "WarnMonitor is not running"
                fi
                ;;
            status)
                if pgrep -f "WarnMonitor.lax" > /dev/null; then
                    echo "WarnMonitor is running (PID: $(pgrep -f 'WarnMonitor.lax'))"
                else
                    echo "WarnMonitor is not running"
                fi
                ;;
            *)
                echo "Invalid action for 'WarnMonitor'"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        echo ""
        echo "Available commands:"
        echo "  start    - Start all WinPower components"
        echo "  stop     - Stop all WinPower components"
        echo "  status   - Show status of all components"
        echo "  restart  - Restart all WinPower components"
        echo ""
        exit 1
        ;;
esac
