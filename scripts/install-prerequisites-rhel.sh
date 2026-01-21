#!/bin/bash
# =============================================================================
# install-prerequisites-rhel.sh
# =============================================================================
# Installs all prerequisites for the OpenShift AI Ops Self-Healing Platform
# on RHEL 9 or RHEL 10 workstations.
#
# This script is idempotent - safe to run multiple times.
#
# Usage:
#   ./scripts/install-prerequisites-rhel.sh
#
# What gets installed:
#   - System packages: podman, git, make, jq, python3-pip, development headers
#   - Python packages: ansible-navigator, ansible-builder, kubernetes, openshift-client
#   - Ansible collections: kubernetes.core, community.general, ansible.posix
#   - CLI tools: oc, kubectl, helm, yq, tkn
#
# Requirements:
#   - RHEL 9.x or RHEL 10.x
#   - sudo access
#   - Internet connectivity
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Versions (update as needed)
OC_VERSION="${OC_VERSION:-4.18}"
HELM_VERSION="${HELM_VERSION:-v3.16.4}"
YQ_VERSION="${YQ_VERSION:-v4.44.6}"
TKN_VERSION="${TKN_VERSION:-0.38.1}"

# Virtual environment location
VENV_DIR="${VENV_DIR:-$HOME/.venv/aiops-platform}"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

check_rhel_version() {
    log_info "Checking RHEL version..."
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found. This script requires RHEL 9 or 10."
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "rhel" ]]; then
        log_warn "Detected OS: $ID $VERSION_ID (not RHEL)"
        log_warn "This script is designed for RHEL 9/10 but may work on compatible systems (Fedora, CentOS Stream)"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    RHEL_MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
    
    if [[ "$RHEL_MAJOR_VERSION" -lt 9 ]]; then
        log_error "RHEL $VERSION_ID detected. This script requires RHEL 9 or later."
        exit 1
    fi
    
    log_success "Detected: $PRETTY_NAME"
    export RHEL_MAJOR_VERSION
}

check_sudo() {
    log_info "Checking sudo access..."
    if sudo -n true 2>/dev/null; then
        log_success "sudo access confirmed"
    else
        log_warn "sudo access required. You may be prompted for your password."
        sudo true || { log_error "Failed to obtain sudo access"; exit 1; }
    fi
}

check_internet() {
    log_info "Checking internet connectivity..."
    if curl -s --connect-timeout 5 https://mirror.openshift.com > /dev/null; then
        log_success "Internet connectivity confirmed"
    else
        log_error "Cannot reach mirror.openshift.com. Please check your internet connection."
        exit 1
    fi
}

# =============================================================================
# System Packages Installation
# =============================================================================

install_system_packages() {
    log_info "Installing system packages via dnf..."
    
    local packages=(
        # Core tools
        podman
        skopeo
        git
        make
        jq
        rsync
        unzip
        tar
        curl
        wget
        # Python
        python3
        python3-pip
        python3-devel
        # Development headers (needed for some Python packages)
        gcc
        gcc-c++
        openssl-devel
        libcurl-devel
        openldap-devel
        libpq-devel
        # Text processing
        gettext  # provides envsubst
    )
    
    log_info "Packages to install: ${packages[*]}"
    
    sudo dnf install -y "${packages[@]}"
    
    log_success "System packages installed"
}

# =============================================================================
# Python Virtual Environment
# =============================================================================

setup_python_venv() {
    log_info "Setting up Python virtual environment at $VENV_DIR..."
    
    if [[ -d "$VENV_DIR" ]]; then
        log_info "Virtual environment already exists, updating..."
    else
        python3 -m venv "$VENV_DIR"
        log_success "Created virtual environment at $VENV_DIR"
    fi
    
    # Activate and upgrade pip
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip wheel setuptools
    
    log_success "Python virtual environment ready"
}

install_python_packages() {
    log_info "Installing Python packages..."
    
    # Ensure we're in the venv
    source "$VENV_DIR/bin/activate"
    
    # Core Ansible tools
    pip install --upgrade \
        'ansible-navigator[ansible-core]' \
        ansible-builder \
        ansible-lint \
        molecule
    
    # Additional useful tools
    pip install --upgrade \
        kubernetes \
        openshift-client \
        jmespath \
        netaddr
    
    log_success "Python packages installed"
}

install_ansible_collections() {
    log_info "Installing Ansible collections..."
    
    # Ensure we're in the venv
    source "$VENV_DIR/bin/activate"
    
    # Install required Ansible collections
    ansible-galaxy collection install kubernetes.core --force
    ansible-galaxy collection install community.general --force
    ansible-galaxy collection install ansible.posix --force
    
    # Verify installation
    if ansible-galaxy collection list | grep -q "kubernetes.core"; then
        log_success "kubernetes.core collection installed"
    else
        log_error "Failed to install kubernetes.core collection"
        exit 1
    fi
    
    log_success "Ansible collections installed"
}

