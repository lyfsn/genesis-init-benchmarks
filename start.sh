


#!/bin/bash

nohup \
  ./run.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 8 \
  -o "results" \
  -s 1,10,100,1000,2000 \
  > output.log 2>&1 &


./run.sh \
  -t "tests/" \
  -c "nethermind" \
  -r 1 \
  -o "results" \
  -s 1,10



./run.sh \
  -t "tests/" \
  -c "erigon" \
  -r 1 \
  -o "results" \
  -s 1,100,1000
