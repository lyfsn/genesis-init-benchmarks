#!/bin/bash

# Default inputs
TEST_PATH="tests/"
WARMUP_FILE="warmup/warmup-1000bl-16wi-24tx.txt"
CLIENTS="nethermind,geth,reth"
RUNS=8
IMAGES="default"
OUTPUT_DIR="results"

# Parse command line arguments
while getopts "t:w:c:r:i:o:" opt; do
  case $opt in
    t) TEST_PATH="$OPTARG" ;;
    w) WARMUP_FILE="$OPTARG" ;;
    c) CLIENTS="$OPTARG" ;;
    r) RUNS="$OPTARG" ;;
    i) IMAGES="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    *) echo "Usage: $0 [-t test_path] [-w warmup_file] [-c clients] [-r runs] [-i images] [-o output_dir]" >&2
       exit 1 ;;
  esac
done

IFS=',' read -ra CLIENT_ARRAY <<< "$CLIENTS"
IFS=',' read -ra IMAGE_ARRAY <<< "$IMAGES"

# Set up environment
mkdir -p "$OUTPUT_DIR"

# Install dependencies
pip install -r requirements.txt
apt install jq

# Function to check if the block hash matches
check_block_hash() {
  local client=$1
  local expected_hash="0xfcf55e2e15afed0cd61a28b1b1966ac1a2326e7cd5cd062743fa5e51f47f8417"
  local block_hash=""
  local start_time=$(date +%s%3N)
  
  while [ "$block_hash" != "$expected_hash" ]; do
    response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0", false],"id":1}' -H "Content-Type: application/json" http://localhost:8545)
    block_hash=$(echo $response | jq -r '.result.hash')
    if [ "$block_hash" == "null" ]; then
      block_hash=""
    fi
    sleep 1
  done

  echo $(date +%s%3N)  # Return the timestamp in milliseconds
}

# Run benchmarks
for run in $(seq 1 $RUNS); do
  for i in "${!CLIENT_ARRAY[@]}"; do
    client="${CLIENT_ARRAY[$i]}"
    image="${IMAGE_ARRAY[$i]}"

    cd "scripts/$client"
    docker compose down
    sudo rm -rf execution-data
    cd ../..

    # Record the start time
    start_time=$(date +%s%3N)

    if [ -z "$image" ]; then
      echo "Image input is empty, using default image."
      python3 setup_node.py --client $client
    else
      echo "Using provided image: $image for $client"
      python3 setup_node.py --client $client --image $image
    fi

    # Record the time when the block hash matches
    block_hash_time=$(check_block_hash $client)

    # Calculate the interval
    interval=$((block_hash_time - start_time))
    
    # Write the interval to a file in OUTPUT_DIR
    output_file="${OUTPUT_DIR}/${client}_${i}.txt"
    echo "$client: $interval ms" > "$output_file"

    cd "scripts/$client"
    docker compose down
    sudo rm -rf execution-data
    cd ../..
  done
done

