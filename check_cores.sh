#!/bin/bash

# Check the number of CPU cores on the system

echo "=== CPU Core Information ==="
echo

# Method 1: nproc (fastest, most portable)
if command -v nproc >/dev/null 2>&1; then
    cores=$(nproc)
    echo "Total logical cores: $cores"
fi

echo

# Method 2: lscpu (detailed info)
if command -v lscpu >/dev/null 2>&1; then
    echo "--- Detailed CPU Info ---"
    lscpu | grep -E "^(CPU\(s\)|Thread|Core|Socket)"
fi

echo

# Method 3: /proc/cpuinfo (fallback)
if [ -f /proc/cpuinfo ]; then
    physical_cores=$(grep "^core id" /proc/cpuinfo | sort -u | wc -l)
    logical_cores=$(grep "^processor" /proc/cpuinfo | wc -l)
    echo "Physical cores: $physical_cores"
    echo "Logical cores (with hyperthreading): $logical_cores"
fi
