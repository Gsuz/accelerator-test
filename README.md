# Binance Latency Experiment

A Rust-based experiment to measure and compare network latency between two paths for receiving Binance WebSocket events at a Frankfurt EC2 instance:

1. **Baseline**: Direct connection from Binance to Frankfurt over public internet
2. **AWS Backbone**: Route through Tokyo EC2 using AWS VPC Peering private network

## Prerequisites

### Required Tools

- **AWS CLI** (v2.x or later)
  ```bash
  # Install on macOS
  brew install awscli
  
  # Verify installation
  aws --version
  ```

- **Rust** (1.70 or later)
  ```bash
  # Install via rustup
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  
  # Verify installation
  rustc --version
  cargo --version
  ```

- **SSH Key Pair**
  ```bash
  # Generate if you don't have one
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/binance-experiment
  ```

### AWS Configuration

1. Configure AWS CLI with credentials:
   ```bash
   aws configure
   ```
   
2. Ensure you have permissions for:
   - EC2 (launch instances, manage security groups)
   - VPC (create VPCs, subnets, peering connections)
   - IAM (if creating roles)

3. Upload your SSH public key to both regions:
   ```bash
   # Tokyo region
   aws ec2 import-key-pair --key-name binance-experiment \
     --public-key-material fileb://~/.ssh/binance-experiment.pub \
     --region ap-northeast-1
   
   # Frankfurt region
   aws ec2 import-key-pair --key-name binance-experiment \
     --public-key-material fileb://~/.ssh/binance-experiment.pub \
     --region eu-central-1
   ```

## Setup Process

### Step 1: Build Rust Binaries

Build the applications locally:

```bash
cargo build --release
```

This creates two binaries:
- `target/release/tokyo-forwarder`
- `target/release/frankfurt-receiver`

### Step 2: Create SSH Key Pair

Create the SSH key pair needed for EC2 instances:

```bash
./scripts/create-keypair.sh
```

This script:
- Creates a key pair named `binance-latency-key` in both regions
- Saves the private key to `~/.ssh/binance-latency-key.pem`
- Sets proper permissions (400) on the key file

**Note**: If you already have a key pair you want to use, you can skip this step and modify the `KEY_NAME` variable in `setup-ec2.sh`.

### Step 3: Set Up AWS Infrastructure

Run the setup scripts in order:

```bash
# 1. Create VPCs in both regions
./scripts/setup-vpc.sh

# 2. Set up VPC peering connection
./scripts/setup-vpc-peering.sh

# 3. Launch EC2 instances
./scripts/setup-ec2.sh

# 4. Configure NTP for time synchronization
./scripts/setup-ntp.sh
```

**Important**: Note the private IP addresses output by `setup-ec2.sh`. You'll need these for configuration.

### Step 3: Update Configuration Files

Edit the configuration files with your EC2 private IPs:

**tokyo-config.json**:
```json
{
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "frankfurt_private_ip": "10.1.1.XXX",
  "frankfurt_port": 8080,
  "reconnect_max_delay_secs": 30
}
```

**frankfurt-config.json**:
```json
{
  "mode": "baseline",
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "listen_port": 8080,
  "duration_secs": 300,
  "output_file": "results.json"
}
```

### Step 4: Deploy Applications

Deploy the binaries and configuration to EC2 instances:

```bash
./scripts/deploy.sh
```

This script:
- Copies binaries to both EC2 instances
- Copies configuration files
- Sets executable permissions

## Running Experiments

### Baseline Experiment

Measures latency from Binance directly to Frankfurt over public internet.

1. SSH to Frankfurt EC2:
   ```bash
   ssh -i ~/.ssh/binance-experiment ec2-user@<frankfurt-public-ip>
   ```

2. Run the receiver in baseline mode:
   ```bash
   ./frankfurt-receiver --mode baseline --duration 300 --output baseline-results.json
   ```

3. Wait for completion (5 minutes)

4. Download results:
   ```bash
   scp -i ~/.ssh/binance-experiment \
     ec2-user@<frankfurt-public-ip>:baseline-results.json \
     ./baseline-results.json
   
   scp -i ~/.ssh/binance-experiment \
     ec2-user@<frankfurt-public-ip>:baseline-results.csv \
     ./baseline-results.csv
   ```

