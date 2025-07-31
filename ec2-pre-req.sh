#!/bin/bash

# Multi-Distribution Prerequisites Installation Script for GCP Pub/Sub Monitoring
# Supports: Amazon Linux 2, Amazon Linux 2023, Ubuntu, RHEL/CentOS

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    log_info "Detected OS: $OS $VERSION"
    
    # Set package manager and python package names
    case $OS in
        "amzn")
            if [[ $VERSION == "2" ]]; then
                PKG_MANAGER="yum"
                PYTHON_PKG="python39"
                PYTHON_CMD="python3.9"
                OS_NAME="Amazon Linux 2"
            else
                PKG_MANAGER="yum"
                PYTHON_PKG="python3"
                PYTHON_CMD="python3"
                OS_NAME="Amazon Linux 2023"
            fi
            ;;
        "ubuntu")
            PKG_MANAGER="apt"
            PYTHON_PKG="python3.9"
            PYTHON_CMD="python3.9"
            OS_NAME="Ubuntu"
            ;;
        "rhel"|"centos"|"rocky"|"almalinux")
            if [[ $VERSION_ID =~ ^[89] ]]; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            PYTHON_PKG="python39"
            PYTHON_CMD="python3.9"
            OS_NAME=$OS
            ;;
        *)
            log_warning "Unsupported OS: $OS. Attempting with yum..."
            PKG_MANAGER="yum"
            PYTHON_PKG="python39"
            PYTHON_CMD="python3.9"
            OS_NAME="Unknown"
            ;;
    esac
    
    log_success "OS Configuration: $OS_NAME, Package Manager: $PKG_MANAGER, Python: $PYTHON_CMD"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    
    case $PKG_MANAGER in
        "yum")
            yum update -y >/dev/null 2>&1
            ;;
        "dnf")
            dnf update -y >/dev/null 2>&1
            ;;
        "apt")
            apt update >/dev/null 2>&1
            apt upgrade -y >/dev/null 2>&1
            ;;
    esac
    
    log_success "System packages updated"
}

# Install basic dependencies
install_basic_deps() {
    log_info "Installing basic dependencies..."
    
    local packages=("curl" "wget" "which" "tar" "gzip")
    
    # Add jq - different package names on different systems
    case $PKG_MANAGER in
        "apt")
            packages+=("jq")
            ;;
        *)
            packages+=("jq")
            ;;
    esac
    
    for package in "${packages[@]}"; do
        if ! command -v "$package" >/dev/null 2>&1; then
            log_info "Installing $package..."
            case $PKG_MANAGER in
                "yum")
                    yum install -y "$package" >/dev/null 2>&1
                    ;;
                "dnf")
                    dnf install -y "$package" >/dev/null 2>&1
                    ;;
                "apt")
                    apt install -y "$package" >/dev/null 2>&1
                    ;;
            esac
        else
            log_info "$package already installed"
        fi
    done
    
    log_success "Basic dependencies installed"
}

# Install compatible Python version
install_python() {
    log_info "Installing compatible Python version..."
    
    # Check if we already have a compatible Python
    for py_version in python3.12 python3.11 python3.10 python3.9; do
        if command -v "$py_version" >/dev/null 2>&1; then
            PYTHON_CMD="$py_version"
            log_success "Compatible Python found: $PYTHON_CMD"
            return 0
        fi
    done
    
    log_info "Installing $PYTHON_PKG..."
    
    case $PKG_MANAGER in
        "yum")
            # Amazon Linux 2 specific
            if [[ $OS == "amzn" && $VERSION == "2" ]]; then
                amazon-linux-extras install python3.8 -y >/dev/null 2>&1 || true
                yum install -y python39 >/dev/null 2>&1 || yum install -y python38 >/dev/null 2>&1
                # Try to find the installed Python
                for py_cmd in python3.9 python3.8 python3; do
                    if command -v "$py_cmd" >/dev/null 2>&1; then
                        PYTHON_CMD="$py_cmd"
                        break
                    fi
                done
            else
                yum install -y "$PYTHON_PKG" >/dev/null 2>&1
            fi
            ;;
        "dnf")
            dnf install -y "$PYTHON_PKG" >/dev/null 2>&1
            ;;
        "apt")
            # Ubuntu specific
            apt install -y software-properties-common >/dev/null 2>&1
            add-apt-repository ppa:deadsnakes/ppa -y >/dev/null 2>&1 || true
            apt update >/dev/null 2>&1
            apt install -y python3.9 python3.9-venv python3.9-pip >/dev/null 2>&1
            PYTHON_CMD="python3.9"
            ;;
    esac
    
    # Verify Python installation
    if command -v "$PYTHON_CMD" >/dev/null 2>&1; then
        local py_version=$($PYTHON_CMD --version 2>&1 | cut -d' ' -f2)
        log_success "Python installed: $PYTHON_CMD (version $py_version)"
    else
        log_error "Failed to install compatible Python version"
        return 1
    fi
}

