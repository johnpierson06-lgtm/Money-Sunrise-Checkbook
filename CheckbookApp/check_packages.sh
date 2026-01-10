#!/bin/bash

# Package Dependency Diagnostic Script
# Run this in Terminal from your project directory

echo "=== Checking CheckbookApp Package Dependencies ==="
echo ""

PROJECT_DIR="/Users/johnpierson/Documents/CheckbookApp"

cd "$PROJECT_DIR" || exit

echo "1. Checking for Package.resolved..."
if [ -f "Package.resolved" ]; then
    echo "   ✓ Package.resolved exists"
    echo "   Contents:"
    cat Package.resolved
else
    echo "   ✗ Package.resolved NOT FOUND"
fi

echo ""
echo "2. Checking for .swiftpm directory..."
if [ -d ".swiftpm" ]; then
    echo "   ✓ .swiftpm directory exists"
    ls -la .swiftpm/
else
    echo "   ✗ .swiftpm directory NOT FOUND"
fi

echo ""
echo "3. Checking Xcode DerivedData..."
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED_DATA" ]; then
    CHECKBOOK_DIRS=$(find "$DERIVED_DATA" -name "*CheckbookApp*" -type d -maxdepth 1 2>/dev/null)
    if [ -n "$CHECKBOOK_DIRS" ]; then
        echo "   ✓ Found CheckbookApp in DerivedData:"
        echo "$CHECKBOOK_DIRS"
    else
        echo "   ✗ No CheckbookApp in DerivedData"
    fi
else
    echo "   ✗ DerivedData directory not found"
fi

echo ""
echo "4. Checking SwiftPM caches..."
SPM_CACHE="$HOME/Library/Caches/org.swift.swiftpm"
if [ -d "$SPM_CACHE" ]; then
    echo "   ✓ SwiftPM cache exists"
    du -sh "$SPM_CACHE" 2>/dev/null
else
    echo "   ✗ SwiftPM cache not found"
fi

echo ""
echo "=== Recommended Actions ==="
echo ""
echo "If packages are broken, run these commands:"
echo ""
echo "# Clean package state"
echo "cd $PROJECT_DIR"
echo "rm -rf .swiftpm"
echo "rm -f Package.resolved"
echo ""
echo "# Clean Xcode caches"
echo "rm -rf ~/Library/Developer/Xcode/DerivedData"
echo "rm -rf ~/Library/Caches/org.swift.swiftpm"
echo ""
echo "Then in Xcode:"
echo "1. File → Packages → Reset Package Caches"
echo "2. File → Packages → Resolve Package Versions"
echo "3. If still broken: File → Add Package Dependencies (re-add MSAL and BigInt)"
