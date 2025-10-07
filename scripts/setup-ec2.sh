#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== EC2 Instance Setup Script ===${NC}"
echo "This script launches EC2 instances in Tokyo and Frankfurt"
echo ""

# Load resource IDs from VPC setup
RESOURCE_FILE="vpc-resources.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo -e "${RED}Error: $RESOURCE_FILE not found${NC}"
    echo "Please run setup-vpc.sh first"
    exit 1
fi

source $RESOURCE_FILE

# Regions
TOKYO_REGION="ap-northeast-1"
FRANKFURT_REGION="eu-central-1"

# EC2 Configuration
INSTANCE_TYPE="t3.micro"
KEY_NAME="${KEY_NAME:-binance-latency-key}"

# Check if key pair name is provided
if [ -z "$KEY_NAME" ]; then
    echo -e "${RED}Error: SSH key pair name not set${NC}"
    echo "Set KEY_NAME environment variable or update the script"
    exit 1
fi

# Get latest Amazon Linux 2023 AMI for Tokyo
echo -e "${YELLOW}Finding latest Amazon Linux 2023 AMI for Tokyo...${NC}"
TOKYO_AMI=$(aws ec2 describe-images \
    --region $TOKYO_REGION \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

echo -e "${GREEN}✓ Tokyo AMI: $TOKYO_AMI${NC}"

# Get latest Amazon Linux 2023 AMI for Frankfurt
echo -e "${YELLOW}Finding latest Amazon Linux 2023 AMI for Frankfurt...${NC}"
FRANKFURT_AMI=$(aws ec2 describe-images \
    --region $FRANKFURT_REGION \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

echo -e "${GREEN}✓ Frankfurt AMI: $FRANKFURT_AMI${NC}"
echo ""

# Create Tokyo Security Group
echo -e "${YELLOW}Creating Tokyo security group...${NC}"

TOKYO_SG_ID=$(aws ec2 create-security-group \
    --group-name binance-latency-tokyo-sg \
    --description "Security group for Binance latency Tokyo forwarder" \
    --vpc-id $TOKYO_VPC_ID \
    --region $TOKYO_REGION \
    --query 'GroupId' \
    --output text)

echo -e "${GREEN}✓ Tokyo Security Group created: $TOKYO_SG_ID${NC}"

# Configure Tokyo Security Group rules
# Allow SSH from anywhere
aws ec2 authorize-security-group-ingress \
    --group-id $TOKYO_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $TOKYO_REGION

# Allow outbound HTTPS for Binance WebSocket
aws ec2 authorize-security-group-egress \
    --group-id $TOKYO_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $TOKYO_REGION

# Allow outbound TCP 8080 to Frankfurt VPC
aws ec2 authorize-security-group-egress \
    --group-id $TOKYO_SG_ID \
    --protocol tcp \
    --port 8080 \
    --cidr 10.1.0.0/16 \
    --region $TOKYO_REGION

echo -e "${GREEN}✓ Tokyo Security Group configured${NC}"

# Create Frankfurt Security Group
echo -e "${YELLOW}Creating Frankfurt security group...${NC}"

FRANKFURT_SG_ID=$(aws ec2 create-security-group \
    --group-name binance-latency-frankfurt-sg \
    --description "Security group for Binance latency Frankfurt receiver" \
    --vpc-id $FRANKFURT_VPC_ID \
    --region $FRANKFURT_REGION \
    --query 'GroupId' \
    --output text)

echo -e "${GREEN}✓ Frankfurt Security Group created: $FRANKFURT_SG_ID${NC}"

# Configure Frankfurt Security Group rules
# Allow SSH from anywhere
aws ec2 authorize-security-group-ingress \
    --group-id $FRANKFURT_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $FRANKFURT_REGION

# Allow inbound TCP 8080 from Tokyo VPC
aws ec2 authorize-security-group-ingress \
    --group-id $FRANKFURT_SG_ID \
    --protocol tcp \
    --port 8080 \
    --cidr 10.0.0.0/16 \
    --region $FRANKFURT_REGION

# Allow outbound HTTPS for Binance WebSocket (baseline mode)
aws ec2 authorize-security-group-egress \
    --group-id $FRANKFURT_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $FRANKFURT_REGION

echo -e "${GREEN}✓ Frankfurt Security Group configured${NC}"
echo ""

# Launch Tokyo EC2 instance
echo -e "${YELLOW}Launching Tokyo EC2 instance...${NC}"

TOKYO_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $TOKYO_AMI \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $TOKYO_SG_ID \
    --subnet-id $TOKYO_SUBNET_ID \
    --region $TOKYO_REGION \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=binance-latency-tokyo}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✓ Tokyo EC2 instance launched: $TOKYO_INSTANCE_ID${NC}"

# Launch Frankfurt EC2 instance
echo -e "${YELLOW}Launching Frankfurt EC2 instance...${NC}"

FRANKFURT_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $FRANKFURT_AMI \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $FRANKFURT_SG_ID \
    --subnet-id $FRANKFURT_SUBNET_ID \
    --region $FRANKFURT_REGION \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=binance-latency-frankfurt}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✓ Frankfurt EC2 instance launched: $FRANKFURT_INSTANCE_ID${NC}"
