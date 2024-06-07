# Prepare geth image that we will use on the script
cd scripts/erigon
cp ../../../el-cl-genesis-data/custom_config_data/genesis.json /tmp/genesis.json
cp jwtsecret /tmp/jwtsecret

docker compose up -d

docker compose logs