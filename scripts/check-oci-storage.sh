#!/bin/bash
# OCI Storage Audit Script
# Purpose: Check total storage usage (Boot + Block) against Always Free 200GB limit.

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Starting OCI Storage Audit..."

# Get Compartment ID (Tenancy OCID)
COMPARTMENT_ID=$(oci iam compartment list --include-root --query "data[0].id" --raw-output)

if [ -z "$COMPARTMENT_ID" ]; then
    echo -e "${RED}❌ Error: Could not determine Compartment ID. Ensure OCI CLI is configured.${NC}"
    exit 1
fi

echo "📂 Compartment: $COMPARTMENT_ID"

# 1. Audit Block Volumes
echo "📦 Auditing Block Volumes (PVCs)..."
BLOCK_STORAGE=$(oci bv volume list --compartment-id "$COMPARTMENT_ID" --query "data[?\"lifecycle-state\" == 'AVAILABLE'].\"size-in-gbs\"" --output json | jq '. | add // 0')

# 2. Audit Boot Volumes
echo "👢 Auditing Boot Volumes (Nodes)..."
BOOT_STORAGE=$(oci bv boot-volume list --compartment-id "$COMPARTMENT_ID" --query "data[?\"lifecycle-state\" == 'AVAILABLE'].\"size-in-gbs\"" --output json | jq '. | add // 0')

TOTAL_STORAGE=$((BLOCK_STORAGE + BOOT_STORAGE))
LIMIT=200

# Write to GitHub Step Summary if running in GitHub Actions
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
    echo "### 📊 OCI Storage Audit Results" >> "$GITHUB_STEP_SUMMARY"
    echo "| Component | Usage |" >> "$GITHUB_STEP_SUMMARY"
    echo "|-----------|-------|" >> "$GITHUB_STEP_SUMMARY"
    echo "| Block Storage | ${BLOCK_STORAGE} GB |" >> "$GITHUB_STEP_SUMMARY"
    echo "| Boot Storage | ${BOOT_STORAGE} GB |" >> "$GITHUB_STEP_SUMMARY"
    echo "| **Total Usage** | **${TOTAL_STORAGE} GB** |" >> "$GITHUB_STEP_SUMMARY"
    echo "| Limit | ${LIMIT} GB |" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
    
    if [ "$TOTAL_STORAGE" -le "$LIMIT" ]; then
        echo "✅ **SAFE**: You are within the Always Free limits." >> "$GITHUB_STEP_SUMMARY"
    else
        echo "❌ **DANGER**: You are EXCEEDING the Always Free limits by $((TOTAL_STORAGE - LIMIT))GB!" >> "$GITHUB_STEP_SUMMARY"
    fi
fi

echo "------------------------------------------"
echo "📊 Results:"
echo "   Block Storage: ${BLOCK_STORAGE} GB"
echo "   Boot Storage:  ${BOOT_STORAGE} GB"
echo -e "   ${YELLOW}Total Usage:   ${TOTAL_STORAGE} GB${NC}"
echo "   Limit:         ${LIMIT} GB"
echo "------------------------------------------"

if [ "$TOTAL_STORAGE" -le "$LIMIT" ]; then
    echo -e "${GREEN}✅ SAFE: You are within the Always Free limits (${TOTAL_STORAGE}GB / ${LIMIT}GB).${NC}"
else
    OVER_BY=$((TOTAL_STORAGE - LIMIT))
    echo -e "${RED}⚠️  DANGER: You are EXCEEDING the Always Free limits by ${OVER_BY}GB!${NC}"
    echo "Please delete unattached block volumes or reduce PVC sizes."
fi

