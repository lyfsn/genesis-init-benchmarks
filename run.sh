#!/bin/bash

# Default inputs
TEST_PATH="tests/"
WARMUP_FILE="warmup/warmup-1000bl-16wi-24tx.txt"
CLIENTS="nethermind,geth,reth"
RUNS=8
IMAGES="default"
OUTPUT_DIR="results"
SIZES=("1" "100" "1000")

# Parse command line arguments# Parse command line arguments
while getopts "t:w:c:r:i:o:s:" opt; do
  case $opt in
    t) TEST_PATH="$OPTARG" ;;
    w) WARMUP_FILE="$OPTARG" ;;
    c) CLIENTS="$OPTARG" ;;
    r) RUNS="$OPTARG" ;;
    i) IMAGES="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    s) IFS=',' read -ra SIZES <<< "$OPTARG" ;; 
    *) echo "Usage: $0 [-t test_path] [-w warmup_file] [-c clients] [-r runs] [-i images] [-o output_dir] [-s sizes]" >&2
       exit 1 ;;
  esac
done

IFS=',' read -ra CLIENT_ARRAY <<< "$CLIENTS"
IFS=',' read -ra IMAGE_ARRAY <<< "$IMAGES"

# Set up environment
mkdir -p "$OUTPUT_DIR"

# Install dependencies
pip install -r requirements.txt
apt install -y jq

python3 computer_specs.py --output_folder $OUTPUT_DIR

# Function to check if initialization is completed
check_initialization_completed() {
  local client=$1
  local log_entry=$2
  local container_name="gas-execution-client"
  local max_retries=1024
  local retry_count=0
  local wait_time=0.5  # 500 milliseconds

  until [ "$(docker ps -q -f name=$container_name)" ]; do
    echo "Waiting for container $container_name to start..."
    sleep $wait_time
    retry_count=$((retry_count+1))
    if [ $retry_count -ge $max_retries ]; then
      echo "Container $container_name did not start within the expected time."
      return 1
    fi
  done

  echo "Waiting for log entry: $log_entry in $container_name..."
  retry_count=0
  until docker logs $container_name 2>&1 | grep -q "$log_entry"; do
    sleep $wait_time
    retry_count=$((retry_count+1))
    if [ $retry_count -ge $max_retries ]; then
      echo "Log entry $log_entry not found in $container_name within the expected time."
      return 1
    fi
  done

  return 0
}

mkdir -p $TEST_PATH/tmp

# Outer loop
for size in "${SIZES[@]}"; do
  echo "=== Running benchmarks for size ${size}M ==="
  
  new_size=$(echo "($size / 1.2 + 0.5)/1" | bc)

  # Generate chainspec, genesis, and besu files
  python3 generate_chainspec.py $TEST_PATH/chainspec.json $TEST_PATH/tmp/chainspec.json $new_size
  python3 generate_genesis.py $TEST_PATH/genesis.json $TEST_PATH/tmp/genesis.json $new_size
  python3 generate_besu.py $TEST_PATH/besu.json $TEST_PATH/tmp/besu.json $new_size

  # Run benchmarks
  for run in $(seq 1 $RUNS); do
    for i in "${!CLIENT_ARRAY[@]}"; do
      echo "=== Run round $run - Client ${CLIENT_ARRAY[$i]} - Image ${IMAGE_ARRAY[$i]} ==="

      client="${CLIENT_ARRAY[$i]}"
      image="${IMAGE_ARRAY[$i]}"

      # Define the log entry based on the client
      case $client in
        nethermind) log_entry="initialization completed" ;;
        reth) log_entry="Starting reth" ;;
        erigon) log_entry="logging to file system" ;;
        geth) log_entry="Set global gas cap" ;;
        besu) log_entry="Writing node record to disk" ;;
      esac

      cd "scripts/$client"
      docker compose down -t 0
      sudo rm -rf execution-data
      cd ../..

      # Record the start time
      start_time=$(($(date +%s%N) / 1000000))

      if [ -z "$image" ]; then
        echo "Image input is empty, using default image."
        python3 setup_node.py --client $client
      else
        echo "Using provided image: $image for $client"
        python3 setup_node.py --client $client --image $image
      fi

      # Check initialization completion
      check_initialization_completed $client "$log_entry"
      if [ $? -ne 0 ]; then
        echo "Initialization check failed for client $client"
        exit 1
      fi

      # Record the time when the initialization is completed
      initialization_time=$(($(date +%s%N) / 1000000))
      interval=$((initialization_time - start_time))
      
      output_file="${OUTPUT_DIR}/${client}_${run}_first_${size}M.txt"
      echo "$interval" > "$output_file"
      echo "=== Interval $interval written to $output_file ==="

      cd "scripts/$client"
      docker compose down -t 0
      cd ../..

      # Record the second start time
      start_time=$(($(date +%s%N) / 1000000))

      if [ -z "$image" ]; then
        echo "Image input is empty, using default image."
        python3 setup_node.py --client $client
      else
        echo "Using provided image: $image for $client"
        python3 setup_node.py --client $client --image $image
      fi

      # Check initialization completion
      check_initialization_completed $client "$log_entry"
      if [ $? -ne 0 ]; then
        echo "Initialization check failed for client $client"
        exit 1
      fi

      # Record the time when the initialization is completed
      initialization_time=$(($(date +%s%N) / 1000000))
      interval=$((initialization_time - start_time))
      
      output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M.txt"
      echo "$interval" > "$output_file"
      echo "=== Interval $interval written to $output_file ==="

      cd "scripts/$client"
      docker compose down -t 0
      sudo rm -rf execution-data
      cd ../..
    done
  done
done

python3 report.py 
