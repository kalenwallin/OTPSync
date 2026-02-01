#!/bin/bash
# OTPSync Android Debug Script
# Usage: ./debug.sh [command]
#
# Commands:
#   build     - Build and install debug APK
#   run       - Build, install, and launch the app
#   logs      - Show live app logs (filtered to OTPSync)
#   logcat    - Show full logcat with all logs
#   wireless  - Set up wireless debugging
#   devices   - List connected devices
#   clear     - Clear app data
#   uninstall - Uninstall the app
#   crash     - Show crash logs

set -e

APP_PACKAGE="com.kalenwallin.otpsync.dev"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ ${NC}$1"; }
log_success() { echo -e "${GREEN}✓ ${NC}$1"; }
log_warn() { echo -e "${YELLOW}⚠ ${NC}$1"; }
log_error() { echo -e "${RED}✗ ${NC}$1"; }

# Get the first USB device, or first device if no USB
get_device() {
    # Prefer USB device over wireless
    local usb_device=$(adb devices -l 2>/dev/null | grep -E "usb:" | head -1 | awk '{print $1}')
    if [ -n "$usb_device" ]; then
        echo "$usb_device"
        return
    fi
    # Fall back to first available device
    adb devices 2>/dev/null | grep -E "device$" | head -1 | awk '{print $1}'
}

# Wrapper for adb commands to use specific device
adb_cmd() {
    local device=$(get_device)
    if [ -n "$device" ]; then
        adb -s "$device" "$@"
    else
        adb "$@"
    fi
}

# Check for connected devices
check_device() {
    if ! adb devices | grep -q "device$"; then
        log_error "No Android device connected!"
        echo ""
        echo "To connect via USB:"
        echo "  1. Enable Developer Options on your phone"
        echo "  2. Enable USB Debugging in Developer Options"
        echo "  3. Connect your phone via USB cable"
        echo ""
        echo "To connect wirelessly:"
        echo "  ./debug.sh wireless"
        exit 1
    fi
    local device=$(get_device)
    if [ -n "$device" ]; then
        log_info "Using device: $device"
    fi
}

case "${1:-help}" in
    build)
        log_info "Building debug APK..."
        cd "$SCRIPT_DIR"
        ./gradlew assembleDebug
        log_success "Build complete!"
        
        check_device
        log_info "Installing APK..."
        adb_cmd install -r app/build/outputs/apk/debug/app-debug.apk
        log_success "Installed successfully!"
        ;;
        
    run)
        log_info "Building debug APK..."
        cd "$SCRIPT_DIR"
        ./gradlew assembleDebug
        log_success "Build complete!"
        
        check_device
        log_info "Installing APK..."
        adb_cmd install -r app/build/outputs/apk/debug/app-debug.apk
        log_success "Installed!"
        
        log_info "Launching OTPSync..."
        adb_cmd shell am start -n "$APP_PACKAGE/com.kalenwallin.otpsync.MainActivity"
        log_success "App launched!"
        
        echo ""
        log_info "Showing logs (Ctrl+C to stop)..."
        echo "─────────────────────────────────────────────"
        adb_cmd logcat --pid=$(adb_cmd shell pidof -s $APP_PACKAGE) 2>/dev/null || \
            adb_cmd logcat | grep -E "(OTPSync|$APP_PACKAGE|AndroidRuntime|System.err)"
        ;;
        
    logs)
        check_device
        log_info "Showing OTPSync logs (Ctrl+C to stop)..."
        echo "─────────────────────────────────────────────"
        # Try to get PID-filtered logs first, fall back to grep
        PID=$(adb_cmd shell pidof -s $APP_PACKAGE 2>/dev/null)
        if [ -n "$PID" ]; then
            adb_cmd logcat --pid=$PID
        else
            log_warn "App not running. Showing filtered logcat..."
            adb_cmd logcat | grep -E "(OTPSync|$APP_PACKAGE|AndroidRuntime|System.err)"
        fi
        ;;
        
    logcat)
        check_device
        log_info "Showing full logcat (Ctrl+C to stop)..."
        adb_cmd logcat
        ;;
        
    crash)
        check_device
        log_info "Showing crash logs..."
        adb_cmd logcat -d | grep -A 20 "FATAL EXCEPTION\|AndroidRuntime" | tail -50
        ;;
        
    wireless)
        check_device
        log_info "Setting up wireless debugging..."
        
        # Get device IP
        DEVICE_IP=$(adb_cmd shell ip route | awk '/wlan0/ {print $9}' | head -1)
        if [ -z "$DEVICE_IP" ]; then
            DEVICE_IP=$(adb_cmd shell "ip addr show wlan0 | grep 'inet ' | cut -d' ' -f6 | cut -d/ -f1")
        fi
        
        if [ -z "$DEVICE_IP" ]; then
            log_error "Could not detect device IP. Make sure WiFi is connected."
            exit 1
        fi
        
        log_info "Device IP: $DEVICE_IP"
        
        # Enable TCP/IP mode on port 5555
        adb_cmd tcpip 5555
        sleep 2
        
        # Connect wirelessly
        log_info "Connecting to $DEVICE_IP:5555..."
        adb connect "$DEVICE_IP:5555"
        
        log_success "Wireless debugging enabled!"
        echo ""
        echo "You can now unplug the USB cable."
        echo "To reconnect later: adb connect $DEVICE_IP:5555"
        ;;
        
    devices)
        log_info "Connected devices:"
        adb devices -l
        ;;
        
    clear)
        check_device
        log_info "Clearing app data..."
        adb_cmd shell pm clear $APP_PACKAGE
        log_success "App data cleared!"
        ;;
        
    uninstall)
        check_device
        log_info "Uninstalling OTPSync..."
        adb_cmd uninstall $APP_PACKAGE
        log_success "Uninstalled!"
        ;;
        
    *)
        echo "OTPSync Android Debug Script"
        echo ""
        echo "Usage: ./debug.sh [command]"
        echo ""
        echo "Commands:"
        echo "  build     - Build and install debug APK"
        echo "  run       - Build, install, launch, and show logs"
        echo "  logs      - Show live app logs (filtered)"
        echo "  logcat    - Show full system logcat"
        echo "  crash     - Show recent crash logs"
        echo "  wireless  - Set up wireless debugging"
        echo "  devices   - List connected devices"
        echo "  clear     - Clear app data"
        echo "  uninstall - Uninstall the app"
        echo ""
        echo "Examples:"
        echo "  ./debug.sh run       # Full development cycle"
        echo "  ./debug.sh logs      # Just watch logs"
        echo "  ./debug.sh wireless  # Enable wireless debugging"
        ;;
esac
