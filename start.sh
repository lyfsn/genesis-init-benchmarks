


#!/bin/bash

nohup \
  ./runSpeed.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 8 \
  -o "results/speed" \
  -s 1,32,64,256,512,1024,2048 \
  > output.log 2>&1 &

nohup \
  ./runMemory.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 8 \
  -o "results/memory" \
  -s 1,32,64,256,512,1024,2048 \
  > output.log 2>&1 &

