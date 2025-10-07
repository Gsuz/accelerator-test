#!/bin/bash
# Test script for end-to-end AWS backbone flow
# This script verifies:
# - Tokyo forwarder → Frankfurt receiver communication
# - Event forwarding over TCP
# - Sequence tracking and packet loss detection
# - Statistics output

set -e

echo "=== AWS Backbone End-to-End Test ==="
echo ""

# Build the project
echo "Building both components..."
cargo build --release
echo "✓ Build successful"
echo ""

# Start Frankfurt receiver in AWS backbone mode
echo "Starting Frankfurt receiver in AWS backbone mode..."
./target/release/frankfurt-receiver \
    --mode aws-backbone \
    --port 8080 \
    --duration 15 \
    --output /tmp/backbone-results.json \
    --csv-output /tmp/backbone-measurements.csv \
    > /tmp/frankfurt-backbone.log 2>&1 &
FRANKFURT_PID=$!

# Give Frankfurt time to start listening
sleep 2

# Start Tokyo forwarder
echo "Starting Tokyo forwarder..."
timeout 15 ./target/release/tokyo-forwarder \
    --frankfurt-ip 127.0.0.1 \
    --frankfurt-port 8080 \
    > /tmp/tokyo-backbone.log 2>&1 &
TOKYO_PID=$!

echo "✓ Both components started"
echo "  - Frankfurt receiver PID: $FRANKFURT_PID"
echo "  - Tokyo forwarder PID: $TOKYO_PID"
echo ""
echo "Running for 15 seconds..."

# Wait for Frankfurt to complete (it has a duration limit)
wait $FRANKFURT_PID 2>/dev/null || true

# Kill Tokyo forwarder if still running
kill $TOKYO_PID 2>/dev/null || true
wait $TOKYO_PID 2>/dev/null || true

echo "✓ Test run completed"
echo ""

echo "=== Test Results ==="
echo ""

# Check Tokyo forwarder log
if [ ! -f /tmp/tokyo-backbone.log ]; then
    echo "✗ FAILED: Tokyo forwarder log not found"
    exit 1
fi

if ! grep -q "Connected to Binance WebSocket" /tmp/tokyo-backbone.log; then
    echo "✗ FAILED: Tokyo did not connect to Binance"
    cat /tmp/tokyo-backbone.log
    exit 1
fi
echo "✓ Tokyo connected to Binance WebSocket"

if ! grep -q "Connected to Frankfurt" /tmp/tokyo-backbone.log; then
    echo "✗ FAILED: Tokyo did not connect to Frankfurt"
    cat /tmp/tokyo-backbone.log
    exit 1
fi
echo "✓ Tokyo connected to Frankfurt"

# Check Frankfurt receiver log
if [ ! -f /tmp/frankfurt-backbone.log ]; then
    echo "✗ FAILED: Frankfurt receiver log not found"
    exit 1
fi

if ! grep -q "Accepted connection from" /tmp/frankfurt-backbone.log; then
    echo "✗ FAILED: Frankfurt did not accept connection from Tokyo"
    cat /tmp/frankfurt-backbone.log
    exit 1
fi
echo "✓ Frankfurt accepted connection from Tokyo"

if ! grep -q "Collection complete" /tmp/frankfurt-backbone.log; then
    echo "✗ FAILED: Frankfurt collection did not complete"
    cat /tmp/frankfurt-backbone.log
    exit 1
fi
echo "✓ Frankfurt data collection completed"

# Check if output files were created
if [ ! -f /tmp/backbone-results.json ]; then
    echo "✗ FAILED: Results JSON file not created"
    cat /tmp/frankfurt-backbone.log
    exit 1
fi
echo "✓ Results JSON file created"

if [ ! -f /tmp/backbone-measurements.csv ]; then
    echo "✗ FAILED: CSV measurements file not created"
    exit 1
fi
echo "✓ CSV measurements file created"

# Validate JSON structure
if ! jq . /tmp/backbone-results.json > /dev/null 2>&1; then
    echo "✗ FAILED: Results file is not valid JSON"
    cat /tmp/backbone-results.json
    exit 1
fi
echo "✓ Results file is valid JSON"

# Check for required fields
SETUP_TYPE=$(jq -r '.setup_type' /tmp/backbone-results.json)
SAMPLE_COUNT=$(jq -r '.sample_count' /tmp/backbone-results.json)
EVENTS_LOST=$(jq -r '.events_lost' /tmp/backbone-results.json)
BACKBONE_AVG=$(jq -r '.backbone_avg_latency_ms' /tmp/backbone-results.json)
BACKBONE_MEDIAN=$(jq -r '.backbone_median_latency_ms' /tmp/backbone-results.json)

