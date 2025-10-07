# Implementation Plan

- [x] 1. Set up Rust project structure
  - Create Cargo workspace with two binary crates: `tokyo-forwarder` and `frankfurt-receiver`
  - Add shared library crate for common data structures
  - Configure dependencies: tokio, tokio-tungstenite, serde, serde_json, chrono
  - _Requirements: 5.4_

- [x] 2. Implement shared data structures
  - [x] 2.1 Create BinanceBookTickerEvent struct with serde deserialization
    - Define struct matching Binance book ticker JSON format
    - Add serde rename attributes for field mapping (e, u, E, T, s, b, B, a, A)
    - _Requirements: 1.3, 2.2_
  
  - [x] 2.2 Create ForwardedEvent struct for Tokyo → Frankfurt communication
    - Include sequence_id, tokyo_receive_timestamp, binance_event_time, event_data fields
    - Implement serde Serialize and Deserialize
    - _Requirements: 2.2, 3.1_
  
  - [x] 2.3 Create LatencyMeasurement struct
    - Include sequence_id, timestamps, and calculated latencies
    - Add methods for calculating latency from timestamps
    - _Requirements: 3.1, 3.2, 3.3_
  
  - [x] 2.4 Create ExperimentResults struct
    - Include all statistics fields: mean, median, p95, p99, min, max, jitter, packet loss
    - Implement methods to calculate statistics from Vec<LatencyMeasurement>
    - Add JSON serialization for output
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [x] 3. Implement Tokyo forwarder application
  - [x] 3.1 Create main.rs with CLI argument parsing
    - Parse config file path or command-line arguments
    - Load configuration (Binance URL, Frankfurt IP, port)
    - _Requirements: 5.1, 5.2_
  
  - [x] 3.2 Implement WebSocket connection to Binance
    - Connect to wss://stream.binance.com:9443/ws/btcusdt@bookTicker
    - Handle TLS connection
    - Implement message receiving loop
    - _Requirements: 1.1, 2.1_
  
  - [x] 3.3 Implement timestamp recording on event receipt
    - Record SystemTime::now() immediately upon receiving WebSocket message
    - Convert to epoch nanoseconds
    - Parse JSON to extract Binance event time (E field)
    - _Requirements: 2.2, 3.1_
  
  - [x] 3.4 Implement sequence ID assignment
    - Maintain atomic counter for sequence IDs
    - Assign incrementing ID to each event
    - _Requirements: 3.1_
  
  - [x] 3.5 Implement TCP connection to Frankfurt
    - Connect to Frankfurt EC2 private IP on configured port
    - Maintain persistent connection
    - _Requirements: 2.2, 2.3_
  
  - [x] 3.6 Implement event forwarding
    - Create ForwardedEvent with sequence ID, timestamps, and raw data
    - Serialize to JSON
    - Send over TCP connection with newline delimiter
    - _Requirements: 2.3_
  
  - [x] 3.7 Implement reconnection logic
    - Add exponential backoff for WebSocket reconnection
    - Add exponential backoff for TCP reconnection
    - Log connection attempts and failures
    - _Requirements: 2.4_

- [x] 4. Implement Frankfurt receiver - baseline mode
  - [x] 4.1 Create main.rs with CLI argument parsing
    - Parse mode (baseline or aws-backbone), duration, output file
    - Load configuration
    - _Requirements: 5.3_
  
  - [x] 4.2 Implement WebSocket connection to Binance (baseline mode)
    - Connect to wss://stream.binance.com:9443/ws/btcusdt@bookTicker
    - Handle TLS connection
    - Implement message receiving loop
    - _Requirements: 1.1, 1.2_
  
  - [x] 4.3 Implement timestamp recording on event receipt (baseline mode)
    - Record SystemTime::now() immediately upon receiving WebSocket message
    - Convert to epoch nanoseconds
    - Parse JSON to extract Binance event time (E field)
    - _Requirements: 1.3, 3.1_
  
  - [x] 4.4 Implement latency calculation (baseline mode)
    - Calculate end-to-end latency: (Frankfurt arrival - Binance event time)
    - Convert to milliseconds
    - Store in LatencyMeasurement struct
    - _Requirements: 1.4, 3.1_
  
  - [x] 4.5 Implement data collection with duration limit
    - Collect measurements for specified duration
    - Store in Vec<LatencyMeasurement>
    - Gracefully shutdown after duration expires
    - _Requirements: 3.3_

