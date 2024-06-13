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

mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEST_PATH/tmp"

# Install dependencies
echo "[INFO] Installing dependencies..."
pip install -r requirements.txt
apt install -y jq
python3 computer_specs.py --output_folder $OUTPUT_DIR
echo "[INFO] Dependencies installed."

monitor_memory_usage() {
  local container_name=$1
  local output_file=$2
  local max_memory=0
  echo "-1" > "$output_file"

  {
    while :; do
      if [ "$(docker ps -q -f name=$container_name)" ]; then
        memory=$(docker stats --no-stream --format "{{.MemUsage}}" $container_name | awk '{print $1}')
        echo "[DEBUG] Raw memory usage: $memory"  # Debug output

        if [[ $memory == *MiB ]]; then
          memory=$(echo $memory | sed 's/[^0-9.]//g')
        elif [[ $memory == *GiB ]]; then
          memory=$(echo $memory | sed 's/[^0-9.]//g')
          memory=$(echo "$memory * 1024" | bc)
        else
          memory=0
        fi

        echo "[DEBUG] Converted memory usage in MiB: $memory"  # Debug output

        if (( $(echo "$memory > $max_memory" | bc -l) )); then
          max_memory=$memory
        fi
        echo "$max_memory" > "$output_file"
      fi
      sleep 0.1
    done
  } &
  echo $!
}

start_monitoring() {
  local client=$1
  local run=$2
  local size=$3
  local suffix=$4
  local container_name
  if [ "$client" = "nethermind" ] || [ "$client" = "besu" ]; then
    container_name="gas-execution-client"
  else
    container_name="gas-execution-client-sync"
  fi
  mem_output_file="${OUTPUT_DIR}/${client}_${run}_${suffix}_${size}M.txt"
  mem_pid=$(monitor_memory_usage "$container_name" "$mem_output_file")
  echo "[INFO] Started memory monitoring with PID $mem_pid"
}

stop_monitoring() {
  if [ -n "$mem_pid" ]; then
    kill $mem_pid
    echo "[INFO] Stopped memory monitoring with PID $mem_pid"
  fi
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

  echo "[INFO] Generating chainspec, genesis, and besu files..."
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

      cd "scripts/$client"
      docker compose down --remove-orphans
      clean_up
      cd ../..

      start_monitoring $client $run $size "first"

      if [ -z "$image" ]; then
        echo "[INFO] Image input is empty, using default image."
        python3 setup_node.py --client $client
      else
        echo "[INFO] Using provided image: $image for $client"
        python3 setup_node.py --client $client --image $image
      fi

      stop_monitoring

      cd "scripts/$client"
      docker compose stop
      cd ../..

      start_monitoring $client $run $size "second"

      if [ -z "$image" ]; then
        echo "[INFO] Image input is empty, using default image."
        python3 setup_node.py --client $client --second-start
      else
        echo "[INFO] Using provided image: $image for $client"
        python3 setup_node.py --client $client --image $image --second-start
      fi

      stop_monitoring

      cd "scripts/$client"
      docker compose down --remove-orphans
      clean_up
      cd ../..
    done
  done
done

python3 report_memory.py --resultsPath $OUTPUT_DIR
echo "[INFO] Benchmarking completed and report generated."