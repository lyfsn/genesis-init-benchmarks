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
  local max_retries=7200
  local retry_count=0
  local wait_time=0.5  # 500 milliseconds
  local max_wait_time=120  # 2 minutes
  local container_check_retries=12
  local container_retry_count=0

  # Function to check if the container is still running with retries
  check_container_running() {
    while [ $container_retry_count -lt $container_check_retries ]; do
      if [ -z "$(docker ps -q -f name=$container_name)" ]; then
        echo "Container $container_name has stopped unexpectedly. Retrying... ($((container_retry_count + 1))/$container_check_retries)"
        container_retry_count=$((container_retry_count + 1))
        sleep $max_wait_time
      else
        return 0
      fi
    done
    echo "Container $container_name has stopped unexpectedly after $container_check_retries retries."
    return 1
  }

  check_container_running
  if [ $? -ne 0 ]; then
    return 1
  fi

  echo "Container $container_name has started."

  # Reset retry count for log entry check
  retry_count=0
  echo "Waiting for log entry: $log_entry in $container_name..."
  until docker logs $container_name 2>&1 | grep -q "$log_entry"; do
    sleep $wait_time
    retry_count=$((retry_count+1))

    check_container_running
    if [ $? -ne 0 ]; then
      return 1
    fi

    if [ $retry_count -ge $max_retries ]; then
      echo "Log entry $log_entry not found in $container_name within the expected time."
      return 1
    fi
  done

  echo "Log entry $log_entry found in $container_name."
  return 0
}

# Function to monitor and record peak memory usage of a Docker container
monitor_memory_usage() {
  local container_name=$1
  local output_file=$2
  local max_memory=0
  echo "-1" > "$output_file"

  {
    while :; do
      if [ "$(docker ps -q -f name=$container_name)" ]; then
        # Extract memory usage and remove any potential units (like MiB, GiB)
        memory=$(docker stats --no-stream --format "{{.MemUsage}}" $container_name | awk '{print $1}')
        echo "Raw memory usage: $memory"  # Debug output

        # Convert memory usage to MiB if necessary
        if [[ $memory == *MiB ]]; then
          memory=$(echo $memory | sed 's/[^0-9.]//g')
        elif [[ $memory == *GiB ]]; then
          memory=$(echo $memory | sed 's/[^0-9.]//g')
          memory=$(echo "$memory * 1024" | bc)
        else
          memory=0
        fi

        echo "Converted memory usage in MiB: $memory"  # Debug output

        if (( $(echo "$memory > $max_memory" | bc -l) )); then
          max_memory=$memory
        fi
        echo "$max_memory" > "$output_file"  # Write the max memory to the file in each iteration
      fi
      sleep 0.1
    done
  } &
  echo $!
}

mkdir -p $TEST_PATH/tmp

start_monitoring() {
  local client=$1
  local run=$2
  local size=$3
  if [ "$client" = "nethermind" ] || [ "$client" = "besu" ]; then
    mem_output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M_mem.txt"
    mem_pid=$(monitor_memory_usage "gas-execution-client" "$mem_output_file")
  else 
    mem_output_file="${OUTPUT_DIR}/${client}_${run}_first_${size}M_mem.txt"
    mem_pid=$(monitor_memory_usage "gas-execution-client-sync" "$mem_output_file")
  fi
  echo "Started memory monitoring with PID $mem_pid"
}

stop_monitoring() {
  if [ -n "$mem_pid" ]; then
    kill $mem_pid
    echo "Stopped memory monitoring with PID $mem_pid"
  fi
}

# Outer loop
for size in "${SIZES[@]}"; do
  echo "=== Running benchmarks for size ${size}M ==="
  
  echo "Calculating new size for $size"
  new_size=$(echo "scale=2; ($size / 1.2 + 0.5)/1" | bc)
  if [ $? -ne 0 ]; then
    echo "Error calculating new size with bc"
    exit 1
  fi
  echo "New size calculated: $new_size"

  # Generate chainspec, genesis, and besu files
  # python3 generate_chainspec.py $TEST_PATH/chainspec.json $TEST_PATH/tmp/chainspec.json $new_size
  # python3 generate_genesis.py $TEST_PATH/genesis.json $TEST_PATH/tmp/genesis.json $new_size
  # python3 generate_besu.py $TEST_PATH/besu.json $TEST_PATH/tmp/besu.json $new_size

  docker stop gas-execution-client
  docker stop gas-execution-client-sync
  docker rm gas-execution-client
  docker rm gas-execution-client-sync

  # Run benchmarks
  for run in $(seq 1 $RUNS); do
    for I in "${!CLIENT_ARRAY[@]}"; do
      echo "=== Run round $run - Client ${CLIENT_ARRAY[$I]} - Image ${IMAGE_ARRAY[$I]} ==="

      client="${CLIENT_ARRAY[$I]}"
      image="${IMAGE_ARRAY[$I]}"

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

      start_monitoring $client $run $size &

      if [ -z "$image" ]; then
        echo "Image input is empty, using default image."
        python3 setup_node.py --client $client
      else
        echo "Using provided image: $image for $client"
        python3 setup_node.py --client $client --image $image
      fi

      # After the initialization check and recording the interval, make sure to kill the memory monitoring process
      check_initialization_completed $client "$log_entry"
      if [ $? -ne 0 ]; then
        echo "Initialization check failed for client $client"
        stop_monitoring
        continue
      fi

      # Record the time when the initialization is completed
      initialization_time=$(($(date +%s%N) / 1000000))
      interval=$((initialization_time - start_time))

      output_file="${OUTPUT_DIR}/${client}_${run}_first_${size}M.txt"
      echo "$interval" > "$output_file"
      echo "=== Interval $interval written to $output_file ==="

      # Kill the memory monitoring process after the interval is recorded
      stop_monitoring

      cd "scripts/$client"
      docker compose stop -t 0
      cd ../..

      # Record the second start time
      start_time=$(($(date +%s%N) / 1000000))
      start_monitoring $client $run $size &

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
        stop_monitoring
        continue
      fi

      # Record the time when the initialization is completed
      initialization_time=$(($(date +%s%N) / 1000000))
      interval=$((initialization_time - start_time))

      output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M.txt"
      echo "$interval" > "$output_file"
      echo "=== Interval $interval written to $output_file ==="

      # Kill the memory monitoring process after the interval is recorded
      stop_monitoring

      cd "scripts/$client"
      docker compose down -t 0
      sudo rm -rf execution-data
      cd ../..
    done
  done
done

python3 report.py