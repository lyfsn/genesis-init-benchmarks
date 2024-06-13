


#!/bin/bash

nohup \
  ./run.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 8 \
  -o "results" \
  -s 1,64,512,1024,2048 \
  > output.log 2>&1 &


nohup \
  ./run.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 8 \
  -o "results" \
  -s 512,1024 \
  > output.log 2>&1 &

nohup \
  ./run.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 8 \
  -o "results" \
  -s 1,32,64,256,512,1024,2048 \
  > output.log 2>&1 &

nohup \
  ./run.sh \
  -t "tests/" \
  -c "nethermind,geth,reth,erigon,besu" \
  -r 1 \
  -o "results" \
  -s 1,2,3 \
  > output.log 2>&1 &

./run.sh \
  -t "tests/" \
  -c "nethermind" \
  -r 1 \
  -o "results" \
  -s 1,10


./run.sh \
  -t "tests/" \
  -c "geth" \
  -r 1 \
  -o "results" \
  -s 1000

./run.sh \
  -t "tests/" \
  -c "erigon" \
  -r 4 \
  -o "results" \
  -s 1,100,1000


./run.sh \
  -t "tests/" \
  -c "besu" \
  -r 1 \
  -o "results" \
  -s 1