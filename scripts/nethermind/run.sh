# Prepare nethermind image that we will use on the script
cd scripts/nethermind

cp ../../../el-cl-genesis-data/custom_config_data/chainspec.json /tmp/chainspec.json
cp jwtsecret /tmp/jwtsecret

docker compose up -d

docker compose logs
