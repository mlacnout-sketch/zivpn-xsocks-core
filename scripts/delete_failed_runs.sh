#!/bin/bash

# ZIVPN CI Cleanup Script
# Deletes all failed GitHub Actions workflow runs.

echo "🔍 Fetching failed workflow runs..."

# Get list of failed run IDs
FAILED_RUNS=$(gh run list --status failure --limit 100 --json databaseId --jq '.[].databaseId')

if [ -z "$FAILED_RUNS" ]; then
    echo "✅ No failed runs found."
    exit 0
fi

COUNT=$(echo "$FAILED_RUNS" | wc -l)
echo "🗑️ Found $COUNT failed runs. Deleting..."

for RUN_ID in $FAILED_RUNS; do
    echo "  - Deleting run $RUN_ID..."
    gh run delete "$RUN_ID"
done

echo "✨ Cleanup complete."
