#!/bin/bash

# Default inputs
TEST_PATH="tests/"
CLIENTS="nethermind,geth,reth"
RUNS=8
IMAGES="default"
OUTPUT_DIR="results"
SIZES=("1" "100" "1000")

# Parse command line arguments
while getopts "t:c:r:i:o:s:" opt; do
  case $opt in
    t) TEST_PATH="$OPTARG" ;;
    c) CLIENTS="$OPTARG" ;;
    r) RUNS="$OPTARG" ;;
    i) IMAGES="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    s) IFS=',' read -ra SIZES <<< "$OPTARG" ;; 
    *) echo "Usage: $0 [-t test_path] [-c clients] [-r runs] [-i images] [-o output_dir] [-s sizes]" >&2
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

  # Start a background process to tail the logs
  docker logs -f $container_name &
  log_pid=$!

  # Wait for the container to start
  until [ "$(docker ps -q -f name=$container_name)" ]; do
    echo "Waiting for container $container_name to start..."
    sleep $wait_time
    retry_count=$((retry_count+1))
    if [ $retry_count -ge $max_retries ]; then
      echo "Container $container_name did not start within the expected time."
      kill $log_pid  # Terminate the background log tail process
      return 1
    fi
  done

  echo "Container $container_name has started."

  # Function to check if the container is still running
  check_container_running() {
    if [ -z "$(docker ps -q -f name=$container_name)" ]; then
      echo "Container $container_name has stopped unexpectedly."
      kill $log_pid  # Terminate the background log tail process
      return 1
    fi
    return 0
  }

  # Reset retry count for log entry check
  retry_count=0
  echo "Waiting for log entry: $log_entry in $container_name..."
  until docker logs $container_name 2>&1 | grep -q "$log_entry"; do
    sleep $wait_time
    retry_count=$((retry_count+1))

    # Check if the container is still running
    check_container_running
    if [ $? -ne 0 ]; then
      return 1
    fi

    if [ $retry_count -ge $max_retries ]; then
      echo "Log entry $log_entry not found in $container_name within the expected time."
      kill $log_pid  # Terminate the background log tail process
      return 1
    fi
  done

  echo "Log entry $log_entry found in $container_name."
  kill $log_pid  # Terminate the background log tail process
  return 0
}

# Function to monitor and record peak memory usage of a Docker container
monitor_memory_usage() {
  local container_name=$1
  local output_file=$2
  local max_memory=0

  # Monitor memory usage in the background
  (
    while [ "$(docker ps -q -f name=$container_name)" ]; do
      memory=$(docker stats --no-stream --format "{{.MemUsage}}" $container_name | awk '{print $1}')
      memory=${memory%M}
      if (( $(echo "$memory > $max_memory" | bc -l) )); then
        max_memory=$memory
      fi
      sleep 0.5
    done
    echo "Peak memory usage: $max_memory MB" > "$output_file"
  ) &
  mem_pid=$!

  echo $mem_pid
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

  docker stop gas-execution-client
  docker stop gas-execution-client-sync
  docker rm gas-execution-client
  docker rm gas-execution-client-sync

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
            
      if [ "$client" = "nethermind" ] || [ "$client" = "besu" ]; then
        mem_output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M_mem.txt"
        mem_pid=$(monitor_memory_usage "gas-execution-client" "$mem_output_file")
      else 
        mem_output_file="${OUTPUT_DIR}/${client}_${run}_first_${size}M_mem.txt"
        mem_pid=$(monitor_memory_usage "gas-execution-client-sync" "$mem_output_file")
      fi

      # After the initialization check and recording the interval, make sure to kill the memory monitoring process
      check_initialization_completed $client "$log_entry"
      if [ $? -ne 0 ]; then
        echo "Initialization check failed for client $client"
        kill $mem_pid  # Terminate the memory monitoring process
        continue
      fi

      # Record the time when the initialization is completed
      initialization_time=$(($(date +%s%N) / 1000000))
      interval=$((initialization_time - start_time))

      output_file="${OUTPUT_DIR}/${client}_${run}_first_${size}M.txt"
      echo "$interval" > "$output_file"
      echo "=== Interval $interval written to $output_file ==="

      # Kill the memory monitoring process after the interval is recorded
      kill $mem_pid

      cd "scripts/$client"
      docker compose down execution -t 0
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

      if [ "$client" = "nethermind" ] || [ "$client" = "besu" ]; then
        mem_output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M_mem.txt"
        mem_pid=$(monitor_memory_usage "gas-execution-client" "$mem_output_file")
      else 
        mem_output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M_mem.txt"
        mem_pid=$(monitor_memory_usage "gas-execution-client-sync" "$mem_output_file")
      fi

      # Check initialization completion
      check_initialization_completed $client "$log_entry"
      if [ $? -ne 0 ]; then
        echo "Initialization check failed for client $client"
        kill $mem_pid  # Terminate the memory monitoring process
        continue
      fi

      # Record the time when the initialization is completed
      initialization_time=$(($(date +%s%N) / 1000000))
      interval=$((initialization_time - start_time))

      output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M.txt"
      echo "$interval" > "$output_file"
      echo "=== Interval $interval written to $output_file ==="

      # Kill the memory monitoring process after the interval is recorded
      kill $mem_pid

      cd "scripts/$client"
      docker compose down -t 0
      sudo rm -rf execution-data
      cd ../..

    done
  done
done

python3 report.py 