### AWS Backbone Experiment

Measures latency routing through Tokyo EC2 via AWS VPC Peering.

1. SSH to Frankfurt EC2:
   ```bash
   ssh -i ~/.ssh/binance-experiment ec2-user@<frankfurt-public-ip>
   ```

2. Start the receiver in AWS backbone mode:
   ```bash
   ./frankfurt-receiver --mode aws-backbone --port 8080 --duration 300 --output backbone-results.json
   ```

3. In a new terminal, SSH to Tokyo EC2:
   ```bash
   ssh -i ~/.ssh/binance-experiment ec2-user@<tokyo-public-ip>
   ```

4. Start the forwarder:
   ```bash
   ./tokyo-forwarder
   ```

5. Wait for completion (5 minutes)

6. Download results from Frankfurt:
   ```bash
   scp -i ~/.ssh/binance-experiment \
     ec2-user@<frankfurt-public-ip>:backbone-results.json \
     ./backbone-results.json
   
   scp -i ~/.ssh/binance-experiment \
     ec2-user@<frankfurt-public-ip>:backbone-results.csv \
     ./backbone-results.csv
   ```

## Interpreting Results

### JSON Output Format

Both experiments produce JSON files with the following structure:

```json
{
  "setup_type": "baseline",
  "sample_count": 18234,
  "events_lost": 0,
  "avg_latency_ms": 245.67,
  "median_latency_ms": 243.21,
  "p95_latency_ms": 289.45,
  "p99_latency_ms": 312.78,
  "min_latency_ms": 198.34,
  "max_latency_ms": 456.12,
  "jitter_stddev_ms": 23.45,
  "backbone_avg_latency_ms": null,
  "backbone_median_latency_ms": null
}
```

### Key Metrics

- **avg_latency_ms**: Mean latency across all samples
- **median_latency_ms**: 50th percentile (p50) - middle value
- **p95_latency_ms**: 95th percentile - 95% of requests faster than this
- **p99_latency_ms**: 99th percentile - 99% of requests faster than this
- **min/max_latency_ms**: Best and worst case latencies
- **jitter_stddev_ms**: Standard deviation - measures consistency (lower is better)
- **events_lost**: Number of missing sequence IDs (packet loss)
- **backbone_avg_latency_ms**: Tokyo→Frankfurt latency (AWS backbone mode only)

### CSV Output Format

Raw measurements are saved to CSV for detailed analysis:

```csv
sequence_id,binance_time,tokyo_time,frankfurt_time,end_to_end_latency_ms,backbone_latency_ms
1,1704672345123,1704672345234000000,1704672345456000000,333.0,222.0
2,1704672345234,1704672345345000000,1704672345567000000,333.0,222.0
```

### Comparison Analysis

Compare the two experiments:

1. **Latency Difference**:
   ```
   Difference = AWS Backbone avg_latency_ms - Baseline avg_latency_ms
   ```
   - Negative value: AWS backbone is faster
   - Positive value: Baseline is faster

2. **Consistency (Jitter)**:
   - Lower `jitter_stddev_ms` indicates more consistent latency
   - AWS backbone typically shows lower jitter due to private network

3. **Reliability**:
   - Check `events_lost` for packet loss
   - Lower packet loss indicates more reliable connection

4. **Percentile Analysis**:
   - Compare p95 and p99 values
   - High percentiles reveal worst-case performance
   - Important for latency-sensitive applications

### Expected Results

Typical observations:

- **Baseline**: 200-250ms average, higher jitter
- **AWS Backbone**: 220-280ms average, lower jitter
- AWS backbone may add 20-30ms due to extra hop through Tokyo EC2
- AWS backbone should show 30-50% lower jitter (more consistent)
- Packet loss should be minimal (<0.1%) for both setups

### Visualization

You can visualize the CSV data using tools like:

```python
import pandas as pd
import matplotlib.pyplot as plt

# Load data
baseline = pd.read_csv('baseline-results.csv')
backbone = pd.read_csv('backbone-results.csv')

# Plot latency distribution
plt.figure(figsize=(12, 6))
plt.hist(baseline['end_to_end_latency_ms'], bins=50, alpha=0.5, label='Baseline')
plt.hist(backbone['end_to_end_latency_ms'], bins=50, alpha=0.5, label='AWS Backbone')
plt.xlabel('Latency (ms)')
plt.ylabel('Frequency')
plt.legend()
plt.title('Latency Distribution Comparison')
plt.show()
```

