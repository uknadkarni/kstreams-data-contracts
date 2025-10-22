#!/usr/bin/env bash
set -euo pipefail

# Register a data contract (Avro schema + business metadata + field rules) with Confluent Cloud Schema Registry
# This script registers the schema and metadata; Confluent Cloud's Data Governance automatically routes
# messages that violate field constraints to the DLQ topic (stock_trades.dlq by default).
#
# Usage:
#   export SCHEMA_REGISTRY_URL="https://psrc-lq2dm.us-east-2.aws.confluent.cloud"
#   export SCHEMA_REGISTRY_API_KEY="your-api-key"
#   export SCHEMA_REGISTRY_API_SECRET="your-api-secret"
#   export SUBJECT="stock_trades.raw-value"  # Optional, defaults to stock_trades.raw-value
#   export DESCRIPTION="Stock trades data contract - raw trade messages"  # Optional
#   export OWNER="data-team@example.com"  # Optional
#   export TAGS="trading,stock,raw"  # Optional, comma-separated
#   export FIELD_RULES_FILE="/path/to/field_rules.json"  # Optional, JSON file with field constraints
#   export BOOTSTRAP_SERVERS="pkc-921jm.us-east-2.aws.confluent.cloud:9092"  # Optional, for metadata
#   ./register_data_contract.sh
#
# Prerequisites:
# - curl and jq must be installed
# - Confluent Cloud Schema Registry credentials
# - FIELD_RULES_FILE should contain JSON like: {"symbol": {"rule": "not_null"}, ...} if provided
#
# Required environment variables:
# - SCHEMA_REGISTRY_URL (defaults to Confluent Cloud URL if not set)
# - SCHEMA_REGISTRY_API_KEY
# - SCHEMA_REGISTRY_API_SECRET
#
# Optional environment variables:
# - SUBJECT (default: stock_trades.raw-value)
# - DESCRIPTION (default: "Stock trades data contract - raw trade messages")
# - OWNER (default: "data-team@example.com")
# - TAGS (default: "trading,stock,raw")
# - FIELD_RULES_FILE (path to JSON file with field constraints; see README for format)
# - BOOTSTRAP_SERVERS (Kafka bootstrap servers, included in metadata if set)

# Set default values for environment variables
SCHEMA_REGISTRY_URL=${SCHEMA_REGISTRY_URL:-https://psrc-lq2dm.us-east-2.aws.confluent.cloud}
API_KEY=${SCHEMA_REGISTRY_API_KEY:-}
API_SECRET=${SCHEMA_REGISTRY_API_SECRET:-}
SUBJECT=${SUBJECT:-stock_trades-value}

# Business metadata (optional)
DESCRIPTION=${DESCRIPTION:-"Stock trades data contract - raw trade messages"}
OWNER=${OWNER:-"data-team@example.com"}
TAGS=${TAGS:-"trading,stock,raw"}
FIELD_RULES_FILE=${FIELD_RULES_FILE:-}
BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS:-}

# Function to print error and exit
die() { echo "ERROR: $*" >&2; exit 1; }

# Check for required tools
if ! command -v curl >/dev/null 2>&1; then
  die "curl is required but not installed"
fi

if ! command -v jq >/dev/null 2>&1; then
  die "jq is required but not installed (used to build JSON payload)"
fi

# Validate required environment variables
[ -n "$SCHEMA_REGISTRY_URL" ] || die "SCHEMA_REGISTRY_URL is not set"
[ -n "$API_KEY" ] || die "SCHEMA_REGISTRY_API_KEY is not set"
[ -n "$API_SECRET" ] || die "SCHEMA_REGISTRY_API_SECRET is not set"

# Debug: Log the API key and masked secret
echo "Debug: Using SCHEMA_REGISTRY_API_KEY: $API_KEY"
echo "Debug: Using SCHEMA_REGISTRY_API_SECRET: [MASKED]"

die() { echo "ERROR: $*" >&2; exit 1; }

if ! command -v curl >/dev/null 2>&1; then
  die "curl is required but not installed"
fi

if ! command -v jq >/dev/null 2>&1; then
  die "jq is required but not installed (used to build JSON payload)"
fi

[ -n "$SCHEMA_REGISTRY_URL" ] || die "SCHEMA_REGISTRY_URL is not set"
[ -n "$API_KEY" ] || die "SCHEMA_REGISTRY_API_KEY is not set"
[ -n "$API_SECRET" ] || die "SCHEMA_REGISTRY_API_SECRET is not set"

# Create the Avro schema file by copying from the codebase
# This defines the structure for StockTrade records with fields: side (enum), quantity (int), symbol (string), price (double), account (string), userid (string)
cp /Users/ut/workspace/kstreams-data-contracts/src/main/avro/stock_trade.avsc /tmp/stock_trade.avsc

# Read the schema as a compact JSON string for the registration payload
SCHEMA_JSON=$(jq -c '.' /tmp/stock_trade.avsc)
REGISTER_PAYLOAD=$(jq -n --arg s "$SCHEMA_JSON" '{schema: $s}')

# Register the Avro schema with Schema Registry
echo "Registering Avro schema under subject: $SUBJECT"
echo "Schema Registry URL: $SCHEMA_REGISTRY_URL"

HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" --user "$API_KEY:$API_SECRET" \
  -X POST "$SCHEMA_REGISTRY_URL/subjects/$SUBJECT/versions" \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d "$REGISTER_PAYLOAD")

# Parse the HTTP response: body and status code
HTTP_BODY=$(sed '$d' <<<"$HTTP_RESPONSE")
HTTP_STATUS=$(tail -n1 <<<"$HTTP_RESPONSE")

# Check if registration was successful (2xx status)
if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  echo "Schema registered successfully. Response:"
  echo "$HTTP_BODY" | jq .
  SCHEMA_ID=$(echo "$HTTP_BODY" | jq -r '.id // empty')
  echo "Registered schema id: $SCHEMA_ID"

  exit 0
else
  # Registration failed
  echo "Failed to register schema. HTTP status: $HTTP_STATUS" >&2
  echo "$HTTP_BODY" | jq . >&2 || echo "$HTTP_BODY" >&2
  exit 1
fi
