# Prepare nethermind image that we will use on the script
cd scripts/besu

cp ../../../el-cl-genesis-data/custom_config_data/besu.json /tmp/besu.json
cp jwtsecret /tmp/jwtsecret

docker compose up -d

docker compose logs
