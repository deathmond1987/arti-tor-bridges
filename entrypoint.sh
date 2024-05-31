#!/usr/bin/env ash
set -ex

cd /arti
./tor-relay-scanner -n "${NUM_RELAYS:=100}" -g "${MIN_RELAYS:=1}" --timeout "${RELAY_TIMEOUT:=3}" > bridges

echo "[bridges]

enabled = true
bridges =[" > arti-bridges.conf

sed 's/^/  "Bridge /; s/$/",/' ./bridges | tee -a arti-bridges.conf

echo "]" >> arti-bridges.conf
cat ./arti-bridges.conf

"$@"