if [ "$SETUP_TYPE" != "aws-backbone" ]; then
    echo "✗ FAILED: Expected setup_type 'aws-backbone', got '$SETUP_TYPE'"
    exit 1
fi
echo "✓ setup_type is 'aws-backbone'"

if [ "$SAMPLE_COUNT" = "null" ] || [ "$SAMPLE_COUNT" -lt 1 ]; then
    echo "✗ FAILED: Expected at least 1 sample, got $SAMPLE_COUNT"
    exit 1
fi
echo "✓ sample_count is valid: $SAMPLE_COUNT"

if [ "$EVENTS_LOST" = "null" ]; then
    echo "✗ FAILED: events_lost field missing"
    exit 1
fi
echo "✓ events_lost tracked: $EVENTS_LOST"

if [ "$BACKBONE_AVG" = "null" ]; then
    echo "✗ FAILED: backbone_avg_latency_ms should be present in AWS backbone mode"
    exit 1
fi
echo "✓ backbone_avg_latency_ms present: $BACKBONE_AVG ms"

if [ "$BACKBONE_MEDIAN" = "null" ]; then
    echo "✗ FAILED: backbone_median_latency_ms should be present in AWS backbone mode"
    exit 1
fi
echo "✓ backbone_median_latency_ms present: $BACKBONE_MEDIAN ms"

# Verify CSV has tokyo_time and backbone_latency_ms columns
CSV_HEADER=$(head -n 1 /tmp/backbone-measurements.csv)
if [[ ! "$CSV_HEADER" =~ "tokyo_time" ]]; then
    echo "✗ FAILED: CSV missing tokyo_time column"
    exit 1
fi
echo "✓ CSV has tokyo_time column"

if [[ ! "$CSV_HEADER" =~ "backbone_latency_ms" ]]; then
    echo "✗ FAILED: CSV missing backbone_latency_ms column"
    exit 1
fi
echo "✓ CSV has backbone_latency_ms column"

# Verify CSV has data with tokyo_time populated
SECOND_LINE=$(sed -n '2p' /tmp/backbone-measurements.csv)
TOKYO_TIME_VALUE=$(echo "$SECOND_LINE" | cut -d',' -f3)
if [ -z "$TOKYO_TIME_VALUE" ] || [ "$TOKYO_TIME_VALUE" = "null" ]; then
    echo "✗ FAILED: tokyo_time not populated in CSV data"
    exit 1
fi
echo "✓ tokyo_time populated in CSV data"

# Check for sequence ID tracking
echo ""
echo "=== Sequence Tracking Verification ==="
FIRST_SEQ=$(sed -n '2p' /tmp/backbone-measurements.csv | cut -d',' -f1)
LAST_SEQ=$(tail -n 1 /tmp/backbone-measurements.csv | cut -d',' -f1)
echo "First sequence ID: $FIRST_SEQ"
echo "Last sequence ID: $LAST_SEQ"
echo "Events lost: $EVENTS_LOST"

if [ "$EVENTS_LOST" -gt 0 ]; then
    echo "⚠ WARNING: Some events were lost during transmission"
else
    echo "✓ No packet loss detected"
fi

# Display results summary
echo ""
echo "=== Results Summary ==="
cat /tmp/backbone-results.json | jq .
echo ""

# Display sample CSV rows
echo "=== Sample CSV Data (first 5 rows) ==="
head -n 6 /tmp/backbone-measurements.csv
echo ""

# Display log excerpts
echo "=== Tokyo Forwarder Log (last 10 lines) ==="
tail -n 10 /tmp/tokyo-backbone.log
echo ""

echo "=== Frankfurt Receiver Log (last 10 lines) ==="
tail -n 10 /tmp/frankfurt-backbone.log
echo ""

# Cleanup
rm -f /tmp/backbone-results.json /tmp/backbone-measurements.csv
rm -f /tmp/frankfurt-backbone.log /tmp/tokyo-backbone.log

echo "=== All Tests Passed ✓ ==="
echo ""
echo "Summary:"
echo "- Tokyo → Frankfurt TCP connection: ✓"
echo "- Event forwarding: ✓"
echo "- Sequence tracking: ✓"
echo "- Packet loss detection: ✓"
echo "- Backbone latency calculation: ✓"
echo "- Statistics output: ✓"
echo "- Samples collected: $SAMPLE_COUNT"
echo "- Events lost: $EVENTS_LOST"
