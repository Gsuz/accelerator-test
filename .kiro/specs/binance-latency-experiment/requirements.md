# Requirements Document

## Introduction

This feature implements a simple latency comparison experiment to measure the millisecond difference between two network paths for receiving Binance WebSocket events at a Frankfurt EC2 instance. The baseline setup connects directly from Binance's Tokyo WebSocket to Frankfurt over the public internet, while the AWS Backbone setup routes through a Tokyo EC2 instance using AWS's private network via Global Accelerator. The goal is to determine which path has lower latency. All code will be written in Rust.

## Requirements

### Requirement 1: Baseline Setup

**User Story:** As an experimenter, I want to measure latency from Binance Tokyo WebSocket directly to Frankfurt EC2, so that I have a baseline measurement.

#### Acceptance Criteria

1. WHEN the baseline setup runs THEN the system SHALL connect a Frankfurt EC2 instance to Binance Tokyo WebSocket
2. WHEN WebSocket events are received THEN the system SHALL record the arrival timestamp in milliseconds
3. WHEN events contain Binance exchange timestamps THEN the system SHALL extract them for latency calculation
4. WHEN calculating latency THEN the system SHALL compute the difference between Binance timestamp and Frankfurt arrival time in milliseconds

### Requirement 2: AWS Backbone Setup

**User Story:** As an experimenter, I want to measure latency from Binance Tokyo WebSocket through Tokyo EC2 to Frankfurt EC2 via AWS private network, so that I can compare it to the baseline.

#### Acceptance Criteria

1. WHEN the AWS Backbone setup runs THEN the system SHALL connect Tokyo EC2 to Binance Tokyo WebSocket
2. WHEN Tokyo EC2 receives events THEN the system SHALL forward them to Frankfurt EC2 via AWS private network
3. WHEN Frankfurt EC2 receives forwarded events THEN the system SHALL record the arrival timestamp in milliseconds
4. WHEN calculating latency THEN the system SHALL compute the difference between Binance timestamp and Frankfurt arrival time in milliseconds

### Requirement 3: Latency Measurement

**User Story:** As an experimenter, I want accurate latency measurements in milliseconds, so that I can compare the two setups.

#### Acceptance Criteria

1. WHEN events are received THEN the system SHALL calculate latency as (Frankfurt arrival time - Binance exchange time) in milliseconds
2. WHEN collecting measurements THEN the system SHALL record latency for each event
3. WHEN the experiment runs THEN the system SHALL collect at least 100 latency samples per setup
4. WHEN measurements are complete THEN the system SHALL calculate average latency in milliseconds for each setup

### Requirement 4: Results Output

**User Story:** As an experimenter, I want to see the latency difference between the two setups, so that I know which is faster.

#### Acceptance Criteria

1. WHEN both setups have collected data THEN the system SHALL output the average latency for baseline setup in milliseconds
2. WHEN both setups have collected data THEN the system SHALL output the average latency for AWS backbone setup in milliseconds
3. WHEN displaying results THEN the system SHALL show the difference in milliseconds between the two setups
4. WHEN displaying results THEN the system SHALL indicate which setup has lower latency

### Requirement 5: Tokyo Setup First

**User Story:** As an experimenter, I want to start with the Tokyo setup, so that I can validate the connection to Binance before building the full experiment.

#### Acceptance Criteria

1. WHEN starting the experiment THEN the system SHALL first set up and test the Tokyo EC2 instance connection to Binance
2. WHEN Tokyo setup is complete THEN the system SHALL verify WebSocket connectivity and data reception
3. WHEN Tokyo is validated THEN the system SHALL proceed to Frankfurt setup
4. WHEN implementing THEN the system SHALL use Rust for all application code

### Requirement 6: AWS Global Accelerator Configuration

**User Story:** As an experimenter, I want clear guidance on setting up AWS Global Accelerator between Tokyo and Frankfurt, so that I can establish the AWS backbone connection.

#### Acceptance Criteria

1. WHEN setting up Global Accelerator THEN the system SHALL provide documentation on creating a Global Accelerator endpoint
2. WHEN configuring listeners THEN the system SHALL document how to set up TCP listeners for the forwarding connection
3. WHEN configuring endpoint groups THEN the system SHALL document how to add Frankfurt EC2 as a target
4. WHEN Tokyo forwards data THEN the system SHALL connect to the Global Accelerator endpoint instead of directly to Frankfurt
5. WHEN documenting setup THEN the system SHALL include step-by-step instructions for Global Accelerator configuration

### Requirement 7: Basic Infrastructure

**User Story:** As an experimenter, I want simple scripts to set up and run the experiment, so that I can execute it easily.

#### Acceptance Criteria

1. WHEN setting up infrastructure THEN the system SHALL provide scripts to launch EC2 instances in required regions
2. WHEN setting up networking THEN the system SHALL configure security groups to allow WebSocket and inter-instance communication
3. WHEN running the experiment THEN the system SHALL provide Rust binaries to start data collection on each instance
4. WHEN the experiment completes THEN the system SHALL provide a script to retrieve results and tear down infrastructure
