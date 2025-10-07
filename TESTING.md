# Testing Guide

This document describes the test suite for the Binance Latency Experiment project.

## Overview

The project includes comprehensive integration tests that verify all components work correctly both individually and together.

## Test Scripts

### 1. Tokyo Forwarder Standalone Test

**Script**: `scripts/test-tokyo-forwarder.sh`

**Purpose**: Verifies the Tokyo forwarder can connect to Binance and forward events.

**What it tests**:
- WebSocket connection to Binance
- Event parsing and validation
- Timestamp recording
- Sequence ID assignment
- TCP forwarding to Frankfurt

**How to run**:
```bash
./scripts/test-tokyo-forwarder.sh
```

**Duration**: ~15 seconds

**Expected output**:
- Successful WebSocket connection
- Multiple events forwarded (typically 5000-10000 in 15 seconds)
- Valid JSON structure with all required fields
- Incrementing sequence IDs

### 2. Frankfurt Receiver Baseline Test

**Script**: `scripts/test-frankfurt-baseline.sh`

**Purpose**: Verifies the Frankfurt receiver works in baseline mode.

**What it tests**:
- WebSocket connection to Binance
- Latency calculation
- Statistics generation (avg, median, p95, p99, jitter)
- JSON output format
- CSV output format

**How to run**:
```bash
./scripts/test-frankfurt-baseline.sh
```

**Duration**: ~10 seconds

**Expected output**:
- Successful WebSocket connection
- 2000-3000 samples collected
- Valid statistics in JSON format
- CSV file with measurements

### 3. AWS Backbone End-to-End Test

**Script**: `scripts/test-aws-backbone.sh`

**Purpose**: Verifies the complete Tokyo → Frankfurt flow.

**What it tests**:
- Tokyo forwarder → Frankfurt receiver TCP connection
- Event forwarding over TCP
- Sequence tracking
- Packet loss detection
- Backbone latency calculation
- Statistics output

**How to run**:
```bash
./scripts/test-aws-backbone.sh
```

**Duration**: ~15 seconds

**Expected output**:
- Both components start successfully
- TCP connection established
- 3000-4000 samples collected
- Zero or minimal packet loss
- Backbone latency metrics populated

### 4. Comparison Experiment Test (Quick)

**Script**: `scripts/test-comparison-quick.sh`

**Purpose**: Runs both baseline and AWS backbone modes and compares results.

**What it tests**:
- Both modes work correctly
- Results are comparable
- Latency values are reasonable
- Statistics are calculated correctly

**How to run**:
```bash
./scripts/test-comparison-quick.sh
```

**Duration**: ~60 seconds (30 seconds per mode)

**Expected output**:
- Both experiments complete successfully
- Comparison shows latency difference
- All validations pass

### 5. Full Comparison Experiment

**Script**: `scripts/test-comparison.sh`

**Purpose**: Full 5-minute comparison experiment (as designed for production use).

**What it tests**:
- Long-running stability
- Large sample collection
- Statistical significance

**How to run**:
```bash
./scripts/test-comparison.sh
```

**Duration**: ~10 minutes (5 minutes per mode)

**Expected output**:
- 50,000+ samples per mode
- Comprehensive statistics
- Detailed comparison report

## Running All Tests

To run all tests in sequence:

```bash
# Quick validation (< 2 minutes)
./scripts/test-tokyo-forwarder.sh && \
./scripts/test-frankfurt-baseline.sh && \
./scripts/test-aws-backbone.sh

# Full test suite including comparison (< 2 minutes)
./scripts/test-tokyo-forwarder.sh && \
./scripts/test-frankfurt-baseline.sh && \
./scripts/test-aws-backbone.sh && \
./scripts/test-comparison-quick.sh
```

## Test Results Interpretation

### Success Criteria

All tests should:
- ✓ Complete without errors
- ✓ Establish network connections successfully
- ✓ Collect sufficient samples (>100 for short tests, >1000 for longer tests)
- ✓ Generate valid JSON and CSV output
- ✓ Show reasonable latency values (0-10ms for localhost, 200-300ms for real AWS)
- ✓ Have minimal packet loss (<1%)

### Common Issues

#### 1. No Events Received

**Symptom**: Test reports 0 events collected

**Possible causes**:
- Binance WebSocket stream is down
- Network connectivity issues
- Firewall blocking WebSocket connections

**Solution**:
- Check Binance API status
- Verify internet connectivity
- Try accessing the WebSocket URL manually

#### 2. Parsing Errors

**Symptom**: "Failed to parse Binance event" messages

**Possible causes**:
- Binance changed their API format
- Wrong WebSocket stream endpoint

**Solution**:
- Check Binance API documentation
- Verify the WebSocket URL is correct
- Update the `BinanceBookTickerEvent` struct if needed

#### 3. Connection Refused

**Symptom**: "Connection refused" when Tokyo tries to connect to Frankfurt

