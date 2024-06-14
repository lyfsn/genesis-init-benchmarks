#!/bin/bash

# Default inputs
TEST_PATH="tests/"
CLIENTS="nethermind,geth,reth"
RUNS=8
IMAGES="default"
OUTPUT_DIR="results/memory"
SIZES=("1" "64" "512")

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

mkdir -p "$OUTPUT_DIR" "$TEST_PATH/tmp"

# Install dependencies
install_dependencies() {
  echo "[INFO] Installing dependencies..."
  pip install -r requirements.txt
  apt install -y jq
  python3 computer_specs.py --output_folder "$OUTPUT_DIR"
  echo "[INFO] Dependencies installed."
}

install_dependencies

wait_for_container() {
  local container_name=$1
  local max_retries=7200
  local retry_count=0
  local wait_time=0.5

  echo "[INFO] Waiting for container $container_name to start..."
  while [ $retry_count -lt $max_retries ]; do
    if docker ps -q -f name="$container_name" &>/dev/null; then
      echo "[INFO] Container $container_name is running."
      return 0
    fi
    retry_count=$((retry_count + 1))
    sleep $wait_time
  done

  echo "[ERROR] Container $container_name did not start after $max_retries retries."
  return 1
}

check_initialization_completed() {
  local client=$1
  local log_entry=$2
  local container_name=$3

  if ! wait_for_container "$container_name"; then
    return 1
  fi

  local max_retries=7200
  local retry_count=0
  local wait_time=0.5

  echo "[INFO] Waiting for log entry: '$log_entry' in $container_name..."
  until docker logs "$container_name" 2>&1 | grep -q "$log_entry"; do
    sleep $wait_time
    retry_count=$((retry_count + 1))

    if ! wait_for_container "$container_name"; then
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

start_monitoring() {
  local client=$1
  local run=$2
  local size=$3
  local suffix=$4
  local container_name=$5
  local max_memory=0
  local wait_time=0.1
  local mem_output_file="${OUTPUT_DIR}/${client}_${run}_${suffix}_${size}M.txt"
  local unique_id="monitor_$client_$run_$size"

  {
    if ! wait_for_container "$container_name"; then
      exit 1
    fi

    while :; do

      stats_output=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_name")
      mem_usage=$(echo "$stats_output" | awk '{print $1}' | tr -d '[:alpha:]')
      mem_unit=$(echo "$stats_output" | awk '{print $1}' | tr -d '[:digit:]')

      case $mem_unit in
        MiB) mem_usage_mib=$mem_usage ;;
        GiB) mem_usage_mib=$(echo "$mem_usage * 1024" | bc -l) ;;
        KiB) mem_usage_mib=$(echo "scale=2; $mem_usage / 1024" | bc -l) ;;
        B)   mem_usage_mib=$(echo "scale=2; $mem_usage / 1024 / 1024" | bc -l) ;;
        *)   mem_usage_mib=0 ;;
      esac

      if (( $(echo "$mem_usage_mib > $max_memory" | bc -l) )); then
        max_memory=$mem_usage_mib
      fi

      echo "$max_memory" > "$mem_output_file"
      sleep $wait_time
    done
  } & echo $!
}

stop_monitoring() {
  if [ -n "$mem_pid" ]; then
    kill -9 $mem_pid
    wait $mem_pid 2>/dev/null
    echo "[INFO] Stopped memory monitoring with PID $mem_pid"
    mem_pid=""
  fi

  unique_id_pattern="monitor_"
  pids=$(pgrep -f "$unique_id_pattern")
  if [ -n "$pids" ]; then
    echo "[INFO] Killing all runMemory.sh processes with unique ID pattern '$unique_id_pattern': $pids"
    kill -9 $pids
    wait $pids 2>/dev/null
  fi
}

container_exists() {
  local container_name=$1
  [ "$(docker ps -a -q -f name=$container_name)" ]
}

clean_up() {
  echo "[INFO] Cleaning up containers and data..."
  stop_monitoring
  for container_name in gas-execution-client gas-execution-client-sync; do
    if container_exists "$container_name"; then
      docker stop "$container_name"
      docker rm "$container_name"
    fi
  done
  docker container prune -f
  sudo rm -rf execution-data
  echo "[INFO] Cleanup completed."
}

trap clean_up EXIT

for size in "${SIZES[@]}"; do
  echo "======================================"
  echo "[INFO] Running benchmarks for size ${size}M"
  echo "======================================"

  new_size=$(echo "scale=2; ($size / 1.2 + 0.5)/1" | bc)
  if [ $? -ne 0 ]; then
    echo "[ERROR] Error calculating new size with bc"
    exit 1
  fi
  echo "[INFO] New size calculated: $new_size"

  echo "[INFO] Generating chainspec, genesis, and besu files..."
  python3 generate_chainspec.py "$TEST_PATH/chainspec.json" "$TEST_PATH/tmp/chainspec.json" "$new_size"
  python3 generate_genesis.py "$TEST_PATH/genesis.json" "$TEST_PATH/tmp/genesis.json" "$new_size"
  python3 generate_besu.py "$TEST_PATH/besu.json" "$TEST_PATH/tmp/besu.json" "$new_size"

  clean_up

  for run in $(seq 1 $RUNS); do
    for I in "${!CLIENT_ARRAY[@]}"; do
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
      clean_up
      docker compose down --remove-orphans
      cd ../..

      container_name="gas-execution-client"
      [ "$client" != "nethermind" ] && [ "$client" != "besu" ] && container_name="gas-execution-client-sync"

      start_monitoring "$client" "$run" "$size" "first" "$container_name"
      [ -z "$image" ] && python3 setup_node.py --client "$client" || python3 setup_node.py --client "$client" --image "$image"
      check_initialization_completed "$client" "$log_entry" "$container_name" || { stop_monitoring; continue; }
      stop_monitoring

      cd "scripts/$client"
      docker compose stop
      cd ../..

      start_monitoring "$client" "$run" "$size" "second" "$container_name"
      [ -z "$image" ] && python3 setup_node.py --client "$client" --second-start || python3 setup_node.py --client "$client" --image "$image" --second-start
      check_initialization_completed "$client" "$log_entry" "$container_name" || { stop_monitoring; continue; }
      stop_monitoring

      cd "scripts/$client"
      clean_up
      docker compose down --remove-orphans
      cd ../..
    done
  done
done

python3 report_memory.py --resultsPath "$OUTPUT_DIR"
echo "[INFO] Benchmarking completed and report generated."