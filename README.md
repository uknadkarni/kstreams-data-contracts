# Kafka Streams Data Contracts Microservice

A Spring Boot application using Kafka Streams to process stock trade data with Confluent Cloud Data Contracts.

## Purpose

The purpose of this Kafka Streams application is to demonstrate Shift-Left of Stream Governance. When a Kafka Connect converter doesn't (or can't) enforce the rules you need, building a Kafka Streams (KStreams) application is a very common and powerful pattern to enforce governance.

This approach essentially creates a dedicated "validation microservice" that sits in the middle of your data pipeline.

## Overview

- **Input**: Consumes JSON messages from `trades.raw`.
- **Processing**: Parses JSON, uppercases the `symbol`, produces Avro `StockTrade` records to `trades`.
- **Data Contracts**: Enforces CEL rules (quantity > 0, symbol regex, account format) via Confluent Cloud; violations routed to `trades.dlq`.

## Prerequisites

### Local Development Environment
- **Java 17+** (JDK installed and `JAVA_HOME` set)
- **Maven 3.6+**
- **Git** (to clone the repository)

#### Environment Variables
Ensure the following environment variables are set in your shell profile (e.g., `~/.zprofile`, `~/.bashrc`, or `~/.zshrc`) for Confluent Cloud access:

```bash
export KAFKA_SECURITY_PROTOCOL="SASL_SSL"
export KAFKA_SASL_MECHANISM="PLAIN"
export KAFKA_BOOTSTRAP_SERVERS="<your-bootstrap-server-url>"
export SCHEMA_REGISTRY_URL="<your-schema-registry-url>"
export KAFKA_API_KEY="<runtime-kafka-api-key>"
export KAFKA_API_SECRET="<runtime-kafka-api-secret>"
export SCHEMA_REGISTRY_API_KEY="<runtime-schema-registry-api-key>"
export SCHEMA_REGISTRY_API_SECRET="<runtime-schema-registry-api-secret>"
export CONFLUENT_ENVIRONMENT_ID="<your-environment-id>"
export SCHEMA_REGISTRY_CLUSTER_ID="<your-schema-registry-cluster-id>"
```

> **Note**: The `scripts/set-env.sh` file sources these variables from your environment. Update your shell profile and restart your terminal, or run `source ~/.zprofile` (or equivalent) to load them.

### Confluent Cloud Setup

You will need a **Confluent Cloud account** with the following resources configured:

#### 1. Kafka Cluster & Schema Registry
- A **Kafka cluster** (any tier: Basic, Standard, or Dedicated)
- A **Schema Registry** with **ADVANCED governance** tier enabled (required for Data Contracts)
- Note the following for your cluster:
  - **Bootstrap Server URL** (e.g., `pkc-xxxxx.us-east-2.aws.confluent.cloud:9092`)
  - **Schema Registry URL** (e.g., `https://psrc-xxxxx.us-east-2.aws.confluent.cloud`)
  - **Environment ID** and **Schema Registry Cluster ID** (found in Confluent Cloud Console)

#### 2. Service Accounts & API Keys

Create **two service accounts** to follow the principle of least privilege:

**a) Runtime Service Account** (for the Kafka Streams application)
- **Purpose**: Used by the running application to consume/produce messages and fetch schemas
- **Kafka API Key/Secret**: Create an API key for this service account with the following ACLs:
  - `READ` on topic `stock_trades.raw`
  - `WRITE` on topics `stock_trades` and `stock_trades.dlq`
  - `CREATE` on the cluster (for Kafka Streams internal topics)
  - `DESCRIBE` on the cluster
  - `READ/WRITE` on consumer group (for Kafka Streams state management)
- **Schema Registry API Key/Secret**: Create a read-only Schema Registry API key for this service account
  - Role: **Schema Registry Read** (can fetch schemas but not modify them)
- Store these credentials as environment variables in your shell profile (see Environment Variables section above):
```bash
export KAFKA_API_KEY="<runtime-kafka-key>"
export KAFKA_API_SECRET="<runtime-kafka-secret>"
export SCHEMA_REGISTRY_API_KEY="<runtime-sr-key>"
export SCHEMA_REGISTRY_API_SECRET="<runtime-sr-secret>"
```**b) Admin Service Account** (for schema registration and Data Contracts management)
- **Purpose**: Used by scripts and operators to register schemas and manage Data Contracts rules
- **Schema Registry API Key/Secret**: Create a Schema Registry API key with **DataSteward** role
  - Role: **DataSteward** (can create/update schemas and manage Data Contracts rules)
