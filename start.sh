


#!/bin/bash

nohup \
  ./runSpeed.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 8 \
  -o "results" \
  -s 1,32,64,256,512,1024,2048 \
  > output.log 2>&1 &


./runSpeed.sh \
  -t "tests/" \
  -c "nethermind" \
  -r 1 \
  -o "results/speed" \
  -s 1


./runMemory.sh \
  -t "tests/" \
  -c "nethermind" \
  -r 1 \
  -o "results/memory" \
  -s 1

./runMemory.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 1 \
  -o "results/memory" \
  -s 100


./runMemory.sh \
  -t "tests/" \
  -c "geth" \
  -r 1 \
  -o "results/memory" \
  -s 1000