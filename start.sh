


#!/bin/bash

nohup \
  ./run.sh \
  -t "tests/" \
  -w "warmup/warmup-1000bl-16wi-24tx.txt" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 4 \
  -o "results" \
  > output.log 2>&1 &


./run.sh \
  -t "tests/" \
  -w "warmup/warmup-1000bl-16wi-24tx.txt" \
  -c "nethermind" \
  -r 1 \
  -o "results"


./run.sh \
  -t "tests/" \
  -w "warmup/warmup-1000bl-16wi-24tx.txt" \
  -c "reth" \
  -r 1 \
  -o "results"