- Use this key only for administrative tasks like running `scripts/register_data_contract.sh`

> **Note**: You can use the same API keys for both runtime and admin if you prefer, but separate keys are recommended for security and audit purposes.

#### 3. Topics

Create the following topics in Confluent Cloud:

**a) `trades.raw`** (input topic)
- **Purpose**: Receives raw JSON stock trade data from the DataGen connector
- **Schema**: No schema (plain JSON)
- **Partitions**: 6 (or adjust based on expected load)
- **Retention**: 7 days (or as needed)

**b) `trades`** (output topic)
- **Purpose**: Contains validated, transformed Avro `StockTrade` records
- **Schema**: **Avro** (will be registered with Data Contracts rules)
- **Partitions**: 6 (should match input topic for balanced processing)
- **Retention**: 7 days (or as needed)

**c) `trades.dlq`** (dead letter queue)
- **Purpose**: Receives messages that fail Data Contracts validation
- **Schema**: None (will receive JSON with validation failure metadata from Schema Registry)
- **Partitions**: 6
- **Retention**: 30 days (or longer for audit/troubleshooting)

#### 4. DataGen Source Connector

In the Confluent Cloud UI:
1. Navigate to **Connectors** in your cluster
2. Click **Add connector** and search for **"DataGen Source"**
3. Configure the connector:
   - **Name**: `trades-datagen` (or your choice)
   - **Kafka credentials**: Select/create an API key with WRITE access to `trades.raw`
   - **Output topic**: `trades.raw`
   - **Output record value format**: **JSON** (plain JSON) — NOT JSON_SCHEMA or AVRO
   - **Quickstart template**: **Stock Trades**
   - **Max interval between messages**: 1000 (1 message/sec, adjust as needed)
   - **Tasks**: 1
4. **Important**: Ensure the connector uses a JSON/STRING converter without schema registration. If the connector UI exposes `value.converter.schemas.enable`, set it to `false` (or pick JSON that disables schema registration). This will prevent Schema Registry framing (the 5-byte prefix).

Example connector config (Cloud API / REST style):

```json
{
  "name": "trades-datagen",
  "config": {
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
    "kafka.topic": "trades.raw",
    "quickstart": "stock-trades",
    "max.interval": "1000",
    "tasks.max": "1",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
  }
}
```

Verification: after deployment, inspect a message with `kcat` — the first byte should be `0x7b` (ASCII `{`) and not start with `00 00 01 ...`.

#### 5. Register Avro Schema for `stock_trades`

Create the **`stock_trades`** topic with the following **Avro schema** for the value:

**Option A: Via Confluent Cloud UI**
1. Go to **Stream Governance** > **Schemas**
2. Click **Add schema** and select subject **`stock_trades-value`**
3. Paste the following schema:

```json
{
  "type": "record",
  "name": "StockTrade",
  "namespace": "com.example.kstreamsdatacontracts.avro",
  "fields": [
    {"name": "side", "type": {"type": "enum", "name": "Side", "symbols": ["BUY", "SELL", "UNKNOWN"]}},
    {"name": "quantity", "type": "int"},
    {"name": "symbol", "type": "string"},
    {"name": "price", "type": "double"},
    {"name": "account", "type": "string"},
    {"name": "userid", "type": "string"}
  ]
}
```

4. Click **Create** to register the schema

**Option B: Via Script**
- Run the provided script (requires DataSteward API key):
  ```bash
  source scripts/set-env.sh  # Ensure DataSteward credentials are set
  ./scripts/register_data_contract.sh
  ```

#### 6. Configure Data Contracts (Data Quality Rules)

After registering the schema, add the following **Data Contracts rules** in Confluent Cloud:

> Note: this repository includes a canonical copy of the rules at `config/rules.json`. Use that file as a starting point when creating rules via the Confluent Cloud Console or the Schema Registry API.

1. Go to **Stream Governance** > **Schemas**
2. Find the subject **`stock_trades-value`**
3. Click on the schema version, then navigate to the **Data Contracts** or **Quality Rules** tab
4. Add each of the following rules:

---

