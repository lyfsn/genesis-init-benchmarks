


#!/bin/bash

nohup \
  ./runMemory.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 8 \
  -o "results/memory" \
  -s 1,10,100,500,1000,1500 \
  > output.log 2>&1 &

