#!/bin/bash
set -e

echo "=== Gemini API Integration Test ==="
echo

# Get API key from .env
source .env

# Test 1: Direct Gemini API call
echo "✓ Test 1: Direct Gemini API (gemini-2.5-pro)"
curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=${GEMINI_API_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{"contents":[{"parts":[{"text":"Say only: API WORKS"}],"role":"user"}]}' | jq -r '.candidates[0].content.parts[0].text'
echo

# Test 2: Through Thanos gateway
echo "✓ Test 2: Through Thanos Gateway"
curl -s -X POST http://localhost:9000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"gemini-2.5-pro","messages":[{"role":"user","content":"Say only: GATEWAY WORKS"}],"max_tokens":10}' | jq -r '.content // .error'
echo

echo "=== Tests Complete ==="