# =============================================================================
# CLI Tools Installation
# =============================================================================

install_oc_cli() {
    log_info "Installing OpenShift CLI (oc) version $OC_VERSION..."
    
    if check_command oc; then
        local current_version
        current_version=$(oc version --client 2>/dev/null | grep -oP 'Client Version: \K[0-9.]+' || echo "unknown")
        log_info "oc already installed (version: $current_version)"
        read -p "Reinstall/upgrade? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_success "Keeping existing oc installation"
            return 0
        fi
    fi
    
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    
    # Download from mirror.openshift.com (no subscription required)
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac
    
    local url="https://mirror.openshift.com/pub/openshift-v4/${arch}/clients/ocp/stable-${OC_VERSION}/openshift-client-linux.tar.gz"
    log_info "Downloading from: $url"
    
    curl -sSL "$url" -o openshift-client.tar.gz
    tar -xzf openshift-client.tar.gz
    
    sudo mv oc kubectl /usr/local/bin/
    sudo chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
    
    cd - > /dev/null
    rm -rf "$tmp_dir"
    
    log_success "oc and kubectl installed to /usr/local/bin/"
    oc version --client
}

install_helm() {
    log_info "Installing Helm version $HELM_VERSION..."
    
    if check_command helm; then
        local current_version
        current_version=$(helm version --short 2>/dev/null | grep -oP 'v[0-9.]+' || echo "unknown")
        log_info "helm already installed (version: $current_version)"
        read -p "Reinstall/upgrade? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_success "Keeping existing helm installation"
            return 0
        fi
    fi
    
    # Use official Helm install script
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | \
        DESIRED_VERSION="$HELM_VERSION" bash
    
    log_success "Helm installed"
    helm version --short
}

install_yq() {
    log_info "Installing yq version $YQ_VERSION..."
    
    if check_command yq; then
        local current_version
        current_version=$(yq --version 2>/dev/null | grep -oP 'v[0-9.]+' || echo "unknown")
        log_info "yq already installed (version: $current_version)"
        read -p "Reinstall/upgrade? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_success "Keeping existing yq installation"
            return 0
        fi
    fi
    
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac
    
    local url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}"
    log_info "Downloading from: $url"
    
    sudo curl -sSL "$url" -o /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
    
    log_success "yq installed to /usr/local/bin/"
    yq --version
}

install_tkn() {
    log_info "Installing Tekton CLI (tkn) version $TKN_VERSION..."
    
    if check_command tkn; then
        local current_version
        current_version=$(tkn version 2>/dev/null | grep -oP 'Client version: \K[0-9.]+' || echo "unknown")
        log_info "tkn already installed (version: $current_version)"
        read -p "Reinstall/upgrade? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_success "Keeping existing tkn installation"
            return 0
        fi
    fi
    
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac
    
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    
    local url="https://github.com/tektoncd/cli/releases/download/v${TKN_VERSION}/tkn_${TKN_VERSION}_Linux_${arch}.tar.gz"
    log_info "Downloading from: $url"
    
    curl -sSL "$url" -o tkn.tar.gz
    tar -xzf tkn.tar.gz
    
    sudo mv tkn /usr/local/bin/
    sudo chmod +x /usr/local/bin/tkn
    
    cd - > /dev/null
    rm -rf "$tmp_dir"
    
    log_success "tkn installed to /usr/local/bin/"
    tkn version
}

# =============================================================================
# Shell Configuration
# =============================================================================

configure_shell() {
    log_info "Configuring shell environment..."
    
    local shell_rc
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    local marker="# OpenShift AI Ops Platform Prerequisites"
    
    if grep -q "$marker" "$shell_rc" 2>/dev/null; then
        log_info "Shell configuration already present in $shell_rc"
    else
        cat >> "$shell_rc" << EOF

$marker
# Activate Python virtual environment
if [[ -d "$VENV_DIR" ]]; then
    source "$VENV_DIR/bin/activate"
fi

# Ensure /usr/local/bin is in PATH
export PATH="/usr/local/bin:\$PATH"

# oc/kubectl completion (optional, uncomment to enable)
# source <(oc completion bash)
# source <(kubectl completion bash)
# source <(helm completion bash)
EOF
        log_success "Added configuration to $shell_rc"
    fi
    
    log_warn "Run 'source $shell_rc' or start a new terminal to activate changes"
}

# =============================================================================
# Validation
# =============================================================================

