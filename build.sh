#!/bin/bash

# Cross-platform build script for gllvm
# Builds binaries for multiple platforms and architectures

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Configuration
VERSION=${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo "dev")}
BUILD_DIR=${BUILD_DIR:-"./build"}
LDFLAGS="-X main.version=${VERSION} -s -w"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Platform/architecture combinations to build
declare -a PLATFORMS=(
    "linux/amd64"
    "linux/arm64"
    "linux/arm"
    "darwin/amd64"
    "darwin/arm64"
    "freebsd/amd64"
    "windows/amd64"
)

# List of binaries to build
declare -a BINARIES=(
    "gclang"
    "gclang++"
    "gflang"
    "get-bc"
    "gparse"
    "gsanity-check"
)

# Function to build a single binary for a single platform
build_binary() {
    local platform=$1
    local binary=$2
    local goos=$(echo $platform | cut -d'/' -f1)
    local goarch=$(echo $platform | cut -d'/' -f2)
    
    local output_name="${binary}"
    if [[ "$goos" == "windows" ]]; then
        output_name="${binary}.exe"
    fi
    
    local output_dir="${BUILD_DIR}/${goos}_${goarch}"
    local output_path="${output_dir}/${output_name}"
    
    log_info "Building ${binary} for ${goos}/${goarch}..."
    
    mkdir -p "${output_dir}"
    
    GOOS=$goos GOARCH=$goarch CGO_ENABLED=0 go build \
        -ldflags "$LDFLAGS" \
        -o "$output_path" \
        "./cmd/${binary}"
    
    if [[ $? -eq 0 ]]; then
        log_success "Built ${binary} -> ${output_path}"
    else
        log_error "Failed to build ${binary} for ${goos}/${goarch}"
        return 1
    fi
}

# Function to create archives
create_archive() {
    local platform=$1
    local goos=$(echo $platform | cut -d'/' -f1)
    local goarch=$(echo $platform | cut -d'/' -f2)
    
    local platform_dir="${BUILD_DIR}/${goos}_${goarch}"
    local archive_name="gllvm_${VERSION}_${goos}_${goarch}"
    
    if [[ ! -d "$platform_dir" ]]; then
        log_warn "Platform directory not found: $platform_dir"
        return 1
    fi
    
    log_info "Creating archive for ${goos}/${goarch}..."
    
    cd "$platform_dir"
    
    if [[ "$goos" == "windows" ]]; then
        # Create ZIP for Windows
        zip -q "../${archive_name}.zip" *.exe
        log_success "Created ${BUILD_DIR}/${archive_name}.zip"
    else
        # Create tar.gz for Unix-like systems
        tar -czf "../${archive_name}.tar.gz" *
        log_success "Created ${BUILD_DIR}/${archive_name}.tar.gz"
    fi
    
    cd - > /dev/null
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cross-platform build script for gllvm

Options:
    -h, --help              Show this help message
    -p, --platform PLATFORM Build only for specific platform (format: os/arch)
    -b, --binary BINARY     Build only specific binary
    -c, --clean             Clean build directory before building
    -a, --archives          Create archives after building
    -l, --list              List available platforms and binaries
    --no-compress           Skip binary compression (remove -s -w flags)
    
Environment Variables:
    VERSION                 Version string (default: git describe or 'dev')
    BUILD_DIR              Build output directory (default: './build')
    
Examples:
    $0                      # Build all binaries for all platforms
    $0 -p linux/arm64       # Build only for Linux ARM64
    $0 -b gclang            # Build only gclang for all platforms
    $0 -p linux/arm64 -b gclang # Build only gclang for Linux ARM64
    $0 -c -a                # Clean, build all, and create archives

EOF
}

# Function to list available options
list_options() {
    echo "Available platforms:"
    for platform in "${PLATFORMS[@]}"; do
        echo "  $platform"
    done
    
    echo ""
    echo "Available binaries:"
    for binary in "${BINARIES[@]}"; do
        echo "  $binary"
    done
}

