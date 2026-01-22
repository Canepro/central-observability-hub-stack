#!/bin/bash
# Test script to verify Jenkins authentication and CSRF token

JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
JENKINS_USER="${JENKINS_USER:-admin}"

# Get password
if [ -z "${JENKINS_PASSWORD:-}" ]; then
  echo "Getting password from Kubernetes secret..."
  JENKINS_PASSWORD=$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
fi

if [ -z "$JENKINS_PASSWORD" ]; then
  echo "Enter Jenkins password:"
  read -rs JENKINS_PASSWORD
fi

echo "Testing authentication..."
echo "================================"

# Test 1: Basic auth
echo "1. Testing basic authentication..."
AUTH_TEST=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/api/json")
echo "   HTTP Status: $AUTH_TEST"

if [ "$AUTH_TEST" != "200" ]; then
  echo "   ❌ Authentication failed!"
  exit 1
fi
echo "   ✅ Authentication successful"

# Test 2: Get CSRF token
echo ""
echo "2. Getting CSRF token..."
CRUMB_JSON=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/crumbIssuer/api/json")

echo "   Response: $CRUMB_JSON"

if command -v jq &> /dev/null; then
  CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField')
  CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb')
else
  CRUMB_FIELD=$(echo "$CRUMB_JSON" | grep -o '"crumbRequestField":"[^"]*"' | cut -d'"' -f4)
  CRUMB_VALUE=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$CRUMB_FIELD" ] || [ -z "$CRUMB_VALUE" ]; then
  echo "   ❌ Failed to parse CSRF token"
  exit 1
fi

echo "   ✅ CSRF token parsed:"
echo "      Field: $CRUMB_FIELD"
echo "      Value: ${CRUMB_VALUE:0:20}..."

# Test 3: Test API call with CSRF token
echo ""
echo "3. Testing API call with CSRF token..."
TEST_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  "$JENKINS_URL/api/json")

HTTP_CODE=$(echo "$TEST_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "200" ]; then
  echo "   ✅ API call with CSRF token successful!"
else
  echo "   ❌ API call failed with HTTP $HTTP_CODE"
  echo "   Response: $(echo "$TEST_RESPONSE" | head -n-1)"
fi

echo ""
echo "================================"
echo "If all tests pass, you can use:"
echo "  CRUMB_FIELD=\"$CRUMB_FIELD\""
echo "  CRUMB_VALUE=\"$CRUMB_VALUE\""
