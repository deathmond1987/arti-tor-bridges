#!/usr/bin/env ash
# shellcheck disable=SC2187
set -ex

## output setup
reset="\033[0m"
red="\033[0;31m"
green="\033[0;32m"
white="\033[0;37m"
tan="\033[0;33m"
info() { printf "${white}%s${reset}\n" "$@"
}
success() { printf "${green}%s${reset}\n" "$@"
}
error() { >&2 printf "${red}%s${reset}\n" "$@"
}
warn() { printf "${tan}%s${reset}\n" "$@"
}

## script variables
CONFIG_FILE=./arti-bridges.conf
BRIDGE_FILE=./bridges

## set variables
NUM_RELAYS=${NUM_RELAYS:=100}
MIN_RELAYS=${MIN_RELAYS:=1}
RELAY_TIMEOUT=${RELAY_TIMEOUT:=3}

## print setup variables
info "simultaneously scanning relays: ${NUM_RELAYS}"
info "minimum number of relays before start arti: ${MIN_RELAYS}"
info "timeout probing for single relay: ${RELAY_TIMEOUT}"

cd /arti
mkdir -p ./data
cp /arti/conf_example.toml /arti/data/arti_conf_example.toml

## searching open port from bridge list with tor-relay-scanner by valdikSS
## and write founded list to file
./tor-relay-scanner -n "${NUM_RELAYS}" \
                    -g "${MIN_RELAYS}" \
                    --timeout "${RELAY_TIMEOUT}" > "$BRIDGE_FILE"
if [ ! -f "$BRIDGE_FILE" ]; then
    error "bridges not found"
    exit 1
else 
    sed -i '/###SCANNER GEN###/,/###END SCANNER GEN###/d' "$CONFIG_FILE"
fi

## arti using toml configuration
## generating file top part
echo "###SCANNER GEN###
[bridges]

enabled = true
bridges =[" > "$CONFIG_FILE"

## from list of founded bridges copy strings to config file
## sed will change all lines to match toml
## (add   "Bridge  to start line and ", at the end)
sed 's/^/  "Bridge /; s/$/",/' "$BRIDGE_FILE" | tee -a "$CONFIG_FILE"

## closing toml config
echo "]
###END SCANNER GEN###" >> "$CONFIG_FILE"

## prepare to takeoff
success "number of relays scanner found: $(wc -l < $BRIDGE_FILE)"
## delete useles file 
rm -f "$BRIDGE_FILE"

"$@"
