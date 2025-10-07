#!/bin/bash
# Quick comparison experiment test (30 seconds each instead of 5 minutes)
# This is for testing purposes

set -e

echo "=== Quick Latency Comparison Experiment ==="
echo ""
echo "Running 30-second tests for validation"
echo ""

# Build the project
echo "Building all components..."
cargo build --release
echo "✓ Build successful"
echo ""

# Run baseline experiment
echo "========================================="
echo "PHASE 1: Running Baseline Experiment"
echo "========================================="
echo "Duration: 30 seconds"
echo ""

./target/release/frankfurt-receiver \
    --mode baseline \
    --duration 30 \
    --output /tmp/baseline-results.json \
    --csv-output /tmp/baseline-measurements.csv

echo ""
echo "✓ Baseline experiment completed"
echo ""

# Run AWS backbone experiment
echo "========================================="
echo "PHASE 2: Running AWS Backbone Experiment"
echo "========================================="
echo "Duration: 30 seconds"
echo ""

# Start Frankfurt receiver
./target/release/frankfurt-receiver \
    --mode aws-backbone \
    --port 8080 \
    --duration 30 \
    --output /tmp/aws-backbone-results.json \
    --csv-output /tmp/aws-backbone-measurements.csv &
FRANKFURT_PID=$!

sleep 2

# Start Tokyo forwarder
timeout 35 ./target/release/tokyo-forwarder \
    --frankfurt-ip 127.0.0.1 \
    --frankfurt-port 8080 \
    > /tmp/tokyo-forwarder.log 2>&1 &
TOKYO_PID=$!

wait $FRANKFURT_PID 2>/dev/null || true
kill $TOKYO_PID 2>/dev/null || true
wait $TOKYO_PID 2>/dev/null || true

echo ""
echo "✓ AWS backbone experiment completed"
echo ""

# Compare results
echo "========================================="
echo "PHASE 3: Results Comparison"
echo "========================================="
echo ""

BASELINE_SAMPLES=$(jq -r '.sample_count' /tmp/baseline-results.json)
BASELINE_AVG=$(jq -r '.avg_latency_ms' /tmp/baseline-results.json)
BASELINE_MEDIAN=$(jq -r '.median_latency_ms' /tmp/baseline-results.json)
BASELINE_JITTER=$(jq -r '.jitter_stddev_ms' /tmp/baseline-results.json)

BACKBONE_SAMPLES=$(jq -r '.sample_count' /tmp/aws-backbone-results.json)
BACKBONE_AVG=$(jq -r '.avg_latency_ms' /tmp/aws-backbone-results.json)
BACKBONE_MEDIAN=$(jq -r '.median_latency_ms' /tmp/aws-backbone-results.json)
BACKBONE_JITTER=$(jq -r '.jitter_stddev_ms' /tmp/aws-backbone-results.json)
BACKBONE_HOP_AVG=$(jq -r '.backbone_avg_latency_ms' /tmp/aws-backbone-results.json)
EVENTS_LOST=$(jq -r '.events_lost' /tmp/aws-backbone-results.json)

echo "=== Baseline Results ==="
echo "Samples: $BASELINE_SAMPLES"
echo "Avg latency: $BASELINE_AVG ms"
echo "Median latency: $BASELINE_MEDIAN ms"
echo "Jitter: $BASELINE_JITTER ms"
echo ""

echo "=== AWS Backbone Results ==="
echo "Samples: $BACKBONE_SAMPLES"
echo "Avg latency: $BACKBONE_AVG ms"
echo "Median latency: $BACKBONE_MEDIAN ms"
echo "Jitter: $BACKBONE_JITTER ms"
echo "Backbone hop: $BACKBONE_HOP_AVG ms"
echo "Events lost: $EVENTS_LOST"
echo ""

AVG_DIFF=$(echo "$BACKBONE_AVG - $BASELINE_AVG" | bc -l)
echo "=== Comparison ==="
echo "Latency difference: $AVG_DIFF ms"
echo ""

# Validation
if [ "$BASELINE_SAMPLES" -lt 10 ]; then
    echo "✗ FAILED: Too few baseline samples"
    exit 1
fi

if [ "$BACKBONE_SAMPLES" -lt 10 ]; then
    echo "✗ FAILED: Too few backbone samples"
    exit 1
fi

if (( $(echo "$BASELINE_AVG < 0 || $BASELINE_AVG > 10000" | bc -l) )); then
    echo "✗ FAILED: Baseline latency unreasonable"
    exit 1
fi

if (( $(echo "$BACKBONE_AVG < 0 || $BACKBONE_AVG > 10000" | bc -l) )); then
    echo "✗ FAILED: Backbone latency unreasonable"
    exit 1
fi

echo "✓ All validations passed"
echo ""
echo "=== Test Complete ✓ ==="

# Cleanup
rm -f /tmp/baseline-results.json /tmp/baseline-measurements.csv
rm -f /tmp/aws-backbone-results.json /tmp/aws-backbone-measurements.csv
rm -f /tmp/tokyo-forwarder.log
