# Design Document

## Overview

This experiment measures latency differences between two network paths for Binance WebSocket data delivery to Frankfurt. The system consists of Rust applications that connect to Binance WebSocket streams, measure timestamps, and calculate latency metrics. The design prioritizes simplicity and accurate time measurement.

## Architecture

### Baseline Architecture
```
Binance Tokyo WS → Internet → Frankfurt EC2 (Rust App)
```

### AWS Backbone Architecture
```
Binance Tokyo WS → Tokyo EC2 (Rust Forwarder) → VPC Peering (AWS Backbone) → Frankfurt EC2 (Rust Receiver)
```

### Key Design Decisions

1. **Rust Implementation**: Use Rust for performance, precise timing with `std::time::Instant`, and async WebSocket handling
2. **VPC Peering**: Use inter-region VPC Peering for the AWS backbone path (simple 1:1 connection, traffic stays on AWS private network)
3. **Phased Approach**: Start with Tokyo setup, validate, then add Frankfurt
4. **Precise Timing**: Use monotonic clocks (`Instant::now()`) for local measurements to avoid system clock drift
5. **Clock Synchronization**: Use NTP on both EC2 instances for accurate cross-region timestamp comparison
6. **Event Tracking**: Include sequence IDs in forwarded events to detect packet loss and match sent/received messages

## Components and Interfaces

### Component 1: Tokyo Forwarder (Rust)

**Purpose**: Connects to Binance WebSocket and forwards events to Frankfurt via VPC Peering

**Responsibilities**:
- Establish WebSocket connection to Binance Tokyo endpoint
- Subscribe to BTC/USDT book ticker stream (btcusdt@bookTicker)
- Record high-precision receive timestamp using `Instant::now()` and convert to epoch nanoseconds
- Assign incrementing sequence ID to each event
- Package event with timestamps and sequence ID
- Forward to Frankfurt EC2 via TCP connection through VPC peering
- Handle reconnection on failures

**Key Dependencies**:
- `tokio-tungstenite` for async WebSocket client
- `tokio` for async runtime
- `serde_json` for JSON parsing
- `chrono` for epoch timestamp conversion

**Configuration**:
- Binance WebSocket URL
- Frankfurt EC2 private IP address (via VPC peering)
- Frankfurt receiver port
- Stream symbols to subscribe

### Component 2: Frankfurt Receiver (Rust)

**Purpose**: Receives events from either Binance directly (baseline) or Tokyo forwarder (AWS backbone) and calculates latency

**Responsibilities**:
- **Baseline Mode**: Connect directly to Binance WebSocket (btcusdt@bookTicker)
- **AWS Backbone Mode**: Listen for TCP connections from Tokyo forwarder
- Record high-precision arrival timestamp using `Instant::now()` and convert to epoch nanoseconds
- Extract Binance event timestamp (field "E") from book ticker events
- Calculate end-to-end latency: (Frankfurt arrival - Binance event time)
- For AWS backbone: also calculate backbone latency: (Frankfurt arrival - Tokyo receive time)
- Track sequence IDs to detect packet loss
- Aggregate statistics: mean, median, p95, p99, min, max, jitter
- Output results in CSV and JSON formats

**Key Dependencies**:
- `tokio-tungstenite` for WebSocket (baseline mode)
- `tokio::net::TcpListener` for receiving forwarded data (AWS backbone mode)
- `serde_json` for JSON parsing
- `chrono` for timestamp handling

**Configuration**:
- Mode: baseline or aws-backbone
- Binance WebSocket URL (baseline mode)
- Listen port (AWS backbone mode)
- Stream symbols to subscribe

### Component 3: Infrastructure Setup Scripts

**Purpose**: Automate AWS infrastructure provisioning and configuration

**Responsibilities**:
- Launch EC2 instances in Tokyo and Frankfurt regions
- Configure security groups
- Set up AWS Global Accelerator
- Deploy Rust binaries to instances
- Tear down resources after experiment

**Technology**: Bash scripts with AWS CLI commands

## Data Models

### WebSocket Event (from Binance)
```rust
#[derive(Deserialize)]
struct BinanceBookTickerEvent {
    #[serde(rename = "e")]
    event_type: String,  // "bookTicker"
    
    #[serde(rename = "u")]
    update_id: i64,      // Order book updateId
    
    #[serde(rename = "E")]
    event_time: i64,     // Event time in milliseconds
    
    #[serde(rename = "T")]
    transaction_time: i64, // Transaction time in milliseconds
    
    #[serde(rename = "s")]
    symbol: String,      // Trading pair symbol (BTCUSDT)
    
    #[serde(rename = "b")]
    best_bid_price: String,  // Best bid price
    
    #[serde(rename = "B")]
    best_bid_qty: String,    // Best bid quantity
    
    #[serde(rename = "a")]
    best_ask_price: String,  // Best ask price
    
    #[serde(rename = "A")]
    best_ask_qty: String,    // Best ask quantity
}
```