# Install Google Cloud SDK with proper Python
install_gcloud_sdk() {
    log_info "Installing Google Cloud SDK..."
    
    local gcloud_path="/opt/google-cloud-sdk/bin/gcloud"
    
    # Remove any existing broken installation
    if [ -d "/opt/google-cloud-sdk" ]; then
        log_info "Removing existing installation..."
        rm -rf /opt/google-cloud-sdk
    fi
    
    # Install gcloud using the official installer
    log_info "Downloading and installing Google Cloud SDK..."
    cd /tmp
    
    # Use the official installer
    curl -s https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=/opt >/dev/null 2>&1
    
    # Set proper permissions
    chown -R root:root /opt/google-cloud-sdk
    chmod -R 755 /opt/google-cloud-sdk
    
    # Set Python path for gcloud
    log_info "Configuring gcloud to use compatible Python..."
    local python_path=$(which $PYTHON_CMD)
    
    # Create environment file for gcloud
    cat > /opt/google-cloud-sdk/gcloud_env << EOF
export CLOUDSDK_PYTHON=$python_path
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
export CLOUDSDK_INSTALL_DIR=/opt/google-cloud-sdk
EOF
    
    # Create wrapper script
    cat > /opt/google-cloud-sdk/bin/gcloud_wrapper << EOF
#!/bin/bash
source /opt/google-cloud-sdk/gcloud_env
exec /opt/google-cloud-sdk/bin/gcloud "\$@"
EOF
    chmod +x /opt/google-cloud-sdk/bin/gcloud_wrapper
    
    # Configure gcloud with proper Python
    CLOUDSDK_PYTHON=$python_path /opt/google-cloud-sdk/bin/gcloud config set disable_usage_reporting true >/dev/null 2>&1
    CLOUDSDK_PYTHON=$python_path /opt/google-cloud-sdk/bin/gcloud config set survey/disable_prompts true >/dev/null 2>&1
    CLOUDSDK_PYTHON=$python_path /opt/google-cloud-sdk/bin/gcloud config set core/disable_prompts true >/dev/null 2>&1
    
    # Verify installation
    if CLOUDSDK_PYTHON=$python_path /opt/google-cloud-sdk/bin/gcloud --version >/dev/null 2>&1; then
        log_success "✅ Google Cloud SDK installed successfully"
        CLOUDSDK_PYTHON=$python_path /opt/google-cloud-sdk/bin/gcloud --version | head -1
    else
        log_error "❌ Google Cloud SDK installation failed"
        return 1
    fi
}

# Create gcloud symlink and environment setup
create_gcloud_symlink() {
    log_info "Creating gcloud symlink and environment setup..."
    
    # Create symlink to wrapper script
    if [ -f "/usr/local/bin/gcloud" ]; then
        rm -f /usr/local/bin/gcloud
    fi
    ln -s /opt/google-cloud-sdk/bin/gcloud_wrapper /usr/local/bin/gcloud
    
    # Create system-wide environment file
    cat > /etc/profile.d/gcloud.sh << EOF
export CLOUDSDK_PYTHON=$(which $PYTHON_CMD)
export PATH="/opt/google-cloud-sdk/bin:\$PATH"
EOF
    chmod +x /etc/profile.d/gcloud.sh
    
    log_success "Created gcloud symlink and environment setup"
}

# Set up directories
setup_directories() {
    log_info "Setting up directories..."
    
    # Create directories with proper permissions
    mkdir -p /opt/appdynamics
    mkdir -p /tmp
    
    # Set permissions
    chmod 755 /opt/appdynamics
    chmod 1777 /tmp  # Sticky bit for /tmp
    
    log_success "Directories configured"
}

