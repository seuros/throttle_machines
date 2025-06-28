# ThrottleMachines Rate Limiting Test Setup

This directory contains a comprehensive test setup for testing ThrottleMachines rate limiting functionality with instrumentation and Apache Bench load testing.

## Overview

The test setup includes:
1. **Instrumentation Configuration** - Logs all ThrottleMachines events to a file
2. **Rate Limit Configuration** - Different rate limits for different endpoints
3. **Apache Bench Test Scripts** - Automated load testing scenarios
4. **Log Analysis Tools** - Parse and analyze instrumentation events
5. **Server Management** - Easy server startup with monitoring

## Quick Start

### 1. Start the Test Server

```bash
# Start server with log monitoring
./start_server.sh

# Or start server and clear old logs
./start_server.sh --clear-logs
```

The server will start on port 3000 and begin monitoring instrumentation logs in real-time.

### 2. Run Apache Bench Tests (in another terminal)

```bash
# Run comprehensive rate limiting tests
./test_rate_limiting_ab.sh

# Clear logs before testing
./test_rate_limiting_ab.sh --clear-logs

# Show help
./test_rate_limiting_ab.sh --help
```

### 3. Analyze Results

```bash
# Analyze instrumentation events
./analyze_instrumentation_log.rb

# Verbose analysis
./analyze_instrumentation_log.rb -v

# Filter by event type
./analyze_instrumentation_log.rb -e rate_limit

# JSON output
./analyze_instrumentation_log.rb --json

# Monitor logs in real-time
tail -f log/instrumentation.log
```

## Rate Limit Configuration

The test setup configures different rate limits for different endpoints:

| Endpoint | Rate Limit | Algorithm | Purpose |
|----------|------------|-----------|---------|
| `/rate_limit_test` | 10 req/min | token_bucket | Basic endpoint testing |
| `/api/rate_limit_test` | 5 req/min | sliding_window | API endpoint (restrictive) |
| `/rate_limit_status` | 20 req/min | fixed_window | Status checking |
| `/health` | 100 req/min | token_bucket | Health checks (permissive) |
| Other endpoints | 30 req/min | sliding_window | Default rate limiting |

## Test Scenarios

The Apache Bench script runs several test scenarios:

### 1. Basic Rate Limiting Test
- **Target**: `/rate_limit_test` (10 req/min limit)
- **Test**: 15 sequential requests
- **Expected**: First 10 succeed, remaining 5 are rate limited

### 2. API Endpoint Test  
- **Target**: `/api/rate_limit_test` (5 req/min limit)
- **Test**: 8 sequential requests
- **Expected**: Rate limiting kicks in quickly

### 3. Concurrent Load Test
- **Target**: `/rate_limit_status` (20 req/min limit)
- **Test**: 25 requests with 2 concurrent connections
- **Expected**: Tests concurrent request handling

### 4. High Volume Test
- **Target**: `/health` (100 req/min limit)
- **Test**: 50 requests with 5 concurrent connections
- **Expected**: Most requests succeed due to high limit

### 5. Burst Test
- **Target**: `/rate_limit_test` 
- **Test**: 20 requests with 5 concurrent connections
- **Expected**: Tests burst handling and algorithm behavior

### 6. Mixed Load Test
- **Target**: Multiple endpoints simultaneously
- **Test**: Concurrent tests across different endpoints
- **Expected**: Independent rate limiting per endpoint

## Files and Scripts

### Configuration Files

- **`config/initializers/instrumentation.rb`** - Configures event logging to file
- **`config/initializers/throttle_machines.rb`** - Rate limit configuration

### Scripts

- **`start_server.sh`** - Start Rails server with monitoring
- **`test_rate_limiting_ab.sh`** - Apache Bench test suite
- **`analyze_instrumentation_log.rb`** - Log analysis tool

### Log Files

- **`log/instrumentation.log`** - JSON-formatted instrumentation events
- **`log/development.log`** - Standard Rails development log
- **`ab_results/`** - Apache Bench test result files

## Instrumentation Events

The setup captures these ThrottleMachines events:

### Rate Limiting Events
- **`rate_limit.checked`** - Every rate limit check
- **`rate_limit.allowed`** - Request allowed through
- **`rate_limit.throttled`** - Request rate limited

