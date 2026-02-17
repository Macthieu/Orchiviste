FROM swift:5.9-jammy AS builder

WORKDIR /app

# 1) Copy only manifests first to maximize dependency-cache reuse.
COPY OrchivisteSharedKit/Package.swift ./OrchivisteSharedKit/Package.swift
COPY OrchivisteAPI/Package.swift OrchivisteAPI/Package.resolved ./OrchivisteAPI/

WORKDIR /app/OrchivisteAPI
RUN swift package resolve
RUN cp Package.resolved /tmp/OrchivisteAPI.Package.resolved

# 2) Copy full sources after dependency resolution.
WORKDIR /app
COPY OrchivisteSharedKit ./OrchivisteSharedKit
COPY OrchivisteAPI ./OrchivisteAPI

WORKDIR /app/OrchivisteAPI
RUN cp /tmp/OrchivisteAPI.Package.resolved Package.resolved
RUN swift build -c release --disable-automatic-resolution --product OrchivisteAPI

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

WORKDIR /app/OrchivisteAPI

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4 \
    libsqlite3-0 \
    libstdc++6 \
    libxml2 \
    tzdata \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/lib/swift/linux /usr/lib/swift/linux

COPY --from=builder /app/OrchivisteAPI/.build/release/OrchivisteAPI /usr/local/bin/OrchivisteAPI
COPY --from=builder /app/OrchivisteAPI/Resources ./Resources
COPY --from=builder /app/OrchivisteAPI/configs ./configs

ENV LD_LIBRARY_PATH=/usr/lib/swift/linux

ENV ORCHIVISTE_API_PORT=28780
ENV ORCHIVISTE_API_HOST=0.0.0.0
ENV ORCHIVISTE_ANALYSE_URL=http://analyse:28781
ENV ORCHIVISTE_SQLITE_PATH=/data/orchiviste.sqlite
ENV ORCHIVISTE_AUTO_MIGRATE=1

EXPOSE 28780
VOLUME ["/data"]

CMD ["OrchivisteAPI"]
