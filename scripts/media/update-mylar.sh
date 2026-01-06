#!/bin/bash
#
# Update Mylar Deployment Script
# This script updates the Mylar deployment using Terraform
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Mylar Deployment Update Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Change to project root
cd "$PROJECT_ROOT"

# Check if terraform is available
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}ERROR: terraform is not installed or not in PATH${NC}"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

echo -e "${YELLOW}Checking current Mylar status...${NC}"
kubectl get pods -n media -l app=mylar

echo
echo -e "${YELLOW}Running terraform plan for Mylar deployment...${NC}"
terraform plan -target=kubernetes_deployment.mylar

echo
read -p "Do you want to apply these changes? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
    echo -e "${YELLOW}Update cancelled.${NC}"
    exit 0
fi

echo -e "${GREEN}Applying Mylar deployment updates...${NC}"
terraform apply -target=kubernetes_deployment.mylar -auto-approve

echo
echo -e "${YELLOW}Waiting for Mylar pod to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=mylar -n media --timeout=300s || true

echo
echo -e "${GREEN}Current Mylar pod status:${NC}"
kubectl get pods -n media -l app=mylar

echo
echo -e "${GREEN}Mylar service status:${NC}"
kubectl get svc -n media mylar

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Mylar update complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "Access Mylar at: ${YELLOW}http://mylar.home${NC}"
echo
echo -e "To view logs: ${YELLOW}kubectl logs -n media -l app=mylar --tail=50${NC}"
echo