### Forwarded Event (Tokyo → Frankfurt)
```rust
#[derive(Serialize, Deserialize)]
struct ForwardedEvent {
    sequence_id: u64,              // Incrementing event ID for tracking
    tokyo_receive_timestamp: i64,  // When Tokyo received from Binance (epoch nanos)
    binance_event_time: i64,       // Original Binance event time (E field)
    event_data: String,            // Raw JSON from Binance
}
```

### Latency Measurement
```rust
struct LatencyMeasurement {
    sequence_id: u64,
    binance_event_time: i64,       // Binance timestamp (ms)
    tokyo_receive_time: Option<i64>, // Only for AWS backbone mode (epoch nanos)
    frankfurt_receive_time: i64,   // Frankfurt arrival (epoch nanos)
    end_to_end_latency_ms: f64,    // Binance to Frankfurt
    backbone_latency_ms: Option<f64>, // Tokyo to Frankfurt (AWS backbone only)
}
```

### Experiment Results
```rust
struct ExperimentResults {
    setup_type: String,           // "baseline" or "aws-backbone"
    sample_count: usize,
    events_lost: usize,           // Missing sequence IDs
    
    // End-to-end latency (Binance → Frankfurt)
    avg_latency_ms: f64,
    median_latency_ms: f64,
    p95_latency_ms: f64,
    p99_latency_ms: f64,
    min_latency_ms: f64,
    max_latency_ms: f64,
    
    // Jitter (variance in latency)
    jitter_stddev_ms: f64,
    
    // AWS backbone specific (Tokyo → Frankfurt)
    backbone_avg_latency_ms: Option<f64>,
    backbone_median_latency_ms: Option<f64>,
}
```

## VPC Peering Setup Guide

### Step 1: Create VPCs
1. **Tokyo VPC** (ap-northeast-1):
   - CIDR: 10.0.0.0/16
   - Subnet: 10.0.1.0/24 (public subnet for EC2)
   
2. **Frankfurt VPC** (eu-central-1):
   - CIDR: 10.1.0.0/16
   - Subnet: 10.1.1.0/24 (public subnet for EC2)

### Step 2: Create VPC Peering Connection
1. Navigate to VPC console in Tokyo region
2. Go to "Peering Connections" → "Create Peering Connection"
3. Name: `tokyo-frankfurt-peering`
4. VPC (Requester): Tokyo VPC
5. Account: My account
6. Region: Another region → eu-central-1
7. VPC (Accepter): Frankfurt VPC ID
8. Click "Create Peering Connection"

### Step 3: Accept Peering Connection
1. Switch to Frankfurt region in VPC console
2. Go to "Peering Connections"
3. Select the pending peering connection
4. Click "Actions" → "Accept Request"

### Step 4: Update Route Tables
1. **Tokyo VPC Route Table**:
   - Add route: Destination `10.1.0.0/16` → Target: Peering Connection ID
   
2. **Frankfurt VPC Route Table**:
   - Add route: Destination `10.0.0.0/16` → Target: Peering Connection ID

### Step 5: Configure Security Groups
1. **Tokyo EC2 Security Group**:
   - Outbound: Allow TCP port 8080 to 10.1.0.0/16
   - Outbound: Allow HTTPS (443) for Binance WebSocket
   
2. **Frankfurt EC2 Security Group**:
   - Inbound: Allow TCP port 8080 from 10.0.0.0/16
   - Outbound: Allow HTTPS (443) for Binance WebSocket (baseline mode)

### Step 6: Test Connectivity
1. Launch EC2 instances in both VPCs
2. From Tokyo EC2, ping Frankfurt EC2 private IP
3. Verify connectivity over VPC peering

## Error Handling

### WebSocket Connection Failures
- Implement exponential backoff reconnection (1s, 2s, 4s, 8s, max 30s)
- Log all connection attempts and failures
- Continue experiment after reconnection

### TCP Connection Failures (Tokyo → Frankfurt)
- Retry connection with exponential backoff
- Buffer events in memory (with size limit) during disconnection
- Drop oldest events if buffer fills

### Invalid Data
- Skip events with missing or invalid timestamps
- Log parsing errors but continue processing
- Track count of invalid events for reporting