### Circuit Breaker Events (if configured)
- **`circuit_breaker.opened`** - Circuit opened due to failures
- **`circuit_breaker.closed`** - Circuit closed (healthy)
- **`circuit_breaker.half_opened`** - Circuit in half-open state
- **`circuit_breaker.success`** - Successful request through circuit
- **`circuit_breaker.failure`** - Failed request
- **`circuit_breaker.rejected`** - Request rejected (circuit open)

## Example Usage Workflows

### Workflow 1: Basic Rate Limiting Test

```bash
# Terminal 1: Start server
./start_server.sh --clear-logs

# Terminal 2: Run tests and analyze
./test_rate_limiting_ab.sh --clear-logs
./analyze_instrumentation_log.rb -v

# Monitor in real-time
tail -f log/instrumentation.log
```

### Workflow 2: Specific Endpoint Analysis

```bash
# Test only API endpoint
ab -c 1 -n 10 http://localhost:3000/api/rate_limit_test

# Analyze only API events
./analyze_instrumentation_log.rb -k api

# View timeline for API events
./analyze_instrumentation_log.rb -k api -v
```

### Workflow 3: Performance Analysis

```bash
# Run comprehensive tests
./test_rate_limiting_ab.sh

# Analyze performance metrics
./analyze_instrumentation_log.rb --json | jq '.events[].duration_ms' | sort -n

# Check burst patterns
./analyze_instrumentation_log.rb -v
```

## Log Analysis Features

The log analyzer provides:

### Summary Statistics
- Total events by type
- Time range analysis
- Event rate calculations

### Event Timeline
- Chronological event listing with icons
- Rate limit decisions (allowed/throttled)
- Key information per event

### Rate Limit Analysis
- Success/failure rates per endpoint
- Algorithm distribution
- Burst detection
- Throttling timeline

### Performance Metrics
- Response time statistics (min, max, avg)
- Percentile analysis (P95, P99)
- Duration distribution

## Troubleshooting

### Server Won't Start
```bash
# Check if port is in use
lsof -i :3000

# Use different port
PORT=3001 ./start_server.sh
```

### No Instrumentation Events
```bash
# Check if instrumentation is enabled
grep -n "instrumentation" config/initializers/throttle_machines.rb

# Verify log file exists
ls -la log/instrumentation.log
```

### Apache Bench Not Installed
```bash
# macOS
brew install httpd

# Ubuntu/Debian
sudo apt-get install apache2-utils
```

### Log Analysis Shows No Events
```bash
# Check log file format
head -5 log/instrumentation.log

# Verify JSON parsing
./analyze_instrumentation_log.rb -v
```

## Customization

### Adding New Test Scenarios

Edit `test_rate_limiting_ab.sh` and add new `run_ab_test` calls:

```bash
run_ab_test "/your/endpoint" 2 20 "Custom test description"
```

### Modifying Rate Limits

Edit `config/initializers/throttle_machines.rb`:

```ruby
when '/your/endpoint'
  {
    key: "custom:#{req.ip}",
    limit: 15,
    period: 60,
    algorithm: :token_bucket
  }
```

### Custom Log Analysis

The analyzer supports filtering and custom output:

```bash
# Filter by time (requires code modification)
# Filter by multiple criteria
./analyze_instrumentation_log.rb -e rate_limit -k api

# Export to JSON for custom processing
./analyze_instrumentation_log.rb --json > events.json
```

## Integration with CI/CD

The test setup can be integrated into CI/CD pipelines:

```bash
#!/bin/bash
# CI test script

# Start server in background
./start_server.sh &
SERVER_PID=$!

# Wait for server to start
sleep 5

# Run tests
./test_rate_limiting_ab.sh

# Analyze results
./analyze_instrumentation_log.rb --json > test_results.json

# Check for expected rate limiting
THROTTLED=$(./analyze_instrumentation_log.rb -e throttled --json | jq '.events | length')
if [ "$THROTTLED" -lt 5 ]; then
  echo "❌ Expected throttling events not found"
  exit 1
fi

# Cleanup
kill $SERVER_PID
echo "✅ Rate limiting tests passed"
```

This comprehensive test setup provides everything needed to test, monitor, and analyze ThrottleMachines rate limiting behavior in a realistic environment.