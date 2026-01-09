#!/bin/bash
# Comprehensive notebook testing script for local development and CI
# Usage: ./run_notebook_tests.sh [options]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NOTEBOOKS_DIR="$PROJECT_ROOT/notebooks"
TEST_OUTPUT_DIR="/tmp/notebook_tests_$(date +%Y%m%d_%H%M%S)"

# Default options
VERBOSE=false
PARALLEL=false
SPECIFIC_NOTEBOOK=""
GENERATE_REPORT=true
CLEANUP=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -p, --parallel          Run tests in parallel (experimental)
    -n, --notebook NAME     Test specific notebook only
    -o, --output-dir DIR    Custom output directory
    --no-report             Skip generating HTML report
    --no-cleanup            Keep temporary files after testing

Examples:
    $0                                          # Run all notebook tests
    $0 -v                                       # Run with verbose output
    $0 -n prometheus-metrics-collection.ipynb  # Test specific notebook
    $0 --parallel                               # Run tests in parallel

Environment Variables:
    NOTEBOOK_TEST_TIMEOUT   Default timeout for notebook execution (default: 300s)
    NOTEBOOK_TEST_MODE      Set to 'true' to enable test mode in notebooks
    SYNTHETIC_DATA_ONLY     Set to 'true' to use only synthetic data
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -p|--parallel)
            PARALLEL=true
            shift
            ;;
        -n|--notebook)
            SPECIFIC_NOTEBOOK="$2"
            shift 2
            ;;
        -o|--output-dir)
            TEST_OUTPUT_DIR="$2"
            shift 2
            ;;
        --no-report)
            GENERATE_REPORT=false
            shift
            ;;
        --no-cleanup)
            CLEANUP=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Setup environment
setup_environment() {
    print_status $BLUE "🔧 Setting up test environment..."

    # Create output directory
    mkdir -p "$TEST_OUTPUT_DIR"

    # Set environment variables for testing
    export NOTEBOOK_TEST_MODE=true
    export SYNTHETIC_DATA_ONLY=true
    export PYTHONPATH="$PROJECT_ROOT/notebooks/utils:$PYTHONPATH"

    # Check Python and dependencies
    if ! command -v python3 &> /dev/null; then
        print_status $RED "❌ Python 3 is required but not installed"
        exit 1
    fi

    # Install test dependencies if needed
    if ! python3 -c "import papermill" &> /dev/null; then
        print_status $YELLOW "📦 Installing test dependencies..."
        pip install -r "$SCRIPT_DIR/requirements.txt"
    fi

    print_status $GREEN "✅ Environment setup complete"
}

# Function to test a single notebook
test_notebook() {
    local notebook_path=$1
    local notebook_name=$(basename "$notebook_path")
    local output_path="$TEST_OUTPUT_DIR/test_${notebook_name}"

    print_status $BLUE "🧪 Testing: $notebook_name"

    if [ ! -f "$notebook_path" ]; then
        print_status $RED "❌ Notebook not found: $notebook_path"
        return 1
    fi

    # Set timeout
    local timeout=${NOTEBOOK_TEST_TIMEOUT:-300}

    # Execute notebook with papermill
    if $VERBOSE; then
        papermill "$notebook_path" "$output_path" \
            -p TEST_MODE true \
            -p SYNTHETIC_DATA_ONLY true \
            --execution-timeout $timeout \
            --kernel python3
    else
        papermill "$notebook_path" "$output_path" \
            -p TEST_MODE true \
            -p SYNTHETIC_DATA_ONLY true \
            --execution-timeout $timeout \
            --kernel python3 \
            > /dev/null 2>&1
    fi

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        print_status $GREEN "✅ $notebook_name: PASSED"
        return 0
    else
        print_status $RED "❌ $notebook_name: FAILED"
        return 1
    fi
}

# Function to run all tests
run_all_tests() {
    print_status $BLUE "🚀 Starting comprehensive notebook testing..."

    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    # Define notebooks to test
    local notebooks=(
        "$NOTEBOOKS_DIR/01-data-collection/prometheus-metrics-collection.ipynb"
        "$NOTEBOOKS_DIR/01-data-collection/openshift-events-analysis.ipynb"
        "$NOTEBOOKS_DIR/01-data-collection/log-parsing-analysis.ipynb"
        "$NOTEBOOKS_DIR/01-data-collection/feature-store-demo.ipynb"
        "$NOTEBOOKS_DIR/02-anomaly-detection/isolation-forest-implementation.ipynb"
    )

    # Filter for specific notebook if requested
    if [ -n "$SPECIFIC_NOTEBOOK" ]; then
        notebooks=()
        for notebook in "${notebooks[@]}"; do
            if [[ "$(basename "$notebook")" == "$SPECIFIC_NOTEBOOK" ]]; then
                notebooks=("$notebook")
                break
            fi
        done

        if [ ${#notebooks[@]} -eq 0 ]; then
            print_status $RED "❌ Notebook '$SPECIFIC_NOTEBOOK' not found"
            exit 1
        fi
    fi

    # Run tests
    for notebook in "${notebooks[@]}"; do
        if [ -f "$notebook" ]; then
            total_tests=$((total_tests + 1))

            if test_notebook "$notebook"; then
                passed_tests=$((passed_tests + 1))
            else
                failed_tests=$((failed_tests + 1))
            fi
        else
            print_status $YELLOW "⏭️ Skipping missing notebook: $(basename "$notebook")"
        fi
    done

    # Print summary
    print_status $BLUE "📊 Test Summary:"
    echo "  Total: $total_tests"
    echo "  Passed: $passed_tests"
    echo "  Failed: $failed_tests"

    if [ $failed_tests -eq 0 ]; then
        print_status $GREEN "🎉 All tests passed!"
        return 0
    else
        print_status $RED "❌ $failed_tests test(s) failed"
        return 1
    fi
}

# Function to generate comprehensive report
generate_report() {
    if [ "$GENERATE_REPORT" = false ]; then
        return 0
    fi

    print_status $BLUE "📋 Generating comprehensive test report..."

    # Run Python-based comprehensive testing
    cd "$SCRIPT_DIR"
    python notebook_tests.py

    if [ -f "notebook_test_report.json" ]; then
        print_status $GREEN "✅ Comprehensive report generated: notebook_test_report.json"
    else
        print_status $YELLOW "⚠️ Comprehensive report generation failed"
    fi
}

# Cleanup function
cleanup() {
    if [ "$CLEANUP" = true ]; then
        print_status $BLUE "🧹 Cleaning up temporary files..."
        # Keep the main output directory but clean up any temp files
        find "$TEST_OUTPUT_DIR" -name "*.tmp" -delete 2>/dev/null || true
    fi
}

# Main execution
main() {
    print_status $BLUE "🧪 OpenShift AIOps Platform - Notebook Testing Suite"
    print_status $BLUE "=================================================="

    setup_environment

    # Run tests
    if run_all_tests; then
        generate_report
        cleanup
        print_status $GREEN "🎉 Notebook testing completed successfully!"
        exit 0
    else
        generate_report
        cleanup
        print_status $RED "❌ Notebook testing failed!"
        exit 1
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
