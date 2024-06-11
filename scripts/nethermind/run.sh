# Prepare nethermind image that we will use on the script
cd scripts/nethermind


cp ../../tests/tmp/chainspec.json /tmp/chainspec.json
cp jwtsecret /tmp/jwtsecret

docker compose up -d

docker compose logs