## Troubleshooting

### WebSocket Connection Issues

**Symptom**: "Failed to connect to Binance WebSocket"

**Solutions**:
- Check internet connectivity from EC2 instance
- Verify security group allows outbound HTTPS (port 443)
- Check Binance API status: https://www.binance.com/en/support/announcement

### VPC Peering Connection Issues

**Symptom**: Tokyo forwarder cannot connect to Frankfurt

**Solutions**:
- Verify VPC peering is active: `aws ec2 describe-vpc-peering-connections`
- Check route tables have correct routes to peer VPC CIDR
- Verify security groups allow TCP port 8080 between VPCs
- Test connectivity: `ping <frankfurt-private-ip>` from Tokyo EC2

### NTP Synchronization Issues

**Symptom**: Unrealistic latency values (negative or extremely high)

**Solutions**:
- Check NTP status: `chronyc tracking`
- Verify NTP is synchronized: `System time` offset should be < 10ms
- Restart chrony: `sudo systemctl restart chronyd`
- Wait 5-10 minutes for synchronization

### High Packet Loss

**Symptom**: `events_lost` > 1% of `sample_count`

**Solutions**:
- Check CPU usage on EC2 instances: `top`
- Verify network bandwidth is not saturated
- Increase EC2 instance size if needed
- Check for network issues in AWS Service Health Dashboard

### Permission Denied Errors

**Symptom**: Cannot execute binaries on EC2

**Solutions**:
```bash
chmod +x frankfurt-receiver tokyo-forwarder
```

## Cleanup

After completing experiments, tear down all AWS resources:

```bash
./scripts/teardown.sh
```

This script:
- Terminates EC2 instances
- Deletes VPC peering connection
- Deletes VPCs and associated resources (subnets, route tables, security groups, internet gateways)

**Important**: Verify all resources are deleted to avoid ongoing charges:

```bash
# Check for remaining instances
aws ec2 describe-instances --region ap-northeast-1 --query 'Reservations[].Instances[?State.Name!=`terminated`]'
aws ec2 describe-instances --region eu-central-1 --query 'Reservations[].Instances[?State.Name!=`terminated`]'

# Check for remaining VPCs
aws ec2 describe-vpcs --region ap-northeast-1
aws ec2 describe-vpcs --region eu-central-1
```

## Cost Estimation

Approximate AWS costs for running this experiment:

- **EC2 Instances**: 2 × t3.micro × $0.0104/hour = ~$0.02/hour
- **Data Transfer**: 
  - Intra-region VPC peering: Free
  - Inter-region VPC peering: $0.02/GB
  - Internet egress: $0.09/GB
- **Estimated total**: $0.50 - $2.00 for a 1-hour experiment

## Architecture Diagrams

### Baseline Setup
```
┌─────────────────┐
│  Binance Tokyo  │
│   WebSocket     │
└────────┬────────┘
         │
         │ Public Internet
         │ (~200-250ms)
         │
         ▼
┌─────────────────┐
│  Frankfurt EC2  │
│   (Receiver)    │
└─────────────────┘
```

### AWS Backbone Setup
```
┌─────────────────┐
│  Binance Tokyo  │
│   WebSocket     │
└────────┬────────┘
         │
         │ (~50ms)
         ▼
┌─────────────────┐      VPC Peering       ┌─────────────────┐
│   Tokyo EC2     │─────────────────────────│  Frankfurt EC2  │
│  (Forwarder)    │   AWS Private Network   │   (Receiver)    │
│  10.0.1.0/24    │      (~170-230ms)       │  10.1.1.0/24    │
└─────────────────┘                         └─────────────────┘
```

## Additional Resources

- [Binance WebSocket API Documentation](https://binance-docs.github.io/apidocs/spot/en/#websocket-market-streams)
- [AWS VPC Peering Guide](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html)
- [Rust Tokio Documentation](https://tokio.rs/)
- [NTP Time Synchronization](https://chrony.tuxfamily.org/documentation.html)

## License

This project is for experimental purposes only.
