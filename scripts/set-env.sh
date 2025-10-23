#!/usr/bin/env bash
# Load environment variables for local runs (non-destructive).
# This script will source the user's `~/.zprofile` if present, then export a
# set of expected environment variable names so child processes inherit them.

set -euo pipefail

PROFILE="$HOME/.zprofile"
if [ -f "$PROFILE" ]; then
	# shellcheck disable=SC1090
	source "$PROFILE"
fi

# Export the important variables (no-op if already set)
export KAFKA_SECURITY_PROTOCOL
export KAFKA_SASL_MECHANISM
export KAFKA_BOOTSTRAP_SERVERS
export SCHEMA_REGISTRY_URL
export KAFKA_API_KEY
export KAFKA_API_SECRET
export SCHEMA_REGISTRY_API_KEY
export SCHEMA_REGISTRY_API_SECRET
export CONFLUENT_ENVIRONMENT_ID
export SCHEMA_REGISTRY_CLUSTER_ID

echo "Loaded environment variables for kstreams-data-contracts (sourced $PROFILE if present)."