### Clock Synchronization
- Configure NTP (chrony) on both EC2 instances for accurate system time
- Use `SystemTime::now()` for epoch timestamps (synchronized via NTP)
- Use `Instant::now()` for monotonic local measurements (immune to clock adjustments)
- For end-to-end latency: compare Binance timestamp (ms) with Frankfurt system time
- For backbone latency: compare Tokyo receive time with Frankfurt receive time (both NTP-synced)
- Validate NTP sync status before starting experiments

## Testing Strategy

### Phase 1: Tokyo Setup Validation
1. Verify NTP synchronization on Tokyo EC2
2. Deploy Tokyo forwarder
3. Verify WebSocket connection to Binance
4. Confirm event reception and parsing
5. Validate JSON structure and timestamp extraction
6. Verify sequence ID assignment is working
7. Check timestamp recording accuracy

### Phase 2: Frankfurt Baseline Validation
1. Verify NTP synchronization on Frankfurt EC2
2. Deploy Frankfurt receiver in baseline mode
3. Verify direct WebSocket connection to Binance
4. Confirm latency calculation logic
5. Verify statistics calculation (mean, median, percentiles)
6. Collect sample measurements and validate output format

### Phase 3: AWS Backbone Validation
1. Set up VPC peering between Tokyo and Frankfurt
2. Test connectivity: ping Frankfurt private IP from Tokyo
3. Deploy Frankfurt receiver in AWS backbone mode
4. Start Tokyo forwarder pointing to Frankfurt private IP
5. Verify end-to-end event flow over VPC peering
6. Confirm sequence ID tracking and packet loss detection
7. Validate both end-to-end and backbone latency calculations

### Phase 4: Comparison
1. Run baseline setup for N minutes (e.g., 300 seconds)
2. Run AWS backbone setup for N minutes
3. Compare all metrics: mean, median, p95, p99, jitter
4. Analyze packet loss rates
5. Generate comparison report showing latency difference
6. Run experiments at different times of day to capture network variability
7. Validate results make sense (AWS backbone may add latency but should show lower jitter)

## Deployment Flow

### Initial Setup
1. Create Tokyo VPC (10.0.0.0/16) and Frankfurt VPC (10.1.0.0/16)
2. Set up inter-region VPC peering
3. Configure route tables for both VPCs
4. Launch Tokyo EC2 instance (t3.micro, ap-northeast-1) in Tokyo VPC
5. Launch Frankfurt EC2 instance (t3.micro, eu-central-1) in Frankfurt VPC
6. Configure security groups
7. Install and configure NTP (chrony) on both instances
8. Verify NTP synchronization with `chronyc tracking`
9. Build Rust binaries locally
10. Copy binaries and config files to EC2 instances via SCP

### Running Baseline Experiment
1. SSH to Frankfurt EC2
2. Run: `./frankfurt-receiver --mode baseline --duration 300`
3. Wait for completion
4. Retrieve results file

### Running AWS Backbone Experiment
1. SSH to Frankfurt EC2
2. Run: `./frankfurt-receiver --mode aws-backbone --port 8080 --duration 300`
3. SSH to Tokyo EC2
4. Run: `./tokyo-forwarder --frankfurt-ip <private-ip> --port 8080`
5. Wait for completion
6. Retrieve results from Frankfurt

### Teardown
1. Stop all running processes
2. Download result files
3. Terminate EC2 instances
4. Delete VPC peering connection
5. Delete VPCs and associated resources (subnets, route tables, security groups)

## Configuration Files

### tokyo-config.json
```json
{
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "frankfurt_private_ip": "10.1.1.10",
  "frankfurt_port": 8080,
  "reconnect_max_delay_secs": 30
}
```

### frankfurt-config.json
```json
{
  "mode": "baseline",
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "listen_port": 8080,
  "duration_secs": 300,
  "output_file": "results.json"
}
```

## Performance Considerations

- Use async I/O throughout to handle high-frequency events
- Minimize processing in hot path (timestamp recording should be first operation)
- Use `Instant::now()` immediately upon receiving data for accuracy
- Buffer writes to disk to avoid I/O blocking measurement
- Use efficient JSON parsing (serde_json is fast)
- Keep memory footprint small (streaming processing, no large buffers)
- Use lightweight serialization for forwarded events (JSON with minimal fields)
- Batch statistics calculations at end rather than per-event

## Expected Results

Based on typical network characteristics:
- **Baseline**: ~200-250ms (Tokyo to Frankfurt over public internet)
- **AWS Backbone**: ~220-280ms (extra hop through Tokyo EC2 + Global Accelerator processing)

The AWS backbone may show slightly higher latency due to the additional hop, but should demonstrate more consistent latency (lower jitter) due to AWS's private network via VPC peering. The experiment will reveal the actual difference.
