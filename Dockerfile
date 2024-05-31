## build container for arti
FROM alpine:latest as build
## local problems with ssl
ENV GIT_SSL_NO_VERIFY=true
## updating distro
RUN apk update --no-cache
## add build deps
RUN apk add cargo \
            git \
            pkgconf \
            openssl-dev \
            sqlite-dev --no-cache
## cloning arti
RUN git clone https://gitlab.torproject.org/tpo/core/arti.git
## set git dir as workdir
WORKDIR /arti
## release kraken (build arti)
RUN cargo build -p arti --locked --release
#RUN cd ./examples/gsoc2023/connection-checker && cargo build -p connection-checker --locked --release

## build container for tor-relay-scanner
FROM alpine:latest AS bridge-builder
## set workdir variable
ARG APP_DIR=torparse
## add python, clone git and build cython package of tor-build-scanner
RUN apk add python3 \
    py3-pip \
    pipx \
    git \
    binutils &&\
    pipx install pyinstaller &&\
    export PATH=/root/.local/bin:$PATH &&\
    git clone --branch main https://github.com/ValdikSS/tor-relay-scanner.git &&\
    cd tor-relay-scanner &&\
    pip install . --target "$APP_DIR" &&\
    find "$APP_DIR" -path '*/__pycache__*' -delete &&\
    cp "$APP_DIR"/tor_relay_scanner/__main__.py "$APP_DIR"/ &&\
    pyinstaller -F --paths "$APP_DIR" "$APP_DIR"/__main__.py

## configuring output image 
FROM alpine:latest as release
## add libgcc (needed for rust)
## add sqlite-libc (needed for arti)
## add tini (zombies, run!)
## add curl (healthcheck)
RUN apk update --no-cache && apk add libgcc sqlite-libs tini curl --no-cache
## add user and group for app
RUN addgroup -S arti && adduser -S arti -G arti
## add workdir
RUN mkdir /arti
## chown workdir
RUN chown -R arti:arti /arti
## copy arti binary to container
COPY --from=build --chmod=755 /arti/target/release/arti /arti/arti
#COPY --from=build /arti/target/release/connection-checker /arti/connection-checker
## copy arti example config to container
COPY --from=build /arti/crates/arti/src/arti-example-config.toml /arti/conf_example.toml
## add tor relay scanner binary to container
COPY --from=bridge-builder --chmod=755 /tor-relay-scanner/dist/__main__ /arti/tor-relay-scanner
## add entrypoint.sh to container
COPY --chmod=755 ./entrypoint.sh /
## set workdir
WORKDIR /arti
## set arti binary owner
RUN chown arti:arti ./arti
## set healthcheck
HEALTHCHECK --interval=5m --retries=2 \
            CMD if [ -f /arti/.scanner ]; then echo "arti starting...";  else curl --retry 4 --max-time 30 -xs --socks5-hostname 127.0.0.1:9150 'https://check.torproject.org' | tac | grep -qm1 Congratulations; fi || exit 1
## set workuser
USER arti
## set entrypoint
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
## set cmd
CMD ["./arti", "-c", "arti-bridges.conf", "proxy"]