# Test installations
test_installations() {
    log_info "Testing installations..."
    
    local errors=0
    local python_path=$(which $PYTHON_CMD)
    
    # Test gcloud with proper Python
    if CLOUDSDK_PYTHON=$python_path /opt/google-cloud-sdk/bin/gcloud --version >/dev/null 2>&1; then
        log_success "✅ gcloud working"
    else
        log_error "❌ gcloud not working"
        errors=$((errors + 1))
    fi
    
    # Test wrapper script
    if /usr/local/bin/gcloud --version >/dev/null 2>&1; then
        log_success "✅ gcloud wrapper working"
    else
        log_error "❌ gcloud wrapper not working"
        errors=$((errors + 1))
    fi
    
    # Test Python
    if $PYTHON_CMD --version >/dev/null 2>&1; then
        log_success "✅ $PYTHON_CMD working"
    else
        log_error "❌ $PYTHON_CMD not working"
        errors=$((errors + 1))
    fi
    
    # Test jq
    if command -v jq >/dev/null 2>&1; then
        log_success "✅ jq working"
    else
        log_error "❌ jq not working"
        errors=$((errors + 1))
    fi
    
    # Test curl
    if command -v curl >/dev/null 2>&1; then
        log_success "✅ curl working"
    else
        log_error "❌ curl not working"
        errors=$((errors + 1))
    fi
    
    # Test basic commands
    local commands=("which" "tar" "gzip" "awk" "sed" "grep")
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "✅ $cmd working"
        else
            log_error "❌ $cmd not working"
            errors=$((errors + 1))
        fi
    done
    
    return $errors
}

# Show final status
show_final_status() {
    echo ""
    echo "🎉 Prerequisites Installation Complete!"
    echo "======================================"
    echo ""
    echo "✅ Installed Components:"
    echo "   • Operating System: $OS_NAME"
    echo "   • Package Manager: $PKG_MANAGER"
    echo "   • Python: $(which $PYTHON_CMD) ($($PYTHON_CMD --version 2>&1))"
    echo "   • Google Cloud SDK: /opt/google-cloud-sdk"
    echo "   • gcloud command: /opt/google-cloud-sdk/bin/gcloud"
    echo "   • gcloud wrapper: /usr/local/bin/gcloud"
    echo "   • jq: $(which jq)"
    echo "   • curl: $(which curl)"
    echo ""
    echo "📋 Versions:"
    local python_path=$(which $PYTHON_CMD)
    echo "   • gcloud: $(CLOUDSDK_PYTHON=$python_path /opt/google-cloud-sdk/bin/gcloud --version | head -1)"
    echo "   • jq: $(jq --version)"
    echo "   • curl: $(curl --version | head -1)"
    echo ""
    echo "🔧 Environment Setup:"
    echo "   • CLOUDSDK_PYTHON set to: $python_path"
    echo "   • Environment file: /etc/profile.d/gcloud.sh"
    echo "   • gcloud config: disable prompts and reporting"
    echo ""
    echo "🚀 Ready for Metrics Collector!"
    echo "   You can now run your metrics collection script."
    echo "   All prerequisites are installed and configured."
    echo ""
    echo "💡 Next Steps:"
    echo "   1. Update your metrics collector script with credentials"
    echo "   2. Run your metrics collector script"
    echo "   3. Script will use: CLOUDSDK_PYTHON=$python_path /opt/google-cloud-sdk/bin/gcloud"
}

# Main execution
main() {
    echo "=============================================="
    echo "Multi-Distribution GCP Pub/Sub Prerequisites"
    echo "=============================================="
    echo ""
    
    check_root
    detect_os
    update_system
    install_basic_deps
    install_python
    install_gcloud_sdk
    create_gcloud_symlink
    setup_directories
    
    echo ""
    log_info "Running installation tests..."
    if test_installations; then
        show_final_status
        echo ""
        log_success "🎉 All prerequisites installed successfully!"
        exit 0
    else
        echo ""
        log_error "❌ Some installations failed. Check the errors above."
        exit 1
    fi
}

# Handle interruption
trap 'echo ""; log_error "Installation interrupted"; exit 1' INT TERM

# Show help if requested
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    echo "Multi-Distribution GCP Pub/Sub Prerequisites Installation Script"
    echo ""
    echo "Supported Operating Systems:"
    echo "  • Amazon Linux 2"
    echo "  • Amazon Linux 2023"
    echo "  • Ubuntu 18.04/20.04/22.04"
    echo "  • RHEL/CentOS 7/8/9"
    echo "  • Rocky Linux / AlmaLinux"
    echo ""
    echo "This script installs:"
    echo "  • Compatible Python version (3.9+)"
    echo "  • Google Cloud SDK (gcloud) with proper Python configuration"
    echo "  • jq (JSON processor)"
    echo "  • curl, wget, tar, gzip"
    echo "  • Creates necessary directories"
    echo "  • Sets up environment variables"
    echo ""
    echo "Usage: sudo $0"
    echo ""
    echo "Requirements:"
    echo "  • Must run as root (use sudo)"
    echo "  • Internet connection required"
    echo ""
    echo "After running this script, you can use the metrics collector script."
    exit 0
fi

# Run main function
main "$@"