**Rule: `quantity_positive`**
- **Type**: CEL
- **Kind**: CONDITION
- **Mode**: WRITE
- **Expression**: `message.quantity > 0`
- **Description**: "Message Quantity" (ensures trade quantity is a positive integer)
- **On Failure**: Send to DLQ
  - **DLQ Topic**: `stock_trades.dlq`

---

**Rule: `price_positive`**
- **Type**: CEL
- **Kind**: CONDITION
- **Mode**: WRITE
- **Expression**: `message.price > 0.0`
- **Description**: "Ensures price is greater than zero"
- **On Failure**: Send to DLQ
  - **DLQ Topic**: `stock_trades.dlq`
- **⚠️ Important**: Ensure the DLQ topic is spelled correctly as `stock_trades.dlq` (not `stock_trades.dql`)

---

**Rule: `symbol_not_empty`**
- **Type**: CEL
- **Kind**: CONDITION
- **Mode**: WRITE
- **Expression**: `message.symbol != null && message.symbol != ""`
- **Description**: "Ensures symbol is present and non-empty"
- **On Failure**: Send to DLQ
  - **DLQ Topic**: `stock_trades.dlq`

---

**Rule: `valid_side_enum`**
- **Type**: CEL
- **Kind**: CONDITION
- **Mode**: WRITE
- **Expression**: `message.side == "BUY" || message.side == "SELL"`
- **Description**: "Ensures side is one of the allowed enum values (BUY or SELL)"
- **On Failure**: Send to DLQ
  - **DLQ Topic**: `stock_trades.dlq`

---

**Rule: `account_not_empty`**
- **Type**: CEL
- **Kind**: CONDITION
- **Mode**: WRITE
- **Expression**: `message.account != null && message.account != ""`
- **Description**: "Ensures account is present and non-empty"
- **On Failure**: Send to DLQ
  - **DLQ Topic**: `stock_trades.dlq`

---

**Rule: `userid_not_empty`**
- **Type**: CEL
- **Kind**: CONDITION
- **Mode**: WRITE
- **Expression**: `message.userid != null && message.userid != ""`
- **Description**: "Ensures userid is present and non-empty"
- **On Failure**: Send to DLQ
  - **DLQ Topic**: `stock_trades.dlq`

---

5. **Save** all rules and ensure they are **enabled**

> **Verification**: After adding all rules, confirm that the `stock_trades-value` schema shows 6 active Data Contracts rules in the Confluent Cloud UI.

## Setup

1. **Clone and build**:
   ```bash
   git clone <repo>
   cd kstreams-data-contracts
   mvn clean compile
   ```

2. **Set environment variables**:
   Ensure your environment variables are loaded (they should be set in your shell profile as described in Prerequisites):
   ```bash
   source scripts/set-env.sh
   ```

3. **Register the Avro schema**:
   ```bash
   ./scripts/register_data_contract.sh
   ```

4. **Add Data Contracts rules** in Confluent Cloud Console:
   - Go to **Stream Governance** > **Data Contracts**.
   - Find subject `stock_trades-value`.
   - Add rules:
     - Name: `quantity_check`, CEL: `message.quantity > 0`, Action: Send to DLQ (`stock_trades.dlq`)
     - Name: `symbol_check`, CEL: `message.symbol.matches("^[A-Z]{1,5}$")`, Action: Send to DLQ
     - Name: `account_check`, CEL: `message.account.matches("^ACC[0-9]{3}$")`, Action: Send to DLQ

5. **Run the app**:
   ```bash
   mvn spring-boot:run
   ```

## Schema

Avro schema for `StockTrade` (auto-generated from `src/main/avro/stock_trade.avsc`):

```json
{
  "type": "record",
  "name": "StockTrade",
  "namespace": "com.example.kstreamsdatacontracts.avro",
  "fields": [
    {"name": "side", "type": {"type": "enum", "name": "Side", "symbols": ["BUY", "SELL", "UNKNOWN"]}},
    {"name": "quantity", "type": "int"},
    {"name": "symbol", "type": "string"},
    {"name": "price", "type": "double"},
    {"name": "account", "type": "string"},
    {"name": "userid", "type": "string"}
  ]
}
```

## Testing

-- Produce valid JSON to `trades.raw`: `{"side":"BUY","quantity":100,"symbol":"AAPL","price":150.0,"account":"ACC123","userid":"user1"}`
-- Check `trades` for Avro output.
-- Produce invalid (e.g., quantity=0) and check `trades.dlq` for violations.

Use Confluent CLI or Cloud Console to produce/consume.

