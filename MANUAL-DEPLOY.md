# Manual Deployment Guide

## Step 1: Copy Source Code to Instances

From your local machine, run these commands:

### Copy to Tokyo Instance
```bash
# Create directory
ssh -i ~/.ssh/binance-latency-key.pem ec2-user@54.65.234.137 "mkdir -p ~/tokyo-forwarder"

# Copy source files
scp -i ~/.ssh/binance-latency-key.pem -r tokyo-forwarder/src tokyo-forwarder/Cargo.toml ec2-user@54.65.234.137:~/tokyo-forwarder/
```

### Copy to Frankfurt Instance
```bash
# Create directory
ssh -i ~/.ssh/binance-latency-key.pem ec2-user@18.159.62.178 "mkdir -p ~/frankfurt-receiver"

# Copy source files
scp -i ~/.ssh/binance-latency-key.pem -r frankfurt-receiver/src frankfurt-receiver/Cargo.toml ec2-user@18.159.62.178:~/frankfurt-receiver/
```

## Step 2: Create Config Files

### Tokyo Config
Create `~/tokyo-config.json` on Tokyo instance:
```json
{
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "frankfurt_private_ip": "10.1.1.77",
  "frankfurt_port": 8080,
  "reconnect_max_delay_secs": 30
}
```

### Frankfurt Baseline Config
Create `~/frankfurt-baseline-config.json` on Frankfurt instance:
```json
{
  "mode": "baseline",
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "listen_port": 8080,
  "duration_secs": 300,
  "output_file": "results-baseline.json"
}
```

### Frankfurt AWS Backbone Config
Create `~/frankfurt-backbone-config.json` on Frankfurt instance:
```json
{
  "mode": "aws-backbone",
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "listen_port": 8080,
  "duration_secs": 300,
  "output_file": "results-backbone.json"
}
```

## Step 3: Build on Each Instance

### On Tokyo Instance (in your SSH session):
```bash
cd ~/tokyo-forwarder
cargo build --release

# Copy binary to home directory for easy access
cp target/release/tokyo-forwarder ~/
chmod +x ~/tokyo-forwarder
```

### On Frankfurt Instance (in your SSH session):
```bash
cd ~/frankfurt-receiver
cargo build --release

# Copy binary to home directory for easy access
cp target/release/frankfurt-receiver ~/
chmod +x ~/frankfurt-receiver
```

## Step 4: Run Experiments

### Experiment 1: Frankfurt Baseline (Direct Connection)

**On Frankfurt instance:**
```bash
cd ~
./frankfurt-receiver frankfurt-baseline-config.json
```

This will:
- Connect directly to Binance from Frankfurt
- Run for 5 minutes (300 seconds)
- Save results to `results-baseline.json` and `results-baseline.csv`

Wait for it to complete, then press Ctrl+C or wait for it to finish.

### Experiment 2: AWS Backbone (Tokyo → Frankfurt)

**Step 1 - Start Frankfurt receiver (in Frankfurt SSH session):**
```bash
cd ~
./frankfurt-receiver frankfurt-backbone-config.json
```

**Step 2 - Start Tokyo forwarder (in Tokyo SSH session):**
```bash
cd ~
./tokyo-forwarder tokyo-config.json
```

This will:
- Tokyo connects to Binance and forwards to Frankfurt via VPC peering
- Frankfurt receives and measures latency
- Run for 5 minutes (300 seconds)
- Save results to `results-backbone.json` and `results-backbone.csv`

## Step 5: Retrieve Results

From your local machine:

```bash
# Get baseline results
scp -i ~/.ssh/binance-latency-key.pem ec2-user@18.159.62.178:~/results-baseline.* .

# Get backbone results
scp -i ~/.ssh/binance-latency-key.pem ec2-user@18.159.62.178:~/results-backbone.* .
```

## Quick Commands Reference

### Check if binary is running:
```bash
ps aux | grep -E "(tokyo-forwarder|frankfurt-receiver)"
```

### Stop a running process:
```bash
pkill tokyo-forwarder
# or
pkill frankfurt-receiver
```

### View logs in real-time:
The applications output to stdout, so you'll see logs in your terminal.

### Test connectivity between instances:
```bash
# From Tokyo, ping Frankfurt private IP
ping -c 3 10.1.1.77

# From Frankfurt, check if port 8080 is listening
ss -tlnp | grep 8080
```

## Troubleshooting

### If cargo command not found:
```bash
source $HOME/.cargo/env
```

### If build fails with missing dependencies:
```bash
# Install build essentials
sudo yum install -y gcc openssl-devel
```

### If connection fails between Tokyo and Frankfurt:
```bash
# Check VPC peering routes
# From Tokyo:
ping 10.1.1.77

# Check security groups allow traffic on port 8080
```

### If WebSocket connection fails:
```bash
# Test Binance connectivity
curl -I https://stream.binance.com

# Check DNS resolution
nslookup stream.binance.com
```
