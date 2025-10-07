#!/bin/bash
# Script to create SSH key pair for EC2 instances

set -e

KEY_NAME="binance-latency-key"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"

echo "=== Creating SSH Key Pair ==="
echo ""

# Check if key file already exists locally
if [ -f "$KEY_FILE" ]; then
    echo "⚠ Key file already exists at: $KEY_FILE"
    read -p "Do you want to delete it and create a new one? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing key file."
        echo "If you need to recreate it, delete the AWS key pairs first:"
        echo "  aws ec2 delete-key-pair --key-name $KEY_NAME --region ap-northeast-1"
        echo "  aws ec2 delete-key-pair --key-name $KEY_NAME --region eu-central-1"
        exit 0
    fi
    rm -f "$KEY_FILE"
fi

# Generate a local SSH key pair
echo "Generating local SSH key pair..."
ssh-keygen -t rsa -b 2048 -f "$KEY_FILE" -N "" -C "binance-latency-key"

if [ $? -ne 0 ]; then
    echo "✗ Failed to generate SSH key pair"
    exit 1
fi

echo "✓ Local SSH key pair generated"

# Import public key to Tokyo region
echo "Importing key pair to Tokyo (ap-northeast-1)..."
aws ec2 import-key-pair \
    --key-name "$KEY_NAME" \
    --region ap-northeast-1 \
    --public-key-material fileb://${KEY_FILE}.pub

if [ $? -eq 0 ]; then
    echo "✓ Key pair imported to Tokyo"
else
    echo "✗ Failed to import key pair to Tokyo"
    echo "Note: If the key already exists in AWS, delete it first:"
    echo "  aws ec2 delete-key-pair --key-name $KEY_NAME --region ap-northeast-1"
    exit 1
fi

# Import public key to Frankfurt region
echo "Importing key pair to Frankfurt (eu-central-1)..."
aws ec2 import-key-pair \
    --key-name "$KEY_NAME" \
    --region eu-central-1 \
    --public-key-material fileb://${KEY_FILE}.pub

if [ $? -eq 0 ]; then
    echo "✓ Key pair imported to Frankfurt"
else
    echo "✗ Failed to import key pair to Frankfurt"
    echo "Note: If the key already exists in AWS, delete it first:"
    echo "  aws ec2 delete-key-pair --key-name $KEY_NAME --region eu-central-1"
    rm -f "$KEY_FILE" "${KEY_FILE}.pub"
    exit 1
fi

# Remove public key file (we only need the private key)
rm -f "${KEY_FILE}.pub"

# Set proper permissions
chmod 400 "$KEY_FILE"
echo "✓ Set key file permissions to 400"

echo ""
echo "=== Key Pair Created Successfully ==="
echo ""
echo "Key file location: $KEY_FILE"
echo "Key name: $KEY_NAME"
echo ""
echo "You can now run the setup-ec2.sh script."
echo ""
echo "To delete the key pairs later, run:"
echo "  aws ec2 delete-key-pair --key-name $KEY_NAME --region ap-northeast-1"
echo "  aws ec2 delete-key-pair --key-name $KEY_NAME --region eu-central-1"
echo "  rm $KEY_FILE"
