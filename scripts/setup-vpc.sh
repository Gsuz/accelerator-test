#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== VPC Setup Script ===${NC}"
echo "This script creates VPCs in Tokyo and Frankfurt regions"
echo ""

# Tokyo VPC Configuration
TOKYO_REGION="ap-northeast-1"
TOKYO_VPC_CIDR="10.0.0.0/16"
TOKYO_SUBNET_CIDR="10.0.1.0/24"
TOKYO_VPC_NAME="binance-latency-tokyo-vpc"
TOKYO_SUBNET_NAME="binance-latency-tokyo-subnet"
TOKYO_IGW_NAME="binance-latency-tokyo-igw"
TOKYO_RT_NAME="binance-latency-tokyo-rt"

# Frankfurt VPC Configuration
FRANKFURT_REGION="eu-central-1"
FRANKFURT_VPC_CIDR="10.1.0.0/16"
FRANKFURT_SUBNET_CIDR="10.1.1.0/24"
FRANKFURT_VPC_NAME="binance-latency-frankfurt-vpc"
FRANKFURT_SUBNET_NAME="binance-latency-frankfurt-subnet"
FRANKFURT_IGW_NAME="binance-latency-frankfurt-igw"
FRANKFURT_RT_NAME="binance-latency-frankfurt-rt"

# Output file for resource IDs
OUTPUT_FILE="vpc-resources.txt"

echo -e "${YELLOW}Creating Tokyo VPC...${NC}"

# Create Tokyo VPC
TOKYO_VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $TOKYO_VPC_CIDR \
    --region $TOKYO_REGION \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$TOKYO_VPC_NAME}]" \
    --query 'Vpc.VpcId' \
    --output text)

echo -e "${GREEN}✓ Tokyo VPC created: $TOKYO_VPC_ID${NC}"

# Enable DNS hostnames for Tokyo VPC
aws ec2 modify-vpc-attribute \
    --vpc-id $TOKYO_VPC_ID \
    --enable-dns-hostnames \
    --region $TOKYO_REGION

# Create Tokyo Subnet
TOKYO_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $TOKYO_VPC_ID \
    --cidr-block $TOKYO_SUBNET_CIDR \
    --region $TOKYO_REGION \
    --availability-zone ${TOKYO_REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$TOKYO_SUBNET_NAME}]" \
    --query 'Subnet.SubnetId' \
    --output text)

echo -e "${GREEN}✓ Tokyo Subnet created: $TOKYO_SUBNET_ID${NC}"

# Enable auto-assign public IP for Tokyo subnet
aws ec2 modify-subnet-attribute \
    --subnet-id $TOKYO_SUBNET_ID \
    --map-public-ip-on-launch \
    --region $TOKYO_REGION

# Create Tokyo Internet Gateway
TOKYO_IGW_ID=$(aws ec2 create-internet-gateway \
    --region $TOKYO_REGION \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$TOKYO_IGW_NAME}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

echo -e "${GREEN}✓ Tokyo Internet Gateway created: $TOKYO_IGW_ID${NC}"

# Attach Internet Gateway to Tokyo VPC
aws ec2 attach-internet-gateway \
    --vpc-id $TOKYO_VPC_ID \
    --internet-gateway-id $TOKYO_IGW_ID \
    --region $TOKYO_REGION

echo -e "${GREEN}✓ Tokyo Internet Gateway attached${NC}"

# Create Tokyo Route Table
TOKYO_RT_ID=$(aws ec2 create-route-table \
    --vpc-id $TOKYO_VPC_ID \
    --region $TOKYO_REGION \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$TOKYO_RT_NAME}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

echo -e "${GREEN}✓ Tokyo Route Table created: $TOKYO_RT_ID${NC}"

# Add route to Internet Gateway in Tokyo Route Table
aws ec2 create-route \
    --route-table-id $TOKYO_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $TOKYO_IGW_ID \
    --region $TOKYO_REGION

# Associate Tokyo Route Table with Subnet
aws ec2 associate-route-table \
    --subnet-id $TOKYO_SUBNET_ID \
    --route-table-id $TOKYO_RT_ID \
    --region $TOKYO_REGION

echo -e "${GREEN}✓ Tokyo Route Table configured${NC}"
echo ""

echo -e "${YELLOW}Creating Frankfurt VPC...${NC}"

# Create Frankfurt VPC
FRANKFURT_VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $FRANKFURT_VPC_CIDR \
    --region $FRANKFURT_REGION \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$FRANKFURT_VPC_NAME}]" \
    --query 'Vpc.VpcId' \
    --output text)

