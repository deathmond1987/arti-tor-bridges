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
LOCK_FILE=./.scanner

## set tor relay scanner variables
NUM_RELAYS=${NUM_RELAYS:=100}
MIN_RELAYS=${MIN_RELAYS:=1}
RELAY_TIMEOUT=${RELAY_TIMEOUT:=3}
SENSITIVE_LOG=${SENSITIVE_LOG:=true}
## set arti config default values
SOCKS_LISTEN=${SOCKS_LISTEN:=9150}

## print tor scanner variables
warn "simultaneously scanning relays: ${NUM_RELAYS}"
warn "minimum number of relays before start arti: ${MIN_RELAYS}"
warn "timeout probing for single relay: ${RELAY_TIMEOUT}"

cd /arti
## copy config example to arti dir
cp /arti/conf_example.toml /arti/arti_conf_example.toml

## remove generated config. it will be regenerated

if [ -f "${CONFIG_FILE}" ]; then
    warn "remove config file. it will be regenerated"
    rm -f "${CONFIG_FILE}"
fi

## generating arti config
create_config () {
    success "generating config file"
    
    ## setup arti socket port
    warn "  set proxy port: ${SOCKS_LISTEN}"
    echo "[proxy]" >> "${CONFIG_FILE}"
    echo "socks_listen = ${SOCKS_LISTEN}" >> "${CONFIG_FILE}"

    ## setup log sensitive information 
    warn "  set log sensitive information:"
    echo "[logging]" >> "$CONFIG_FILE"
    echo "log_sensitive_information = ${SENSITIVE_LOG}" >> "${CONFIG_FILE}"

    ## set listen address 0.0.0.0
    warn "set prepouting. arti itself listen only 127.0.0.01"
    iptables -t nat -A PREROUTING -p tcp --dport ${SOCKS_LISTEN} -j DNAT --to-destination 127.0.0.1:${SOCKS_LISTEN}
}

launch_arti () {
    ## creating lock file to temporary disable healthcheck
    touch "${LOCK_FILE}"

    ## searching open port from bridge list with tor-relay-scanner by valdikSS
    ## and write founded list to file
    while [ ! -s "$BRIDGE_FILE" ]; do
        ./tor-relay-scanner -n "${NUM_RELAYS}" \
                            -g "${MIN_RELAYS}" \
                            --timeout "${RELAY_TIMEOUT}" > "${BRIDGE_FILE}"
    done

    ## arti using toml configuration
    ## generating file top part
    echo "[bridges]

enabled = true
bridges =[" > "${CONFIG_FILE}"

    ## from list of founded bridges copy strings to config file
    ## sed will change all lines to match toml
    ## (add   "Bridge  to start line and ", at the end)
    sed 's/^/  "Bridge /; s/$/",/' "$BRIDGE_FILE" | tee -a "${CONFIG_FILE}"

    ## closing toml config
    echo "]">> "${CONFIG_FILE}"

    create_config

    ## prepare to takeoff
    success "number of relays scanner found: $(wc -l < ${BRIDGE_FILE})"
    ## delete useles file
    rm -f "${BRIDGE_FILE}"
    ## removing lock file to enable healthcheck
    rm -f "${LOCK_FILE}"

    "$@"
}

launch_arti "$@"
