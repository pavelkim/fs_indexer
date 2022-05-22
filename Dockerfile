FROM alpine:3.15 as builder

ARG BUILD_VERSION=0.0.0
ARG PROGNAME=fs_indexer

WORKDIR /src
ADD . /src

RUN apk add bash make uuidgen
RUN make build


FROM alpine:3.15
RUN apk add bash findutils

ARG BUILD_VERSION=0.0.0
ARG PROGNAME=fs_indexer

ENV SCAN_ROOT="/scan"

WORKDIR /
COPY --from=builder "/src/${PROGNAME}-${BUILD_VERSION}/fs_indexer.sh" fs_indexer.sh

ENTRYPOINT ["./fs_indexer.sh"]