echo -e "${GREEN}✓ Frankfurt VPC created: $FRANKFURT_VPC_ID${NC}"

# Enable DNS hostnames for Frankfurt VPC
aws ec2 modify-vpc-attribute \
    --vpc-id $FRANKFURT_VPC_ID \
    --enable-dns-hostnames \
    --region $FRANKFURT_REGION

# Create Frankfurt Subnet
FRANKFURT_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $FRANKFURT_VPC_ID \
    --cidr-block $FRANKFURT_SUBNET_CIDR \
    --region $FRANKFURT_REGION \
    --availability-zone ${FRANKFURT_REGION}a \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$FRANKFURT_SUBNET_NAME}]" \
    --query 'Subnet.SubnetId' \
    --output text)

echo -e "${GREEN}✓ Frankfurt Subnet created: $FRANKFURT_SUBNET_ID${NC}"

# Enable auto-assign public IP for Frankfurt subnet
aws ec2 modify-subnet-attribute \
    --subnet-id $FRANKFURT_SUBNET_ID \
    --map-public-ip-on-launch \
    --region $FRANKFURT_REGION

# Create Frankfurt Internet Gateway
FRANKFURT_IGW_ID=$(aws ec2 create-internet-gateway \
    --region $FRANKFURT_REGION \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$FRANKFURT_IGW_NAME}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

echo -e "${GREEN}✓ Frankfurt Internet Gateway created: $FRANKFURT_IGW_ID${NC}"

# Attach Internet Gateway to Frankfurt VPC
aws ec2 attach-internet-gateway \
    --vpc-id $FRANKFURT_VPC_ID \
    --internet-gateway-id $FRANKFURT_IGW_ID \
    --region $FRANKFURT_REGION

echo -e "${GREEN}✓ Frankfurt Internet Gateway attached${NC}"

# Create Frankfurt Route Table
FRANKFURT_RT_ID=$(aws ec2 create-route-table \
    --vpc-id $FRANKFURT_VPC_ID \
    --region $FRANKFURT_REGION \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$FRANKFURT_RT_NAME}]" \
    --query 'RouteTable.RouteTableId' \
    --output text)

echo -e "${GREEN}✓ Frankfurt Route Table created: $FRANKFURT_RT_ID${NC}"

# Add route to Internet Gateway in Frankfurt Route Table
aws ec2 create-route \
    --route-table-id $FRANKFURT_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $FRANKFURT_IGW_ID \
    --region $FRANKFURT_REGION

# Associate Frankfurt Route Table with Subnet
aws ec2 associate-route-table \
    --subnet-id $FRANKFURT_SUBNET_ID \
    --route-table-id $FRANKFURT_RT_ID \
    --region $FRANKFURT_REGION

echo -e "${GREEN}✓ Frankfurt Route Table configured${NC}"
echo ""

# Save resource IDs to file
cat > $OUTPUT_FILE << EOF
# VPC Resource IDs
# Generated on $(date)

TOKYO_VPC_ID=$TOKYO_VPC_ID
TOKYO_SUBNET_ID=$TOKYO_SUBNET_ID
TOKYO_IGW_ID=$TOKYO_IGW_ID
TOKYO_RT_ID=$TOKYO_RT_ID

FRANKFURT_VPC_ID=$FRANKFURT_VPC_ID
FRANKFURT_SUBNET_ID=$FRANKFURT_SUBNET_ID
FRANKFURT_IGW_ID=$FRANKFURT_IGW_ID
FRANKFURT_RT_ID=$FRANKFURT_RT_ID
EOF

echo -e "${GREEN}=== VPC Setup Complete ===${NC}"
echo ""
echo "Resource IDs saved to: $OUTPUT_FILE"
echo ""
echo "Tokyo VPC:"
echo "  VPC ID: $TOKYO_VPC_ID"
echo "  Subnet ID: $TOKYO_SUBNET_ID"
echo "  CIDR: $TOKYO_VPC_CIDR"
echo ""
echo "Frankfurt VPC:"
echo "  VPC ID: $FRANKFURT_VPC_ID"
echo "  Subnet ID: $FRANKFURT_SUBNET_ID"
echo "  CIDR: $FRANKFURT_VPC_CIDR"
echo ""
echo -e "${YELLOW}Next step: Run setup-vpc-peering.sh to establish VPC peering${NC}"