- [x] 5. Implement Frankfurt receiver - AWS backbone mode
  - [x] 5.1 Implement TCP listener for Tokyo forwarder
    - Bind to configured port
    - Accept connection from Tokyo EC2
    - _Requirements: 2.2, 2.5_
  
  - [x] 5.2 Implement event reception from Tokyo
    - Read newline-delimited JSON from TCP stream
    - Deserialize ForwardedEvent
    - Record Frankfurt arrival timestamp immediately
    - _Requirements: 2.5, 3.1_
  
  - [x] 5.3 Implement latency calculation (AWS backbone mode)
    - Calculate end-to-end latency: (Frankfurt arrival - Binance event time)
    - Calculate backbone latency: (Frankfurt arrival - Tokyo receive time)
    - Store both in LatencyMeasurement struct
    - _Requirements: 2.4, 3.1_
  
  - [x] 5.4 Implement sequence ID tracking
    - Track received sequence IDs
    - Detect gaps in sequence to identify packet loss
    - Count missing events
    - _Requirements: 3.3_

- [x] 6. Implement statistics calculation and output
  - [x] 6.1 Implement statistics calculation
    - Sort latency measurements
    - Calculate mean, median (p50), p95, p99
    - Calculate min and max
    - Calculate standard deviation for jitter
    - _Requirements: 3.4, 4.1, 4.2_
  
  - [x] 6.2 Implement results output
    - Create ExperimentResults struct with calculated statistics
    - Serialize to JSON
    - Write to output file
    - Print summary to console
    - _Requirements: 4.1, 4.2, 4.3, 4.4_
  
  - [x] 6.3 Implement CSV output for raw measurements
    - Write all LatencyMeasurement records to CSV
    - Include headers: sequence_id, binance_time, tokyo_time, frankfurt_time, latency_ms
    - _Requirements: 4.1_

- [x] 7. Create infrastructure setup scripts
  - [x] 7.1 Create VPC setup script
    - Script to create Tokyo VPC (10.0.0.0/16) with subnet
    - Script to create Frankfurt VPC (10.1.0.0/16) with subnet
    - Script to create internet gateways and route tables
    - _Requirements: 7.1, 7.2_
  
  - [x] 7.2 Create VPC peering setup script
    - Script to create peering connection from Tokyo to Frankfurt
    - Script to accept peering connection in Frankfurt
    - Script to update route tables in both VPCs
    - _Requirements: 6.2, 6.3, 6.4, 7.2_
  
  - [x] 7.3 Create EC2 launch script
    - Script to launch Tokyo EC2 instance in Tokyo VPC
    - Script to launch Frankfurt EC2 instance in Frankfurt VPC
    - Configure security groups (WebSocket, TCP forwarding, SSH)
    - _Requirements: 7.1, 7.2_
  
  - [x] 7.4 Create NTP setup script
    - Script to install and configure chrony on both instances
    - Script to verify NTP synchronization
    - _Requirements: 6.5_
  
  - [x] 7.5 Create deployment script
    - Script to build Rust binaries
    - Script to copy binaries to EC2 instances via SCP
    - Script to copy config files
    - _Requirements: 7.3_
  
  - [x] 7.6 Create teardown script
    - Script to terminate EC2 instances
    - Script to delete VPC peering connection
    - Script to delete VPCs and associated resources
    - _Requirements: 7.4_

- [x] 8. Create configuration files
  - [x] 8.1 Create tokyo-config.json template
    - Include Binance WebSocket URL (btcusdt@bookTicker)
    - Include Frankfurt private IP placeholder
    - Include port configuration
    - _Requirements: 5.2_
  
  - [x] 8.2 Create frankfurt-config.json template
    - Include mode selection (baseline/aws-backbone)
    - Include Binance WebSocket URL
    - Include listen port and duration
    - Include output file path
    - _Requirements: 5.2_

- [x] 9. Create documentation
  - [x] 9.1 Create README with setup instructions
    - Document prerequisites (AWS CLI, Rust, SSH keys)
    - Document step-by-step setup process
    - Document how to run experiments
    - Document how to interpret results
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_
  
  - [x] 9.2 Create VPC peering setup guide
    - Document manual VPC peering setup steps
    - Include screenshots or detailed CLI commands
    - Document troubleshooting common issues
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [ ] 10. Integration and end-to-end testing
  - [x] 10.1 Test Tokyo forwarder standalone
    - Verify WebSocket connection to Binance
    - Verify event parsing and timestamp recording
    - Verify sequence ID assignment
    - _Requirements: 5.1_
  
  - [x] 10.2 Test Frankfurt receiver in baseline mode
    - Verify WebSocket connection to Binance
    - Verify latency calculation
    - Verify statistics output
    - _Requirements: 5.1_
  
  - [x] 10.3 Test end-to-end AWS backbone flow
    - Set up VPC peering
    - Run Tokyo forwarder and Frankfurt receiver together
    - Verify event forwarding over VPC peering
    - Verify sequence tracking and packet loss detection
    - Verify statistics output
    - _Requirements: 5.1_
  
  - [x] 10.4 Run comparison experiment
    - Run baseline for 5 minutes
    - Run AWS backbone for 5 minutes
    - Compare results
    - Validate latency difference makes sense
    - _Requirements: 5.1_
