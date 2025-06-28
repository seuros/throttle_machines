#!/bin/bash

# Server Startup Script for ThrottleMachines Testing
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PORT=${PORT:-3000}
ENVIRONMENT=${RAILS_ENV:-development}
LOG_DIR="$(pwd)/log"

echo -e "${BLUE}=== ThrottleMachines Test Server Startup ===${NC}"
echo "Environment: $ENVIRONMENT"
echo "Port: $PORT"
echo "Log directory: $LOG_DIR"
echo ""

# Create log directory
mkdir -p "$LOG_DIR"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Shutting down server...${NC}"
    if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
    fi
    exit 0
}

# Trap cleanup function on exit
trap cleanup SIGINT SIGTERM

# Check if bundle install is needed
if [ ! -f "Gemfile.lock" ] || [ "Gemfile" -nt "Gemfile.lock" ]; then
    echo -e "${YELLOW}Installing/updating gems...${NC}"
    bundle install
fi

# Clear old logs if requested
if [ "$1" = "--clear-logs" ] || [ "$1" = "-c" ]; then
    echo -e "${YELLOW}Clearing logs...${NC}"
    > "$LOG_DIR/development.log" 2>/dev/null || true
    > "$LOG_DIR/instrumentation.log" 2>/dev/null || true
    echo -e "${GREEN}✓ Logs cleared${NC}"
fi

# Show rate limit configuration
echo -e "${BLUE}Rate Limit Configuration:${NC}"
echo "/rate_limit_test      → 10 requests/min (token_bucket)"
echo "/api/rate_limit_test  → 5 requests/min (sliding_window)" 
echo "/rate_limit_status    → 20 requests/min (fixed_window)"
echo "/health               → 100 requests/min (token_bucket)"
echo "Other endpoints       → 30 requests/min (sliding_window)"
echo ""

# Check if port is already in use
if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}❌ Port $PORT is already in use${NC}"
    echo "Stop the existing server or use a different port with: PORT=3001 $0"
    exit 1
fi

echo -e "${GREEN}Starting Rails server on port $PORT...${NC}"
echo "Press Ctrl+C to stop the server"
echo ""

# Start the server
rails server -p $PORT -e $ENVIRONMENT &
SERVER_PID=$!

# Wait a moment for server to start
sleep 3

# Check if server started successfully
if ps -p $SERVER_PID > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Server started successfully (PID: $SERVER_PID)${NC}"
    echo ""
    echo -e "${BLUE}Available endpoints:${NC}"
    echo "Health check:         http://localhost:$PORT/health"
    echo "Rate limit test:      http://localhost:$PORT/rate_limit_test"  
    echo "API rate limit test:  http://localhost:$PORT/api/rate_limit_test"
    echo "Rate limit status:    http://localhost:$PORT/rate_limit_status"
    echo ""
    echo -e "${BLUE}Testing commands:${NC}"
    echo "Run Apache Bench tests:  ./test_rate_limiting_ab.sh"
    echo "Analyze logs:            ./analyze_instrumentation_log.rb"
    echo "Monitor logs:            tail -f log/instrumentation.log"
    echo ""
    echo -e "${YELLOW}Server is running... monitoring logs:${NC}"
    echo ""
    
    # Monitor the instrumentation log in real-time
    if [ -f "$LOG_DIR/instrumentation.log" ]; then
        tail -f "$LOG_DIR/instrumentation.log" &
        TAIL_PID=$!
    fi
    
    # Wait for server process
    wait $SERVER_PID
else
    echo -e "${RED}❌ Failed to start server${NC}"
    exit 1
fi