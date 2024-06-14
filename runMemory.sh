#!/bin/bash

TEST_PATH="tests/"
CLIENTS="nethermind,geth,reth"
RUNS=8
IMAGES="default"
OUTPUT_DIR="results/memory"
SIZES=("1" "64" "512")

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

mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEST_PATH/tmp"

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt
apt install -y jq
python3 computer_specs.py --output_folder "$OUTPUT_DIR"
echo "Dependencies installed."

check_initialization_completed() {
  local client=$1
  local log_entry=$2
  local container_name="gas-execution-client"
  local max_retries=7200
  local retry_count=0
  local wait_time=0.5 
  local max_wait_time=120 
  local container_check_retries=12
  local container_retry_count=0

  check_container_running() {
    while [ $container_retry_count -lt $container_check_retries ]; do
      if [ -z "$(docker ps -q -f name=$container_name)" ]; then
        echo "[ERROR] Container $container_name has stopped unexpectedly. Retrying... ($((container_retry_count + 1))/$container_check_retries)"
        container_retry_count=$((container_retry_count + 1))
        sleep $max_wait_time
      else
        return 0
      fi
    done
    echo "[ERROR] Container $container_name has stopped unexpectedly after $container_check_retries retries."
    return 1
  }

  check_container_running
  if [ $? -ne 0 ]; then
    return 1
  fi

  echo "[INFO] Container $container_name has started."

  retry_count=0
  echo "[INFO] Waiting for log entry: '$log_entry' in $container_name..."
  until docker logs $container_name 2>&1 | grep -q "$log_entry"; do
    sleep $wait_time
    retry_count=$((retry_count+1))

    check_container_running
    if [ $? -ne 0 ]; then
      return 1
    fi

    if [ $retry_count -ge $max_retries ]; then
      echo "[ERROR] Log entry '$log_entry' not found in $container_name within the expected time."
      return 1
    fi
  done

  echo "[INFO] Log entry '$log_entry' found in $container_name."
  return 0
}

monitor_memory_usage() {
  local container_name=$1
  local output_file=$2
  local interval=1
  local max_memory_usage=0

  echo "[INFO] Starting memory monitoring for $container_name..."

  while true; do
    current_memory=$(docker stats --no-stream --format "{{.MemUsage}}" $container_name | awk -F '[ /]+' '{print $1}' | sed 's/[^0-9.]//g')
    if (( $(echo "$current_memory > $max_memory_usage" | bc -l) )); then
      max_memory_usage=$current_memory
      echo "$max_memory_usage" > "$output_file"
    fi
    sleep $interval
  done &
  monitor_pid=$!

  trap "kill $monitor_pid" EXIT

  echo "[INFO] Memory monitoring for $container_name with PID $monitor_pid started."
}

stop_memory_monitor() {
  local output_file=$1
  echo "[INFO] Stopping memory monitoring..."

  kill $monitor_pid
  wait $monitor_pid 2>/dev/null

  local max_memory_usage=$(awk 'BEGIN{max=0} {if($1>max) max=$1} END{print max}' "$output_file")
  echo "$max_memory_usage" > "$output_file"
  echo "[INFO] Max memory usage $max_memory_usage written to $output_file"
}

clean_up() {
  echo "[INFO] Cleaning up containers and data..."
  docker stop gas-execution-client gas-execution-client-sync
  docker rm gas-execution-client gas-execution-client-sync
  docker container prune -f
  sudo rm -rf execution-data
  echo "[INFO] Cleanup completed."
}

for size in "${SIZES[@]}"; do
  echo "======================================"
  echo "[INFO] Running benchmarks for size ${size}M"
  echo "======================================"

  echo "[INFO] Calculating new size for $size"
  new_size=$(echo "scale=2; ($size / 1.2 + 0.5)/1" | bc)
  if [ $? -ne 0 ]; then
    echo "[ERROR] Error calculating new size with bc"
    exit 1
  fi
  echo "[INFO] New size calculated: $new_size"

  python3 generate_chainspec.py $TEST_PATH/chainspec.json $TEST_PATH/tmp/chainspec.json $new_size
  python3 generate_genesis.py $TEST_PATH/genesis.json $TEST_PATH/tmp/genesis.json $new_size
  python3 generate_besu.py $TEST_PATH/besu.json $TEST_PATH/tmp/besu.json $new_size

  clean_up

  for run in $(seq 1 $RUNS); do
    for I in "${!CLIENT_ARRAY[@]}"; do
      echo "--------------------------------------"
      echo "[INFO] Run round $run - Client ${CLIENT_ARRAY[$I]} - Image ${IMAGE_ARRAY[$I]}"
      echo "--------------------------------------"

      client="${CLIENT_ARRAY[$I]}"
      image="${IMAGE_ARRAY[$I]}"

      case $client in
        nethermind) log_entry="initialization completed" ;;
        reth) log_entry="Starting reth" ;;
        erigon) log_entry="logging to file system" ;;
        geth) log_entry="Set global gas cap" ;;
        besu) log_entry="Writing node record to disk" ;;
      esac

      cd "scripts/$client"
      docker compose down --remove-orphans
      clean_up
      cd ../..

      if [[ "$client" == "nethermind" || "$client" == "besu" ]]; then
        memory_output_file="${OUTPUT_DIR}/${client}_${run}_first_${size}M.txt"
        monitor_memory_usage "gas-execution-client" $memory_output_file
      else
        memory_output_file="${OUTPUT_DIR}/${client}_${run}_first_${size}M.txt"
        monitor_memory_usage "gas-execution-client-sync" $memory_output_file
      fi

      if [ -z "$image" ]; then
        echo "[INFO] Image input is empty, using default image."
        python3 setup_node.py --client $client
      else
        echo "[INFO] Using provided image: $image for $client"
        python3 setup_node.py --client $client --image $image
      fi

      check_initialization_completed $client "$log_entry"
      if [ $? -ne 0 ]; then
        echo "[ERROR] Initialization check failed for client $client"
        stop_memory_monitor $memory_output_file
        continue
      fi

      stop_memory_monitor $memory_output_file

      cd "scripts/$client"
      docker compose stop
      clean_up
      cd ../..

      if [[ "$client" == "nethermind" || "$client" == "besu" ]]; then
        memory_output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M.txt"
        monitor_memory_usage "gas-execution-client" $memory_output_file
      else
        memory_output_file="${OUTPUT_DIR}/${client}_${run}_second_${size}M.txt"
        monitor_memory_usage "gas-execution-client-sync" $memory_output_file
      fi

      if [ -z "$image" ]; then
        echo "[INFO] Image input is empty, using default image."
        python3 setup_node.py --client $client --second-start
      else
        echo "[INFO] Using provided image: $image for $client"
        python3 setup_node.py --client $client --image $image --second-start
      fi

      check_initialization_completed $client "$log_entry"
      if [ $? -ne 0 ]; then
        echo "[ERROR] Initialization check failed for client $client"
        stop_memory_monitor $memory_output_file
        continue
      fi

      stop_memory_monitor $memory_output_file

      cd "scripts/$client"
      docker compose down --remove-orphans
      clean_up
      cd ../..
    done
  done
done

python3 report_memory.py --resultsPath $OUTPUT_DIR
echo "[INFO] Benchmarking completed and report generated."