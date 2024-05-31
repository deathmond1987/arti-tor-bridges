FROM alpine:latest as build
ENV GIT_SSL_NO_VERIFY=true
RUN apk update --no-cache
RUN apk add cargo \
            git \
            pkgconf \
            openssl-dev \
            sqlite-dev --no-cache
RUN git clone https://gitlab.torproject.org/tpo/core/arti.git
WORKDIR arti
RUN cargo build -p arti --locked --release
RUN cd ./examples/gsoc2023/connection-checker && cargo build -p connection-checker --locked --release

FROM alpine:latest AS bridge-builder
ARG APP_DIR=torparse
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

FROM alpine:latest as release
RUN apk update --no-cache && apk add libgcc sqlite-libs tini
RUN addgroup -S arti && adduser -S arti -G arti
RUN mkdir /arti
RUN chown -R arti:arti /arti
COPY --from=build /arti/target/release/arti /arti/arti
COPY --from=build /arti/target/release/connection-checker /arti/connection-checker
COPY --from=build /arti/crates/arti/src/arti-example-config.toml /arti/conf.toml
COPY --from=bridge-builder --chmod=755 /tor-relay-scanner/dist/__main__ /arti/tor-relay-scanner
COPY --chmod=755 ./entrypoint.sh /
WORKDIR /arti
RUN chmod 755 ./*
RUN chown arti:arti ./arti
USER arti
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
CMD ["./arti", "-c", "arti-bridges.conf", "proxy"]
