# Prepare geth image that we will use on the script
cd scripts/geth


cp ../../tests/tmp/genesis.json /tmp/genesis.json
cp jwtsecret /tmp/jwtsecret

docker compose up -d

docker compose logs