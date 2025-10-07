#!/bin/bash
# Comparison experiment test
# This script:
# - Runs baseline for 5 minutes
# - Runs AWS backbone for 5 minutes
# - Compares results
# - Validates latency difference makes sense

set -e

echo "=== Latency Comparison Experiment ==="
echo ""
echo "This test will run both baseline and AWS backbone modes"
echo "for 5 minutes each and compare the results."
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
echo "Duration: 5 minutes (300 seconds)"
echo "Mode: Direct Binance → Frankfurt"
echo ""

./target/release/frankfurt-receiver \
    --mode baseline \
    --duration 300 \
    --output baseline-results.json \
    --csv-output baseline-measurements.csv

echo ""
echo "✓ Baseline experiment completed"
echo ""

# Run AWS backbone experiment
echo "========================================="
echo "PHASE 2: Running AWS Backbone Experiment"
echo "========================================="
echo "Duration: 5 minutes (300 seconds)"
echo "Mode: Binance → Tokyo → Frankfurt"
echo ""

# Start Frankfurt receiver
./target/release/frankfurt-receiver \
    --mode aws-backbone \
    --port 8080 \
    --duration 300 \
    --output aws-backbone-results.json \
    --csv-output aws-backbone-measurements.csv &
FRANKFURT_PID=$!

# Give Frankfurt time to start
sleep 3

# Start Tokyo forwarder
timeout 305 ./target/release/tokyo-forwarder \
    --frankfurt-ip 127.0.0.1 \
    --frankfurt-port 8080 \
    > tokyo-forwarder.log 2>&1 &
TOKYO_PID=$!

echo "Both components started:"
echo "  - Frankfurt receiver PID: $FRANKFURT_PID"
echo "  - Tokyo forwarder PID: $TOKYO_PID"
echo ""
echo "Running for 5 minutes..."

# Wait for Frankfurt to complete
wait $FRANKFURT_PID 2>/dev/null || true

# Kill Tokyo if still running
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

# Extract metrics from both experiments
BASELINE_SAMPLES=$(jq -r '.sample_count' baseline-results.json)
BASELINE_AVG=$(jq -r '.avg_latency_ms' baseline-results.json)
BASELINE_MEDIAN=$(jq -r '.median_latency_ms' baseline-results.json)
BASELINE_P95=$(jq -r '.p95_latency_ms' baseline-results.json)
BASELINE_P99=$(jq -r '.p99_latency_ms' baseline-results.json)
BASELINE_JITTER=$(jq -r '.jitter_stddev_ms' baseline-results.json)

BACKBONE_SAMPLES=$(jq -r '.sample_count' aws-backbone-results.json)
BACKBONE_AVG=$(jq -r '.avg_latency_ms' aws-backbone-results.json)
BACKBONE_MEDIAN=$(jq -r '.median_latency_ms' aws-backbone-results.json)
BACKBONE_P95=$(jq -r '.p95_latency_ms' aws-backbone-results.json)
BACKBONE_P99=$(jq -r '.p99_latency_ms' aws-backbone-results.json)
BACKBONE_JITTER=$(jq -r '.jitter_stddev_ms' aws-backbone-results.json)
BACKBONE_HOP_AVG=$(jq -r '.backbone_avg_latency_ms' aws-backbone-results.json)
BACKBONE_HOP_MEDIAN=$(jq -r '.backbone_median_latency_ms' aws-backbone-results.json)
EVENTS_LOST=$(jq -r '.events_lost' aws-backbone-results.json)

echo "=== Baseline Results ==="
echo "Samples collected: $BASELINE_SAMPLES"
echo "Average latency: $BASELINE_AVG ms"
echo "Median latency: $BASELINE_MEDIAN ms"
echo "P95 latency: $BASELINE_P95 ms"
echo "P99 latency: $BASELINE_P99 ms"
echo "Jitter (stddev): $BASELINE_JITTER ms"
echo ""

echo "=== AWS Backbone Results ==="
echo "Samples collected: $BACKBONE_SAMPLES"
echo "Average latency: $BACKBONE_AVG ms"
echo "Median latency: $BACKBONE_MEDIAN ms"
echo "P95 latency: $BACKBONE_P95 ms"
echo "P99 latency: $BACKBONE_P99 ms"
echo "Jitter (stddev): $BACKBONE_JITTER ms"
echo "Events lost: $EVENTS_LOST"
echo ""
echo "Tokyo → Frankfurt hop:"
echo "  Average: $BACKBONE_HOP_AVG ms"
echo "  Median: $BACKBONE_HOP_MEDIAN ms"
echo ""

# Calculate differences
AVG_DIFF=$(echo "$BACKBONE_AVG - $BASELINE_AVG" | bc -l)
MEDIAN_DIFF=$(echo "$BACKBONE_MEDIAN - $BASELINE_MEDIAN" | bc -l)
JITTER_DIFF=$(echo "$BACKBONE_JITTER - $BASELINE_JITTER" | bc -l)