echo ""

# Wait for instances to be running
echo -e "${YELLOW}Waiting for Tokyo instance to be running...${NC}"
aws ec2 wait instance-running \
    --instance-ids $TOKYO_INSTANCE_ID \
    --region $TOKYO_REGION

echo -e "${GREEN}✓ Tokyo instance is running${NC}"

echo -e "${YELLOW}Waiting for Frankfurt instance to be running...${NC}"
aws ec2 wait instance-running \
    --instance-ids $FRANKFURT_INSTANCE_ID \
    --region $FRANKFURT_REGION

echo -e "${GREEN}✓ Frankfurt instance is running${NC}"
echo ""

# Get instance details
echo -e "${YELLOW}Retrieving instance details...${NC}"

TOKYO_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $TOKYO_INSTANCE_ID \
    --region $TOKYO_REGION \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

TOKYO_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids $TOKYO_INSTANCE_ID \
    --region $TOKYO_REGION \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

FRANKFURT_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $FRANKFURT_INSTANCE_ID \
    --region $FRANKFURT_REGION \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

FRANKFURT_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids $FRANKFURT_INSTANCE_ID \
    --region $FRANKFURT_REGION \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

# Append instance IDs to resource file
cat >> $RESOURCE_FILE << EOF

TOKYO_INSTANCE_ID=$TOKYO_INSTANCE_ID
TOKYO_SG_ID=$TOKYO_SG_ID
TOKYO_PUBLIC_IP=$TOKYO_PUBLIC_IP
TOKYO_PRIVATE_IP=$TOKYO_PRIVATE_IP

FRANKFURT_INSTANCE_ID=$FRANKFURT_INSTANCE_ID
FRANKFURT_SG_ID=$FRANKFURT_SG_ID
FRANKFURT_PUBLIC_IP=$FRANKFURT_PUBLIC_IP
FRANKFURT_PRIVATE_IP=$FRANKFURT_PRIVATE_IP
EOF

echo -e "${GREEN}=== EC2 Setup Complete ===${NC}"
echo ""
echo "Tokyo Instance:"
echo "  Instance ID: $TOKYO_INSTANCE_ID"
echo "  Public IP: $TOKYO_PUBLIC_IP"
echo "  Private IP: $TOKYO_PRIVATE_IP"
echo "  SSH: ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$TOKYO_PUBLIC_IP"
echo ""
echo "Frankfurt Instance:"
echo "  Instance ID: $FRANKFURT_INSTANCE_ID"
echo "  Public IP: $FRANKFURT_PUBLIC_IP"
echo "  Private IP: $FRANKFURT_PRIVATE_IP"
echo "  SSH: ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$FRANKFURT_PUBLIC_IP"
echo ""
echo -e "${YELLOW}Note: Wait 2-3 minutes for instances to fully initialize before SSH${NC}"
echo -e "${YELLOW}Next step: Run setup-ntp.sh to configure time synchronization${NC}"
