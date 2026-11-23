ARG IMAGE_BASE_TAG=3.12-slim-bookworm

FROM "python:${IMAGE_BASE_TAG}" AS hat-syslog-base
RUN apt-get update

FROM hat-syslog-base AS hat-syslog-npm
ENV DEBIAN_FRONTEND='noninteractive'
WORKDIR /root
RUN apt-get install -y nodejs npm

FROM hat-syslog-npm AS hat-syslog-build
ENV PIP_ROOT_USER_ACTION='ignore'
WORKDIR /root
RUN pip install --upgrade pip
WORKDIR /hat-syslog
COPY . .
SHELL ["/usr/bin/env", "bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c"]
RUN \
    build_vendored() ( \
        local dir; \
\
        mkdir -p "${1}"; \
        PIP_FIND_LINKS="$(realpath "${1}")"; \
        export PIP_FIND_LINKS; \
        shift; \
\
        for dir in "${@}"; \
        do \
        pushd "${dir}" || continue; \
        pip wheel --wheel-dir "${PIP_FIND_LINKS}" . || :; \
        popd; \
        done; \
    ); \
    build_vendored ./.vendor-dist vendor/hat-{aio,util,json,juggler}; \
    pip install --find-links ./.vendor-dist --group dev . && \
    doit clean_all && \
    doit

FROM hat-syslog-base AS hat-syslog-run
WORKDIR /root
RUN --mount=type=tmpfs,target=/stages \
    --mount=type=bind,source=/hat-syslog/build,target=/stages/build,from=hat-syslog-build \
    --mount=type=bind,source=/hat-syslog/.vendor-dist,target=/stages/build-dist,from=hat-syslog-build \
    pip install --root-user-action=ignore /stages/build/py/*.whl /stages/build-dist/*.whl

WORKDIR /hat-syslog
VOLUME /hat-syslog
EXPOSE 6514/tcp \
       6514/udp \
       23020/tcp

ENTRYPOINT ["/usr/local/bin/hat-syslog-server", "--db-path", "/hat-syslog/syslog.db"]