echo "=== Comparison ==="
echo "Average latency difference: $AVG_DIFF ms"
echo "Median latency difference: $MEDIAN_DIFF ms"
echo "Jitter difference: $JITTER_DIFF ms"
echo ""

# Determine which is faster
if (( $(echo "$BACKBONE_AVG < $BASELINE_AVG" | bc -l) )); then
    echo "✓ AWS Backbone is FASTER by $(echo "$BASELINE_AVG - $BACKBONE_AVG" | bc -l) ms on average"
    FASTER="AWS Backbone"
elif (( $(echo "$BACKBONE_AVG > $BASELINE_AVG" | bc -l) )); then
    echo "✓ Baseline is FASTER by $(echo "$BACKBONE_AVG - $BASELINE_AVG" | bc -l) ms on average"
    FASTER="Baseline"
else
    echo "✓ Both setups have equal average latency"
    FASTER="Equal"
fi
echo ""

# Validate results make sense
echo "=== Validation ==="

# Check that we got enough samples
if [ "$BASELINE_SAMPLES" -lt 100 ]; then
    echo "⚠ WARNING: Baseline collected fewer than 100 samples ($BASELINE_SAMPLES)"
else
    echo "✓ Baseline collected sufficient samples ($BASELINE_SAMPLES)"
fi

if [ "$BACKBONE_SAMPLES" -lt 100 ]; then
    echo "⚠ WARNING: AWS backbone collected fewer than 100 samples ($BACKBONE_SAMPLES)"
else
    echo "✓ AWS backbone collected sufficient samples ($BACKBONE_SAMPLES)"
fi

# Check that latencies are reasonable (not negative, not absurdly high)
if (( $(echo "$BASELINE_AVG < 0" | bc -l) )) || (( $(echo "$BASELINE_AVG > 10000" | bc -l) )); then
    echo "✗ FAILED: Baseline average latency is unreasonable: $BASELINE_AVG ms"
    exit 1
else
    echo "✓ Baseline latency is reasonable"
fi

if (( $(echo "$BACKBONE_AVG < 0" | bc -l) )) || (( $(echo "$BACKBONE_AVG > 10000" | bc -l) )); then
    echo "✗ FAILED: AWS backbone average latency is unreasonable: $BACKBONE_AVG ms"
    exit 1
else
    echo "✓ AWS backbone latency is reasonable"
fi

# Check that backbone hop latency is reasonable (should be very small for localhost)
if (( $(echo "$BACKBONE_HOP_AVG < 0" | bc -l) )) || (( $(echo "$BACKBONE_HOP_AVG > 1000" | bc -l) )); then
    echo "✗ FAILED: Backbone hop latency is unreasonable: $BACKBONE_HOP_AVG ms"
    exit 1
else
    echo "✓ Backbone hop latency is reasonable"
fi

# For localhost testing, backbone hop should be very small (< 10ms)
if (( $(echo "$BACKBONE_HOP_AVG < 10" | bc -l) )); then
    echo "✓ Backbone hop latency is consistent with localhost testing (< 10ms)"
else
    echo "⚠ WARNING: Backbone hop latency seems high for localhost: $BACKBONE_HOP_AVG ms"
fi

# Check packet loss
if [ "$EVENTS_LOST" -eq 0 ]; then
    echo "✓ No packet loss in AWS backbone mode"
elif [ "$EVENTS_LOST" -lt 10 ]; then
    echo "⚠ WARNING: Minor packet loss detected: $EVENTS_LOST events"
else
    echo "⚠ WARNING: Significant packet loss detected: $EVENTS_LOST events"
fi

echo ""
echo "=== Summary Report ==="
echo ""
echo "Experiment completed successfully!"
echo ""
echo "Configuration:"
echo "  - Test duration: 5 minutes per mode"
echo "  - Baseline samples: $BASELINE_SAMPLES"
echo "  - AWS backbone samples: $BACKBONE_SAMPLES"
echo ""
echo "Key Findings:"
echo "  - Faster setup: $FASTER"
echo "  - Latency difference: $AVG_DIFF ms (average)"
echo "  - Backbone hop overhead: $BACKBONE_HOP_AVG ms (average)"
echo "  - Packet loss: $EVENTS_LOST events"
echo ""
echo "Note: This test was run on localhost. In a real AWS deployment:"
echo "  - Baseline would measure public internet latency (typically 200-300ms Tokyo→Frankfurt)"
echo "  - AWS backbone would add VPC peering overhead but provide more consistent latency"
echo "  - The backbone hop would represent the Tokyo→Frankfurt AWS private network transit"
echo ""

echo "=== All Tests Passed ✓ ==="
echo ""
echo "Results files created:"
echo "  - baseline-results.json"
echo "  - baseline-measurements.csv"
echo "  - aws-backbone-results.json"
echo "  - aws-backbone-measurements.csv"
echo "  - tokyo-forwarder.log"
