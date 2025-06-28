#!/bin/bash

# Apache Bench Test Script for ThrottleMachines Rate Limiting
# This script tests different endpoints with various rate limits

set -e

# Configuration
BASE_URL="http://localhost:3000"
LOG_DIR="$(pwd)/log"
RESULTS_DIR="$(pwd)/ab_results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create results directory
mkdir -p "$RESULTS_DIR"

echo -e "${BLUE}=== ThrottleMachines Apache Bench Testing ===${NC}"
echo "Base URL: $BASE_URL"
echo "Results directory: $RESULTS_DIR"
echo "Log directory: $LOG_DIR"
echo ""

# Function to run Apache Bench test
run_ab_test() {
    local endpoint="$1"
    local concurrent="$2"
    local requests="$3"
    local description="$4"
    local output_file="$RESULTS_DIR/ab_${endpoint//\//_}_c${concurrent}_n${requests}.txt"
    
    echo -e "${YELLOW}Testing: $description${NC}"
    echo "Endpoint: $BASE_URL$endpoint"
    echo "Concurrent: $concurrent, Requests: $requests"
    echo "Output: $output_file"
    
    # Run the test and capture output
    if ab -c "$concurrent" -n "$requests" -v 2 "$BASE_URL$endpoint" > "$output_file" 2>&1; then
        echo -e "${GREEN}✓ Test completed successfully${NC}"
        
        # Extract and display key metrics
        local success_rate=$(grep "Complete requests:" "$output_file" | awk '{print $3}')
        local failed_rate=$(grep "Failed requests:" "$output_file" | awk '{print $3}')
        local rps=$(grep "Requests per second:" "$output_file" | awk '{print $4}')
        
        echo "  Complete requests: $success_rate"
        echo "  Failed requests: $failed_rate"
        echo "  Requests per second: $rps"
        
        # Check for 429 responses (rate limited)
        local rate_limited=$(grep -c "429" "$output_file" || echo "0")
        if [ "$rate_limited" -gt 0 ]; then
            echo -e "  ${RED}Rate limited responses: $rate_limited${NC}"
        else
            echo "  Rate limited responses: $rate_limited"
        fi
    else
        echo -e "${RED}✗ Test failed${NC}"
    fi
    
    echo ""
    sleep 2 # Brief pause between tests
}

# Function to check if server is running
check_server() {
    echo -e "${BLUE}Checking if server is running...${NC}"
    if curl -s "$BASE_URL/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Server is running${NC}"
        return 0
    else
        echo -e "${RED}✗ Server is not responding${NC}"
        echo "Please start the server with: rails server -p 3000"
        return 1
    fi
}

# Function to clear instrumentation log
clear_logs() {
    echo -e "${BLUE}Clearing instrumentation logs...${NC}"
    if [ -f "$LOG_DIR/instrumentation.log" ]; then
        > "$LOG_DIR/instrumentation.log"
        echo -e "${GREEN}✓ Instrumentation log cleared${NC}"
    fi
    if [ -f "$LOG_DIR/development.log" ]; then
        > "$LOG_DIR/development.log"
        echo -e "${GREEN}✓ Development log cleared${NC}"
    fi
    echo ""
}

# Function to show current rate limit status
show_rate_limits() {
    echo -e "${BLUE}=== Configured Rate Limits ===${NC}"
    echo "/rate_limit_test      → 10 requests/min (token_bucket)"
    echo "/api/rate_limit_test  → 5 requests/min (sliding_window)"
    echo "/rate_limit_status    → 20 requests/min (fixed_window)"
    echo "/health               → 100 requests/min (token_bucket)"
    echo "Other endpoints       → 30 requests/min (sliding_window)"
    echo ""
}

# Main execution
main() {
    # Check if ab is installed
    if ! command -v ab &> /dev/null; then
        echo -e "${RED}Error: Apache Bench (ab) is not installed${NC}"
        echo "Install with: brew install httpd (macOS) or apt-get install apache2-utils (Ubuntu)"
        exit 1
    fi
    
    # Check if server is running
    if ! check_server; then
        exit 1
    fi
    
    # Show rate limits
    show_rate_limits
    
    # Clear logs if requested
    if [ "$1" = "--clear-logs" ] || [ "$1" = "-c" ]; then
        clear_logs
    fi
    
    echo -e "${BLUE}Starting rate limiting tests...${NC}"
    echo "Monitor instrumentation events with: tail -f $LOG_DIR/instrumentation.log"
    echo ""
    
    # Test 1: Basic endpoint - should hit rate limit
    run_ab_test "/rate_limit_test" 1 15 "Basic endpoint (10/min limit) - expect rate limiting"
    
    # Test 2: API endpoint - should hit rate limit quickly
    run_ab_test "/api/rate_limit_test" 1 8 "API endpoint (5/min limit) - expect rate limiting"
    
    # Test 3: Status endpoint - moderate load
    run_ab_test "/rate_limit_status" 2 25 "Status endpoint (20/min limit) - concurrent requests"
    
    # Test 4: Health endpoint - should mostly succeed
    run_ab_test "/health" 5 50 "Health endpoint (100/min limit) - high concurrency"
    
    # Test 5: Burst test on basic endpoint
    run_ab_test "/rate_limit_test" 5 20 "Basic endpoint - burst test (concurrent)"
    
    # Test 6: Mixed load test
    echo -e "${YELLOW}Running mixed load test...${NC}"
    echo "This will hit multiple endpoints simultaneously"
    
    # Run multiple ab commands in background for mixed load
    ab -c 2 -n 10 "$BASE_URL/rate_limit_test" > "$RESULTS_DIR/mixed_basic.txt" 2>&1 &
    ab -c 1 -n 6 "$BASE_URL/api/rate_limit_test" > "$RESULTS_DIR/mixed_api.txt" 2>&1 &
    ab -c 3 -n 15 "$BASE_URL/rate_limit_status" > "$RESULTS_DIR/mixed_status.txt" 2>&1 &
    
    # Wait for all background jobs to complete
    wait
    echo -e "${GREEN}✓ Mixed load test completed${NC}"
    echo ""
    
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "All Apache Bench tests completed!"
    echo "Results saved in: $RESULTS_DIR"
    echo ""
    echo "Next steps:"
    echo "1. Check instrumentation log: tail -f $LOG_DIR/instrumentation.log"
    echo "2. Analyze results with: ./analyze_instrumentation_log.rb"
    echo "3. View detailed AB results in: $RESULTS_DIR/"
    echo ""
    echo -e "${GREEN}Rate limiting test suite completed successfully!${NC}"
}

# Show help if requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --clear-logs    Clear instrumentation and development logs before testing"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "This script tests ThrottleMachines rate limiting using Apache Bench."
    echo "Make sure the Rails server is running on port 3000 before executing."
    echo ""
    echo "Endpoints tested:"
    echo "  /rate_limit_test      (10 req/min)"
    echo "  /api/rate_limit_test  (5 req/min)"
    echo "  /rate_limit_status    (20 req/min)"
    echo "  /health               (100 req/min)"
    exit 0
fi

# Run main function
main "$@"