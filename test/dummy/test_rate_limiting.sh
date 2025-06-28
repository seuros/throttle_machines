#!/bin/bash

echo "ThrottleMachines Rate Limiting Test with Apache Bench"
echo "====================================================="
echo ""
echo "Make sure the Rails server is running in another terminal:"
echo "  cd test/dummy && bin/rails server"
echo ""
echo "Press Enter when the server is running..."
read

# Test 1: Basic rate limiting (100 requests/minute per IP)
echo "Test 1: Testing basic rate limiting (100 req/min)"
echo "Sending 110 requests to /rate_limit_test..."
ab -n 110 -c 1 http://localhost:3000/rate_limit_test

echo ""
echo "Check the server logs for 429 responses after 100 requests!"
echo ""

# Test 2: Payment endpoint (10 requests/minute)
echo "Test 2: Testing payment endpoint (10 req/min)"
echo "Sending 15 requests to /test/payment..."
ab -n 15 -c 1 http://localhost:3000/test/payment

echo ""
echo "Check the server logs for 429 responses after 10 requests!"
echo ""

# Test 3: API endpoint (1000 requests/hour)
echo "Test 3: Testing API endpoint (1000 req/hour)"
echo "Sending 50 concurrent requests to /api/rate_limit_test..."
ab -n 50 -c 10 http://localhost:3000/api/rate_limit_test

echo ""
echo "All requests should succeed (under the 1000/hour limit)"
echo ""

# Test 4: Concurrent requests
echo "Test 4: Testing concurrent requests"
echo "Sending 200 requests with 20 concurrent connections..."
ab -n 200 -c 20 http://localhost:3000/rate_limit_test

echo ""
echo "Should see 429 errors after 100 successful requests"