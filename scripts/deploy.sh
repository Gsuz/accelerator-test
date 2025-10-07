#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Deployment Script ===${NC}"
echo "This script builds and deploys the Rust applications to EC2 instances"
echo ""

# Load resource IDs
RESOURCE_FILE="vpc-resources.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo -e "${RED}Error: $RESOURCE_FILE not found${NC}"
    echo "Please run setup-vpc.sh and setup-ec2.sh first"
    exit 1
fi

source $RESOURCE_FILE

# Check if instance IPs are available
if [ -z "$TOKYO_PUBLIC_IP" ] || [ -z "$FRANKFURT_PUBLIC_IP" ]; then
    echo -e "${RED}Error: Instance IPs not found in $RESOURCE_FILE${NC}"
    echo "Please run setup-ec2.sh first"
    exit 1
fi

# SSH key configuration
KEY_NAME="${KEY_NAME:-binance-latency-key}"
SSH_KEY="$HOME/.ssh/$KEY_NAME.pem"

if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}Error: SSH key not found at $SSH_KEY${NC}"
    echo "Please ensure your SSH key is available"
    exit 1
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SCP_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "Tokyo Instance: $TOKYO_PUBLIC_IP"
echo "Frankfurt Instance: $FRANKFURT_PUBLIC_IP"
echo ""

# Note: We'll build on the EC2 instances instead of locally
# to ensure Linux compatibility
echo -e "${YELLOW}Note: Binaries will be built on EC2 instances for Linux compatibility${NC}"
echo ""

# Create config files
echo -e "${YELLOW}Creating configuration files...${NC}"

mkdir -p config

# Tokyo config
cat > config/tokyo-config.json << EOF
{
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "frankfurt_private_ip": "$FRANKFURT_PRIVATE_IP",
  "frankfurt_port": 8080,
  "reconnect_max_delay_secs": 30
}
EOF

# Frankfurt baseline config
cat > config/frankfurt-baseline-config.json << EOF
{
  "mode": "baseline",
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "listen_port": 8080,
  "duration_secs": 300,
  "output_file": "results-baseline.json"
}
EOF

# Frankfurt AWS backbone config
cat > config/frankfurt-backbone-config.json << EOF
{
  "mode": "aws-backbone",
  "binance_ws_url": "wss://stream.binance.com:9443/ws/btcusdt@bookTicker",
  "listen_port": 8080,
  "duration_secs": 300,
  "output_file": "results-backbone.json"
}
EOF

echo -e "${GREEN}✓ Configuration files created${NC}"
echo ""

# Deploy to Tokyo instance
echo -e "${YELLOW}Deploying to Tokyo instance...${NC}"

# Copy source code
echo "Copying source code..."
ssh $SSH_OPTS ec2-user@$TOKYO_PUBLIC_IP "mkdir -p ~/tokyo-forwarder"
scp $SCP_OPTS -r tokyo-forwarder/src tokyo-forwarder/Cargo.toml ec2-user@$TOKYO_PUBLIC_IP:~/tokyo-forwarder/ || {
    echo -e "${RED}Failed to copy tokyo-forwarder source${NC}"
    exit 1
}

# Copy config
scp $SCP_OPTS config/tokyo-config.json ec2-user@$TOKYO_PUBLIC_IP:~/ || {
    echo -e "${RED}Failed to copy tokyo config${NC}"
    exit 1
}

# Install Rust and build on instance
echo "Installing Rust and building on Tokyo instance..."
ssh $SSH_OPTS ec2-user@$TOKYO_PUBLIC_IP << 'ENDSSH'
    # Install Rust if not already installed
    if ! command -v cargo &> /dev/null; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    # Build the binary
    cd ~/tokyo-forwarder
    ~/.cargo/bin/cargo build --release
    
    # Copy binary to home directory
    cp target/release/tokyo-forwarder ~/
    chmod +x ~/tokyo-forwarder
ENDSSH

echo -e "${GREEN}✓ Tokyo deployment complete${NC}"
echo ""

# Deploy to Frankfurt instance
echo -e "${YELLOW}Deploying to Frankfurt instance...${NC}"

# Copy source code
echo "Copying source code..."
ssh $SSH_OPTS ec2-user@$FRANKFURT_PUBLIC_IP "mkdir -p ~/frankfurt-receiver"
scp $SCP_OPTS -r frankfurt-receiver/src frankfurt-receiver/Cargo.toml ec2-user@$FRANKFURT_PUBLIC_IP:~/frankfurt-receiver/ || {
    echo -e "${RED}Failed to copy frankfurt-receiver source${NC}"
    exit 1
}

# Copy configs
scp $SCP_OPTS config/frankfurt-baseline-config.json ec2-user@$FRANKFURT_PUBLIC_IP:~/ || {
    echo -e "${RED}Failed to copy frankfurt baseline config${NC}"
    exit 1
}

scp $SCP_OPTS config/frankfurt-backbone-config.json ec2-user@$FRANKFURT_PUBLIC_IP:~/ || {
    echo -e "${RED}Failed to copy frankfurt backbone config${NC}"
    exit 1
}

# Install Rust and build on instance
echo "Installing Rust and building on Frankfurt instance..."
ssh $SSH_OPTS ec2-user@$FRANKFURT_PUBLIC_IP << 'ENDSSH'
    # Install Rust if not already installed
    if ! command -v cargo &> /dev/null; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    # Build the binary
    cd ~/frankfurt-receiver
    ~/.cargo/bin/cargo build --release
    
    # Copy binary to home directory
    cp target/release/frankfurt-receiver ~/
    chmod +x ~/frankfurt-receiver
ENDSSH

echo -e "${GREEN}✓ Frankfurt deployment complete${NC}"
echo ""

echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Binaries and configs deployed to both instances"
echo ""
echo "To run baseline experiment:"
echo "  1. SSH to Frankfurt: ssh $SSH_OPTS ec2-user@$FRANKFURT_PUBLIC_IP"
echo "  2. Run: ./frankfurt-receiver frankfurt-baseline-config.json"
echo ""
echo "To run AWS backbone experiment:"
echo "  1. SSH to Frankfurt: ssh $SSH_OPTS ec2-user@$FRANKFURT_PUBLIC_IP"
echo "  2. Run: ./frankfurt-receiver frankfurt-backbone-config.json"
echo "  3. In another terminal, SSH to Tokyo: ssh $SSH_OPTS ec2-user@$TOKYO_PUBLIC_IP"
echo "  4. Run: ./tokyo-forwarder tokyo-config.json"
echo ""
echo "To retrieve results:"
echo "  scp $SCP_OPTS ec2-user@$FRANKFURT_PUBLIC_IP:~/results-*.json ."
echo "  scp $SCP_OPTS ec2-user@$FRANKFURT_PUBLIC_IP:~/results-*.csv ."
