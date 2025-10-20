# Kafka Streams Data Contracts Microservice

A Spring Boot application using Kafka Streams to process stock trade data with Confluent Cloud Data Contracts.

## Overview

- **Input**: Consumes JSON messages from `stock_trades.raw`.
- **Processing**: Parses JSON, uppercases the `symbol`, produces Avro `StockTrade` records to `stock_trades`.
- **Data Contracts**: Enforces CEL rules (quantity > 0, symbol regex, account format) via Confluent Cloud; violations routed to `stock_trades.dlq`.

## Prerequisites

- Java 17+
- Maven 3.6+
- Confluent Cloud account with Kafka cluster and Schema Registry (ADVANCED tier for Data Contracts)
- Topics: `stock_trades.raw` (input), `stock_trades` (output), `stock_trades.dlq` (DLQ)

## Setup

1. **Clone and build**:
   ```bash
   git clone <repo>
   cd kstreams-data-contracts
   mvn clean compile
   ```

2. **Set environment variables**:
   Edit `scripts/set-env.sh` with your Confluent Cloud credentials and source it:
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

- Produce valid JSON to `stock_trades.raw`: `{"side":"BUY","quantity":100,"symbol":"AAPL","price":150.0,"account":"ACC123","userid":"user1"}`
- Check `stock_trades` for Avro output.
- Produce invalid (e.g., quantity=0) and check `stock_trades.dlq` for violations.

Use Confluent CLI or Cloud Console to produce/consume.

