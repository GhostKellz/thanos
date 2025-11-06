#!/bin/bash
# Thanos API Test Script
# Tests all endpoints for zeke integration

set -e

THANOS_URL="${THANOS_URL:-http://localhost:9000}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Thanos AI Gateway"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1: Health check
echo "✓ Test 1: Health Check"
curl -s $THANOS_URL/health | jq '{status, version, providers}'
echo ""

# Test 2: List providers
echo "✓ Test 2: List Providers"
curl -s $THANOS_URL/v1/providers | jq '.data[] | {id, model, auth_method}'
echo ""

# Test 3: List models (first 5)
echo "✓ Test 3: Available Models (first 5)"
curl -s $THANOS_URL/v1/models | jq '.data[0:5] | .[] | {id, provider, context_length}'
echo ""

# Test 4: Chat completion (non-streaming)
echo "✓ Test 4: Chat Completion (Gemini)"
curl -s -X POST $THANOS_URL/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemini-2.5-pro",
    "messages": [{"role": "user", "content": "Say: API TEST PASSED"}]
  }' | jq '{model, content: .choices[0].message.content, tokens: .usage}'
echo ""

# Test 5: Streaming (if provider supports it)
echo "✓ Test 5: Streaming Response"
echo "Request: Count to 3"
curl -N -s -X POST $THANOS_URL/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemini-2.5-pro",
    "messages": [{"role": "user", "content": "Count to 3"}],
    "stream": true
  }' 2>&1 | head -5
echo ""

# Test 6: Metrics
echo "✓ Test 6: Prometheus Metrics"
curl -s $THANOS_URL/metrics | grep "thanos_requests_total" | head -3
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All Tests Complete ✓"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
