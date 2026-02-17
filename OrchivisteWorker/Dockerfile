FROM swift:5.9-jammy AS builder

WORKDIR /app

# 1) Copy only manifests first to maximize dependency-cache reuse.
COPY OrchivisteSharedKit/Package.swift ./OrchivisteSharedKit/Package.swift
COPY OrchivisteWorker/Package.swift OrchivisteWorker/Package.resolved ./OrchivisteWorker/

WORKDIR /app/OrchivisteWorker
RUN swift package resolve
RUN cp Package.resolved /tmp/OrchivisteWorker.Package.resolved

# 2) Copy full sources after dependency resolution.
WORKDIR /app
COPY OrchivisteSharedKit ./OrchivisteSharedKit
COPY OrchivisteWorker ./OrchivisteWorker

WORKDIR /app/OrchivisteWorker
RUN cp /tmp/OrchivisteWorker.Package.resolved Package.resolved
RUN swift build -c release --product OrchivisteWorker

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

WORKDIR /app/OrchivisteWorker

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4 \
    libstdc++6 \
    libxml2 \
    tzdata \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/lib/swift/linux /usr/lib/swift/linux
COPY --from=builder /app/OrchivisteWorker/.build/release/OrchivisteWorker /usr/local/bin/OrchivisteWorker

ENV LD_LIBRARY_PATH=/usr/lib/swift/linux
ENV ORCHIVISTE_REDIS_URL=redis://redis:6379

CMD ["OrchivisteWorker"]
