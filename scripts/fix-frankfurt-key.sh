#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Fix Frankfurt Instance Key Script ===${NC}"
echo "This script will recreate the Frankfurt instance with the correct SSH key"
echo ""

# Load resource IDs
RESOURCE_FILE="vpc-resources.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo -e "${RED}Error: $RESOURCE_FILE not found${NC}"
    exit 1
fi

source $RESOURCE_FILE

# Configuration
FRANKFURT_REGION="eu-central-1"
INSTANCE_TYPE="t3.micro"
KEY_NAME="binance-latency-key"
SSH_KEY="$HOME/.ssh/$KEY_NAME.pem"

echo "Current Frankfurt Instance: $FRANKFURT_INSTANCE_ID"
echo ""

# Step 1: Terminate the Frankfurt instance
echo -e "${YELLOW}Step 1: Terminating Frankfurt instance...${NC}"
aws ec2 terminate-instances \
    --instance-ids $FRANKFURT_INSTANCE_ID \
    --region $FRANKFURT_REGION \
    --output text > /dev/null

echo -e "${GREEN}✓ Termination initiated${NC}"

echo -e "${YELLOW}Waiting for instance to terminate...${NC}"
aws ec2 wait instance-terminated \
    --instance-ids $FRANKFURT_INSTANCE_ID \
    --region $FRANKFURT_REGION

echo -e "${GREEN}✓ Instance terminated${NC}"
echo ""

# Step 2: Delete the Frankfurt key pair
echo -e "${YELLOW}Step 2: Deleting Frankfurt key pair...${NC}"
aws ec2 delete-key-pair \
    --key-name $KEY_NAME \
    --region $FRANKFURT_REGION 2>/dev/null || echo "Key pair already deleted or doesn't exist"

echo -e "${GREEN}✓ Old key pair deleted${NC}"
echo ""

# Step 3: Import the correct key to Frankfurt
echo -e "${YELLOW}Step 3: Importing correct key to Frankfurt...${NC}"

# Generate public key from private key
ssh-keygen -y -f $SSH_KEY > /tmp/${KEY_NAME}.pub

aws ec2 import-key-pair \
    --key-name $KEY_NAME \
    --region $FRANKFURT_REGION \
    --public-key-material fileb:///tmp/${KEY_NAME}.pub

rm /tmp/${KEY_NAME}.pub

echo -e "${GREEN}✓ Key imported to Frankfurt${NC}"
echo ""

# Step 4: Get the latest AMI
echo -e "${YELLOW}Step 4: Finding latest Amazon Linux 2023 AMI...${NC}"
FRANKFURT_AMI=$(aws ec2 describe-images \
    --region $FRANKFURT_REGION \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

echo -e "${GREEN}✓ AMI: $FRANKFURT_AMI${NC}"
echo ""

# Step 5: Launch new Frankfurt instance
echo -e "${YELLOW}Step 5: Launching new Frankfurt instance...${NC}"

NEW_FRANKFURT_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $FRANKFURT_AMI \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $FRANKFURT_SG_ID \
    --subnet-id $FRANKFURT_SUBNET_ID \
    --region $FRANKFURT_REGION \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=binance-latency-frankfurt}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✓ New instance launched: $NEW_FRANKFURT_INSTANCE_ID${NC}"
echo ""

# Step 6: Wait for instance to be running
echo -e "${YELLOW}Step 6: Waiting for instance to be running...${NC}"
aws ec2 wait instance-running \
    --instance-ids $NEW_FRANKFURT_INSTANCE_ID \
    --region $FRANKFURT_REGION

echo -e "${GREEN}✓ Instance is running${NC}"
echo ""

# Step 7: Get new instance details
echo -e "${YELLOW}Step 7: Retrieving instance details...${NC}"

NEW_FRANKFURT_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $NEW_FRANKFURT_INSTANCE_ID \
    --region $FRANKFURT_REGION \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

NEW_FRANKFURT_PRIVATE_IP=$(aws ec2 describe-instances \
    --instance-ids $NEW_FRANKFURT_INSTANCE_ID \
    --region $FRANKFURT_REGION \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

echo -e "${GREEN}✓ New Public IP: $NEW_FRANKFURT_PUBLIC_IP${NC}"
echo -e "${GREEN}✓ New Private IP: $NEW_FRANKFURT_PRIVATE_IP${NC}"
echo ""

# Step 8: Update vpc-resources.txt
echo -e "${YELLOW}Step 8: Updating vpc-resources.txt...${NC}"

# Create a temporary file with updated values
sed -i.bak \
    -e "s/FRANKFURT_INSTANCE_ID=.*/FRANKFURT_INSTANCE_ID=$NEW_FRANKFURT_INSTANCE_ID/" \
    -e "s/FRANKFURT_PUBLIC_IP=.*/FRANKFURT_PUBLIC_IP=$NEW_FRANKFURT_PUBLIC_IP/" \
    -e "s/FRANKFURT_PRIVATE_IP=.*/FRANKFURT_PRIVATE_IP=$NEW_FRANKFURT_PRIVATE_IP/" \
    $RESOURCE_FILE

rm ${RESOURCE_FILE}.bak

echo -e "${GREEN}✓ Resource file updated${NC}"
echo ""

# Step 9: Wait for SSH to be ready
echo -e "${YELLOW}Step 9: Waiting for SSH to be ready (this may take 1-2 minutes)...${NC}"
sleep 30

MAX_ATTEMPTS=12
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$NEW_FRANKFURT_PUBLIC_IP "echo 'SSH ready'" 2>/dev/null; then
        echo -e "${GREEN}✓ SSH is ready${NC}"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 10
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}⚠ SSH not ready yet, but instance is running${NC}"
    echo "You may need to wait a bit longer before connecting"
fi

echo ""
echo -e "${GREEN}=== Frankfurt Instance Fixed ===${NC}"
echo ""
echo "New Frankfurt Instance:"
echo "  Instance ID: $NEW_FRANKFURT_INSTANCE_ID"
echo "  Public IP: $NEW_FRANKFURT_PUBLIC_IP"
echo "  Private IP: $NEW_FRANKFURT_PRIVATE_IP"
echo "  SSH: ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$NEW_FRANKFURT_PUBLIC_IP"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Test SSH connection to Frankfurt"
echo "2. Run setup-ntp.sh to configure time synchronization"
echo "3. Run deploy.sh to deploy applications"
