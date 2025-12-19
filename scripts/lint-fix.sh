#!/bin/bash
# Lint Fixer Script
# Purpose: Automatically fix common linting issues like trailing whitespace and extra trailing newlines.

set -e

# Default directories if none provided
TARGET_DIRS=${*:-"helm argocd/applications k8s"}

echo "🧹 Starting whitespace and newline cleanup..."

for DIR in $TARGET_DIRS; do
    if [ -d "$DIR" ]; then
        echo "📂 Processing directory: $DIR"
        
        # 1. Remove trailing whitespace from all lines
        find "$DIR" -type f -name "*.yaml" -exec sed -i 's/[[:space:]]*$//' {} +
        
        # 2. Remove extra trailing newlines (ensures exactly one newline at end of file)
        find "$DIR" -type f -name "*.yaml" -exec sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' {} +
        
        echo "   ✅ $DIR cleaned."
    else
        echo "   ⚠️  Directory $DIR not found, skipping."
    fi
done

echo "✨ Cleanup complete. Review changes with 'git diff' and commit."