validate_installation() {
    log_info "Validating installation..."
    echo
    
    local all_ok=true
    local tools=("podman" "git" "make" "jq" "oc" "kubectl" "helm" "yq" "tkn")
    
    printf "%-20s %-15s %-30s\n" "Tool" "Status" "Version"
    printf "%-20s %-15s %-30s\n" "----" "------" "-------"
    
    for tool in "${tools[@]}"; do
        if check_command "$tool"; then
            local version
            case "$tool" in
                podman)   version=$(podman --version 2>/dev/null | head -1) ;;
                git)      version=$(git --version 2>/dev/null) ;;
                make)     version=$(make --version 2>/dev/null | head -1) ;;
                jq)       version=$(jq --version 2>/dev/null) ;;
                oc)       version=$(oc version --client 2>/dev/null | grep "Client" | head -1) ;;
                kubectl)  version=$(kubectl version --client 2>/dev/null | grep "Client" | head -1 || kubectl version --client --short 2>/dev/null) ;;
                helm)     version=$(helm version --short 2>/dev/null) ;;
                yq)       version=$(yq --version 2>/dev/null) ;;
                tkn)      version=$(tkn version 2>/dev/null | grep "Client" | head -1) ;;
                *)        version="installed" ;;
            esac
            printf "%-20s ${GREEN}%-15s${NC} %-30s\n" "$tool" "✓ OK" "${version:0:40}"
        else
            printf "%-20s ${RED}%-15s${NC} %-30s\n" "$tool" "✗ MISSING" "-"
            all_ok=false
        fi
    done
    
    echo
    
    # Check Python packages in venv
    if [[ -d "$VENV_DIR" ]]; then
        source "$VENV_DIR/bin/activate"
        
        local py_tools=("ansible-navigator" "ansible-builder" "ansible-lint")
        for tool in "${py_tools[@]}"; do
            if check_command "$tool"; then
                local version
                version=$($tool --version 2>/dev/null | head -1 || echo "installed")
                printf "%-20s ${GREEN}%-15s${NC} %-30s\n" "$tool" "✓ OK" "${version:0:40}"
            else
                printf "%-20s ${RED}%-15s${NC} %-30s\n" "$tool" "✗ MISSING" "-"
                all_ok=false
            fi
        done
    else
        log_warn "Python virtual environment not found at $VENV_DIR"
        all_ok=false
    fi
    
    echo
    
    # Check Ansible collections
    if [[ -d "$VENV_DIR" ]]; then
        source "$VENV_DIR/bin/activate"
        
        local collections=("kubernetes.core" "community.general" "ansible.posix")
        for collection in "${collections[@]}"; do
            if ansible-galaxy collection list 2>/dev/null | grep -q "$collection"; then
                printf "%-20s ${GREEN}%-15s${NC} %-30s\n" "$collection" "✓ OK" "Ansible collection"
            else
                printf "%-20s ${RED}%-15s${NC} %-30s\n" "$collection" "✗ MISSING" "Ansible collection"
                all_ok=false
            fi
        done
    fi
    
    echo
    
    if $all_ok; then
        log_success "All prerequisites installed successfully!"
        return 0
    else
        log_error "Some prerequisites are missing. Please review the output above."
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "============================================================================="
    echo " OpenShift AI Ops Platform - Prerequisites Installer for RHEL 9/10"
    echo "============================================================================="
    echo
    
    # Pre-flight checks
    check_rhel_version
    check_sudo
    check_internet
    
    echo
    echo "============================================================================="
    echo " Installing Prerequisites"
    echo "============================================================================="
    echo
    
    # System packages
    install_system_packages
    
    # Python environment
    setup_python_venv
    install_python_packages
    install_ansible_collections
    
    # CLI tools
    install_oc_cli
    install_helm
    install_yq
    install_tkn
    
    # Shell configuration
    configure_shell
    
    echo
    echo "============================================================================="
    echo " Validation"
    echo "============================================================================="
    echo
    
    validate_installation
    
    echo
    echo "============================================================================="
    echo " Next Steps"
    echo "============================================================================="
    echo
    log_info "1. Start a new terminal or run: source ~/.bashrc"
    log_info "2. Log into your OpenShift cluster: oc login <cluster-url>"
    log_info "3. Get your Ansible Hub token from: https://console.redhat.com/ansible/automation-hub/token"
    log_info "4. Continue with deployment:"
    echo
    echo "   export ANSIBLE_HUB_TOKEN='your-token-here'"
    echo "   make token"
    echo "   make build-ee"
    echo "   make check-prerequisites"
    echo "   make operator-deploy"
    echo
    log_success "Prerequisites installation complete!"
}

# Run main function
main "$@"