**Possible causes**:
- Frankfurt receiver not started
- Wrong port number
- Firewall blocking connection

**Solution**:
- Ensure Frankfurt receiver starts first
- Verify port 8080 is available
- Check firewall rules

#### 4. High Packet Loss

**Symptom**: `events_lost` > 1% of samples

**Possible causes**:
- Network congestion
- CPU overload
- Buffer overflow

**Solution**:
- Check system resources (CPU, memory, network)
- Reduce test duration
- Use more powerful hardware

## Localhost vs AWS Testing

### Localhost Testing

The test scripts run on localhost and show:
- Very low latency (< 1ms for backbone hop)
- Near-zero packet loss
- High throughput

This validates:
- ✓ Code correctness
- ✓ Protocol implementation
- ✓ Data structures
- ✓ Statistics calculation

### AWS Testing

Real AWS deployment will show:
- Higher latency (200-300ms end-to-end)
- Backbone hop latency (170-230ms Tokyo → Frankfurt)
- Potential packet loss (< 0.1% typically)
- Network jitter

This validates:
- ✓ Real-world performance
- ✓ VPC peering effectiveness
- ✓ Geographic latency impact
- ✓ AWS network reliability

## Continuous Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
      - name: Build
        run: cargo build --release
      - name: Test Tokyo Forwarder
        run: ./scripts/test-tokyo-forwarder.sh
      - name: Test Frankfurt Baseline
        run: ./scripts/test-frankfurt-baseline.sh
      - name: Test AWS Backbone
        run: ./scripts/test-aws-backbone.sh
```

## Manual Testing

For manual testing and debugging:

### Test Tokyo Forwarder Manually

```bash
# Start a listener
nc -l 8080 > output.txt &

# Run forwarder
./target/release/tokyo-forwarder \
  --frankfurt-ip 127.0.0.1 \
  --frankfurt-port 8080

# Check output
cat output.txt | head -5 | jq .
```

### Test Frankfurt Receiver Manually

```bash
# Baseline mode
./target/release/frankfurt-receiver \
  --mode baseline \
  --duration 30 \
  --output test-results.json

# AWS backbone mode
./target/release/frankfurt-receiver \
  --mode aws-backbone \
  --port 8080 \
  --duration 30 \
  --output test-results.json
```

## Troubleshooting Tests

### Enable Debug Logging

Add debug output to see what's happening:

```bash
# Set Rust log level
export RUST_LOG=debug

# Run test
./scripts/test-tokyo-forwarder.sh
```

### Check Test Artifacts

Tests create temporary files in `/tmp`:
- `/tmp/tokyo-test-output.txt` - Raw forwarded events
- `/tmp/tokyo-forwarder.log` - Forwarder logs
- `/tmp/frankfurt-baseline.log` - Receiver logs
- `/tmp/baseline-results.json` - Results JSON
- `/tmp/baseline-measurements.csv` - Raw measurements

### Verify Binance Connection

Test Binance WebSocket directly:

```bash
# Using websocat (install: brew install websocat)
websocat "wss://stream.binance.com:9443/ws/btcusdt@bookTicker" | head -5

# Or using wscat (install: npm install -g wscat)
wscat -c "wss://stream.binance.com:9443/ws/btcusdt@bookTicker"
```

## Performance Benchmarks

Expected performance on modern hardware:

| Metric | Localhost | AWS (Real) |
|--------|-----------|------------|
| Events/sec | 300-500 | 300-500 |
| Baseline latency | 0.5ms | 200-250ms |
| Backbone latency | 0.6ms | 220-280ms |
| Backbone hop | 0.1ms | 170-230ms |
| Packet loss | 0% | <0.1% |
| CPU usage | <5% | <10% |
| Memory usage | <50MB | <50MB |

## Test Coverage

The test suite covers:

- ✓ WebSocket connectivity
- ✓ Event parsing
- ✓ Timestamp recording
- ✓ Sequence ID assignment
- ✓ TCP forwarding
- ✓ Latency calculation
- ✓ Statistics generation
- ✓ Packet loss detection
- ✓ JSON output format
- ✓ CSV output format
- ✓ Error handling
- ✓ Connection recovery
- ✓ End-to-end flow

Not covered (requires manual testing):
- VPC peering setup
- EC2 deployment
- NTP synchronization
- Long-term stability (>1 hour)
- High load scenarios
- Network failure recovery

## Next Steps

After all tests pass:

1. Deploy to AWS using `./scripts/setup-ec2.sh`
2. Run real experiments with 5-minute durations
3. Analyze results and compare with localhost tests
4. Document any differences in performance
5. Optimize based on findings

## Support

If tests fail or you encounter issues:

1. Check this troubleshooting guide
2. Review test logs in `/tmp`
3. Verify prerequisites are installed
4. Check Binance API status
5. Open an issue with test output and logs