# Parse command line arguments
CLEAN=false
ARCHIVES=false
SPECIFIC_PLATFORM=""
SPECIFIC_BINARY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--list)
            list_options
            exit 0
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -a|--archives)
            ARCHIVES=true
            shift
            ;;
        -p|--platform)
            SPECIFIC_PLATFORM="$2"
            shift 2
            ;;
        -b|--binary)
            SPECIFIC_BINARY="$2"
            shift 2
            ;;
        --no-compress)
            LDFLAGS="-X main.version=${VERSION}"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Clean build directory if requested
if [[ "$CLEAN" == "true" ]]; then
    log_info "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# Validate specific platform if provided
if [[ -n "$SPECIFIC_PLATFORM" ]]; then
    if [[ ! " ${PLATFORMS[@]} " =~ " ${SPECIFIC_PLATFORM} " ]]; then
        log_error "Invalid platform: $SPECIFIC_PLATFORM"
        log_info "Use --list to see available platforms"
        exit 1
    fi
fi

# Validate specific binary if provided
if [[ -n "$SPECIFIC_BINARY" ]]; then
    if [[ ! " ${BINARIES[@]} " =~ " ${SPECIFIC_BINARY} " ]]; then
        log_error "Invalid binary: $SPECIFIC_BINARY"
        log_info "Use --list to see available binaries"
        exit 1
    fi
fi

# Determine which platforms and binaries to build
PLATFORMS_TO_BUILD=("${PLATFORMS[@]}")
if [[ -n "$SPECIFIC_PLATFORM" ]]; then
    PLATFORMS_TO_BUILD=("$SPECIFIC_PLATFORM")
fi

BINARIES_TO_BUILD=("${BINARIES[@]}")
if [[ -n "$SPECIFIC_BINARY" ]]; then
    BINARIES_TO_BUILD=("$SPECIFIC_BINARY")
fi

# Main build loop
log_info "Starting build process..."
log_info "Version: $VERSION"
log_info "Build directory: $BUILD_DIR"
log_info "Platforms: ${#PLATFORMS_TO_BUILD[@]}"
log_info "Binaries: ${#BINARIES_TO_BUILD[@]}"

TOTAL_BUILDS=$((${#PLATFORMS_TO_BUILD[@]} * ${#BINARIES_TO_BUILD[@]}))
CURRENT_BUILD=0
FAILED_BUILDS=0

for platform in "${PLATFORMS_TO_BUILD[@]}"; do
    for binary in "${BINARIES_TO_BUILD[@]}"; do
        CURRENT_BUILD=$((CURRENT_BUILD + 1))
        echo ""
        log_info "Build ${CURRENT_BUILD}/${TOTAL_BUILDS}: ${binary} for ${platform}"
        
        if ! build_binary "$platform" "$binary"; then
            FAILED_BUILDS=$((FAILED_BUILDS + 1))
        fi
    done
done

# Create archives if requested
if [[ "$ARCHIVES" == "true" ]]; then
    echo ""
    log_info "Creating archives..."
    for platform in "${PLATFORMS_TO_BUILD[@]}"; do
        create_archive "$platform"
    done
fi

# Summary
echo ""
echo "================================"
log_info "Build Summary"
echo "================================"
log_info "Total builds attempted: $TOTAL_BUILDS"
log_success "Successful builds: $((TOTAL_BUILDS - FAILED_BUILDS))"
if [[ $FAILED_BUILDS -gt 0 ]]; then
    log_error "Failed builds: $FAILED_BUILDS"
else
    log_success "All builds completed successfully!"
fi

echo ""
log_info "Build artifacts are in: $BUILD_DIR"

# List build artifacts
if [[ -d "$BUILD_DIR" ]]; then
    echo ""
    log_info "Build artifacts:"
    find "$BUILD_DIR" -type f -name "*" | sort | while read -r file; do
        size=$(du -h "$file" | cut -f1)
        echo "  $file ($size)"
    done
fi

exit $FAILED_BUILDS