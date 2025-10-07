#!/bin/bash
# Test script for Frankfurt receiver in baseline mode
# This script verifies:
# - WebSocket connection to Binance
# - Latency calculation
# - Statistics output

set -e

echo "=== Frankfurt Receiver Baseline Mode Test ==="
echo ""

# Build the project
echo "Building Frankfurt receiver..."
cargo build --release --bin frankfurt-receiver
echo "✓ Build successful"
echo ""

# Run Frankfurt receiver in baseline mode for 10 seconds
echo "Running Frankfurt receiver in baseline mode for 10 seconds..."
./target/release/frankfurt-receiver \
    --mode baseline \
    --duration 10 \
    --output /tmp/baseline-results.json \
    --csv-output /tmp/baseline-measurements.csv \
    > /tmp/frankfurt-baseline.log 2>&1

echo "✓ Frankfurt receiver completed"
echo ""

echo "=== Test Results ==="
echo ""

# Check if output files were created
if [ ! -f /tmp/baseline-results.json ]; then
    echo "✗ FAILED: Results JSON file not created"
    cat /tmp/frankfurt-baseline.log
    exit 1
fi
echo "✓ Results JSON file created"

if [ ! -f /tmp/baseline-measurements.csv ]; then
    echo "✗ FAILED: CSV measurements file not created"
    exit 1
fi
echo "✓ CSV measurements file created"

# Validate JSON structure
if ! jq . /tmp/baseline-results.json > /dev/null 2>&1; then
    echo "✗ FAILED: Results file is not valid JSON"
    cat /tmp/baseline-results.json
    exit 1
fi
echo "✓ Results file is valid JSON"

# Check for required fields in results
SETUP_TYPE=$(jq -r '.setup_type' /tmp/baseline-results.json)
SAMPLE_COUNT=$(jq -r '.sample_count' /tmp/baseline-results.json)
AVG_LATENCY=$(jq -r '.avg_latency_ms' /tmp/baseline-results.json)
MEDIAN_LATENCY=$(jq -r '.median_latency_ms' /tmp/baseline-results.json)
P95_LATENCY=$(jq -r '.p95_latency_ms' /tmp/baseline-results.json)
P99_LATENCY=$(jq -r '.p99_latency_ms' /tmp/baseline-results.json)
MIN_LATENCY=$(jq -r '.min_latency_ms' /tmp/baseline-results.json)
MAX_LATENCY=$(jq -r '.max_latency_ms' /tmp/baseline-results.json)
JITTER=$(jq -r '.jitter_stddev_ms' /tmp/baseline-results.json)

if [ "$SETUP_TYPE" != "baseline" ]; then
    echo "✗ FAILED: Expected setup_type 'baseline', got '$SETUP_TYPE'"
    exit 1
fi
echo "✓ setup_type is 'baseline'"

if [ "$SAMPLE_COUNT" = "null" ] || [ "$SAMPLE_COUNT" -lt 1 ]; then
    echo "✗ FAILED: Expected at least 1 sample, got $SAMPLE_COUNT"
    exit 1
fi
echo "✓ sample_count is valid: $SAMPLE_COUNT"

# Verify all statistics fields are present and numeric
for field in avg_latency_ms median_latency_ms p95_latency_ms p99_latency_ms min_latency_ms max_latency_ms jitter_stddev_ms; do
    VALUE=$(jq -r ".$field" /tmp/baseline-results.json)
    if [ "$VALUE" = "null" ]; then
        echo "✗ FAILED: Missing field $field"
        exit 1
    fi
done
echo "✓ All statistics fields present"

# Verify CSV has data
CSV_LINE_COUNT=$(wc -l < /tmp/baseline-measurements.csv)
if [ "$CSV_LINE_COUNT" -lt 2 ]; then
    echo "✗ FAILED: CSV should have at least 2 lines (header + data)"
    exit 1
fi
echo "✓ CSV file has data ($CSV_LINE_COUNT lines including header)"

# Verify CSV header
HEADER=$(head -n 1 /tmp/baseline-measurements.csv)
if [[ ! "$HEADER" =~ "sequence_id" ]] || [[ ! "$HEADER" =~ "latency_ms" ]]; then
    echo "✗ FAILED: CSV header missing expected columns"
    echo "Header: $HEADER"
    exit 1
fi
echo "✓ CSV header is correct"

# Check log for successful connection
if ! grep -q "Connected to Binance WebSocket" /tmp/frankfurt-baseline.log; then
    echo "✗ FAILED: Did not connect to Binance WebSocket"
    cat /tmp/frankfurt-baseline.log
    exit 1
fi
echo "✓ WebSocket connection established (from log)"

if ! grep -q "Collection complete" /tmp/frankfurt-baseline.log; then
    echo "✗ FAILED: Collection did not complete properly"
    cat /tmp/frankfurt-baseline.log
    exit 1
fi
echo "✓ Data collection completed successfully"

# Display results summary
echo ""
echo "=== Results Summary ==="
cat /tmp/baseline-results.json | jq .
echo ""

# Display sample CSV rows
echo "=== Sample CSV Data (first 5 rows) ==="
head -n 6 /tmp/baseline-measurements.csv
echo ""

# Cleanup
rm -f /tmp/baseline-results.json /tmp/baseline-measurements.csv /tmp/frankfurt-baseline.log

echo "=== All Tests Passed ✓ ==="
echo ""
echo "Summary:"
echo "- WebSocket connection to Binance: ✓"
echo "- Latency calculation: ✓"
echo "- Statistics output (JSON): ✓"
echo "- Raw measurements output (CSV): ✓"
echo "- Samples collected: $SAMPLE_COUNT"
