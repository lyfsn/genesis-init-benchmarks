# Prepare nethermind image that we will use on the script
cd scripts/besu

cp ../../tests/tmp/besu.json /tmp/besu.json
cp jwtsecret /tmp/jwtsecret

docker compose up -d

docker compose logs
