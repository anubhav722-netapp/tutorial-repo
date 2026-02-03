#!/bin/bash
# NetApp BlueXP Connector GCP Setup Script
# 
# This script is designed to be run from Cloud Shell with pre-loaded parameters.
# It creates:
#   1. Custom IAM role with required permissions
#   2. Service Account for the connector
#   3. Role binding between SA and custom role
#   4. Calls webhook to notify completion
#
# Usage:
#   curl -sL https://your-domain/setup.sh | bash -s -- \
#     --project=my-project \
#     --email=user@example.com \
#     --callback=https://backend/webhook

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_ID=""
CUSTOMER_EMAIL=""
CALLBACK_URL=""
SCRIPT_BASE_URL=""
SA_NAME="netapp-bluexp-connector-v2"
ROLE_NAME="NetAppBlueXPConnectorRolev2"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project=*)
      PROJECT_ID="${1#*=}"
      shift
      ;;
    --email=*)
      CUSTOMER_EMAIL="${1#*=}"
      shift
      ;;
    --callback=*)
      CALLBACK_URL="${1#*=}"
      shift
      ;;
    --script-base=*)
      SCRIPT_BASE_URL="${1#*=}"
      shift
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}Error: --project is required${NC}"
  exit 1
fi

if [[ -z "$CUSTOMER_EMAIL" ]]; then
  echo -e "${RED}Error: --email is required${NC}"
  exit 1
fi

if [[ -z "$CALLBACK_URL" ]]; then
  echo -e "${RED}Error: --callback is required${NC}"
  exit 1
fi

if [[ -z "$SCRIPT_BASE_URL" ]]; then
  echo -e "${RED}Error: --script-base is required${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         NetApp BlueXP Connector - GCP Setup                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Project ID:  ${GREEN}$PROJECT_ID${NC}"
echo -e "  Email:       ${GREEN}$CUSTOMER_EMAIL${NC}"
echo ""

# Function to send error to webhook
send_error() {
  local error_message="$1"
  curl -sX POST "$CALLBACK_URL" \
    -H "Content-Type: application/json" \
    -H "ngrok-skip-browser-warning: true" \
    -d "{
      \"customerEmail\": \"${CUSTOMER_EMAIL}\",
      \"projectId\": \"${PROJECT_ID}\",
      \"status\": \"error\",
      \"error\": \"${error_message}\"
    }" > /dev/null 2>&1 || true
}

# Trap errors
trap 'send_error "Script failed unexpectedly"' ERR

# Step 1: Set the project
echo -e "${YELLOW}[1/5]${NC} Setting GCP project..."
if ! gcloud config set project "$PROJECT_ID" 2>/dev/null; then
  echo -e "${RED}Error: Failed to set project. Make sure you have access to project: $PROJECT_ID${NC}"
  send_error "Failed to set project: $PROJECT_ID"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Project set to $PROJECT_ID"

# Step 2: Download role definition
echo -e "${YELLOW}[2/5]${NC} Downloading role permissions..."
ROLE_FILE="/tmp/connector-role-$$.yaml"
if ! curl -sL "${SCRIPT_BASE_URL}/connector-role.yaml" -o "$ROLE_FILE"; then
  echo -e "${RED}Error: Failed to download role definition${NC}"
  send_error "Failed to download role definition"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Role definition downloaded"

# Step 3: Create or update custom IAM role
echo -e "${YELLOW}[3/5]${NC} Creating custom IAM role..."
if gcloud iam roles describe "$ROLE_NAME" --project="$PROJECT_ID" > /dev/null 2>&1; then
  # Role exists, update it
  echo -e "  ${YELLOW}→${NC} Role exists, updating..."
  if ! gcloud iam roles update "$ROLE_NAME" \
    --project="$PROJECT_ID" \
    --file="$ROLE_FILE" \
    --quiet 2>/dev/null; then
    echo -e "${RED}Error: Failed to update IAM role${NC}"
    send_error "Failed to update IAM role"
    exit 1
  fi
  echo -e "  ${GREEN}✓${NC} IAM role updated"
else
  # Create new role
  if ! gcloud iam roles create "$ROLE_NAME" \
    --project="$PROJECT_ID" \
    --file="$ROLE_FILE" \
    --quiet 2>/dev/null; then
    echo -e "${RED}Error: Failed to create IAM role${NC}"
    send_error "Failed to create IAM role"
    exit 1
  fi
  echo -e "  ${GREEN}✓${NC} IAM role created"
fi

# Step 4: Create service account
echo -e "${YELLOW}[4/5]${NC} Creating service account..."
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" > /dev/null 2>&1; then
  echo -e "  ${YELLOW}→${NC} Service account already exists"
else
  if ! gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="NetApp BlueXP Connector" \
    --description="Service account for NetApp BlueXP Connector operations" \
    --quiet 2>/dev/null; then
    echo -e "${RED}Error: Failed to create service account${NC}"
    send_error "Failed to create service account"
    exit 1
  fi
  echo -e "  ${GREEN}✓${NC} Service account created"
fi

# Step 5: Bind role to service account
echo -e "${YELLOW}[5/5]${NC} Binding role to service account..."
ROLE_PATH="projects/${PROJECT_ID}/roles/${ROLE_NAME}"

if ! gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="$ROLE_PATH" \
  --quiet > /dev/null 2>&1; then
  echo -e "${RED}Error: Failed to bind role to service account${NC}"
  send_error "Failed to bind role to service account"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Role bound to service account"

# Get service account unique ID
SA_UNIQUE_ID=$(gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" --format="value(uniqueId)" 2>/dev/null || echo "unknown")

# Step 6: Call webhook to register
echo ""
echo -e "${YELLOW}Registering with NetApp...${NC}"
WEBHOOK_RESPONSE=$(curl -sX POST "$CALLBACK_URL" \
  -H "Content-Type: application/json" \
  -H "ngrok-skip-browser-warning: true" \
  -d "{
    \"customerEmail\": \"${CUSTOMER_EMAIL}\",
    \"serviceAccountEmail\": \"${SA_EMAIL}\",
    \"serviceAccountUniqueId\": \"${SA_UNIQUE_ID}\",
    \"projectId\": \"${PROJECT_ID}\",
    \"roleName\": \"${ROLE_NAME}\",
    \"status\": \"success\"
  }" 2>/dev/null)

if [[ $? -eq 0 ]]; then
  echo -e "  ${GREEN}✓${NC} Registration complete"
else
  echo -e "  ${YELLOW}⚠${NC} Could not reach callback URL (setup still successful)"
fi

# Cleanup
rm -f "$ROLE_FILE"

# Success message
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Setup Complete! ✓                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Service Account Details:${NC}"
echo -e "  Email:      ${GREEN}${SA_EMAIL}${NC}"
echo -e "  Unique ID:  ${GREEN}${SA_UNIQUE_ID}${NC}"
echo -e "  Role:       ${GREEN}${ROLE_PATH}${NC}"
echo ""
echo -e "${YELLOW}You can now close this window and return to the NetApp Console.${NC}"
echo ""
