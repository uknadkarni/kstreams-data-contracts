package com.example.kstreamsdatacontracts.config;

import com.example.kstreamsdatacontracts.avro.StockTrade;
import com.example.kstreamsdatacontracts.avro.Side;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.Produced;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import java.util.Map;

@Configuration
public class StreamsConfig {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${spring.kafka.properties.schema.registry.url}")
    private String schemaRegistryUrl;

    @Value("${spring.kafka.properties.schema.registry.basic.auth.user.info}")
    private String schemaRegistryAuth;

    @Value("${app.topic.input:stock_trades.raw}")
    private String inputTopic;

    @Value("${app.topic.output:stock_trades}")
    private String outputTopic;

    @Bean
    public KStream<String, StockTrade> kStreamTopology(StreamsBuilder builder) {
        // Configure Specific Avro Serde for output
        SpecificAvroSerde<StockTrade> avroSerde = new SpecificAvroSerde<>();
        avroSerde.configure(Map.of(
            "schema.registry.url", schemaRegistryUrl,
            "basic.auth.credentials.source", "USER_INFO",
            "schema.registry.basic.auth.user.info", schemaRegistryAuth
        ), false);

        // Read from input topic as String (assuming JSON_SR is JSON string)
        KStream<String, String> inputStream = builder.stream(inputTopic);

        // Transform JSON string to Avro StockTrade, uppercasing symbol
        KStream<String, StockTrade> transformedStream = inputStream.mapValues(jsonString -> {
            if (jsonString != null) {
                try {
                    JsonNode jsonNode = objectMapper.readTree(jsonString);
                    String sideStr = jsonNode.get("side").asText();
                    Side side = Side.valueOf(sideStr.toUpperCase());
                    int quantity = jsonNode.get("quantity").asInt();
                    String symbol = jsonNode.get("symbol").asText().toUpperCase();
                    double price = jsonNode.get("price").asDouble();
                    String account = jsonNode.get("account").asText();
                    String userid = jsonNode.get("userid").asText();

                    return StockTrade.newBuilder()
                        .setSide(side)
                        .setQuantity(quantity)
                        .setSymbol(symbol)
                        .setPrice(price)
                        .setAccount(account)
                        .setUserid(userid)
                        .build();
                } catch (Exception e) {
                    // Log error and return null or handle invalid records
                    System.err.println("Error transforming record: " + e.getMessage());
                    return null;
                }
            }
            return null;
        }).filter((key, value) -> value != null); // Filter out nulls

        // Write to output topic with Avro serde
        transformedStream.to(outputTopic, Produced.with(Serdes.String(), avroSerde));

        return transformedStream;
    }

    @Bean
    @Primary
    public StreamsBuilder streamsBuilder() {
        return new StreamsBuilder();
    }
}
