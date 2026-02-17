FROM swift:5.9-jammy AS builder

WORKDIR /app

# 1) Copy only manifests first to maximize dependency-cache reuse.
COPY OrchivisteAnalyse/Package.swift OrchivisteAnalyse/Package.resolved ./OrchivisteAnalyse/

WORKDIR /app/OrchivisteAnalyse
RUN swift package resolve
RUN cp Package.resolved /tmp/OrchivisteAnalyse.Package.resolved

# 2) Copy full sources after dependency resolution.
WORKDIR /app
COPY OrchivisteAnalyse ./OrchivisteAnalyse

WORKDIR /app/OrchivisteAnalyse
RUN cp /tmp/OrchivisteAnalyse.Package.resolved Package.resolved
RUN swift build -c release --disable-automatic-resolution --product OrchivisteAnalyse

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

WORKDIR /app/OrchivisteAnalyse

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4 \
    libstdc++6 \
    libxml2 \
    tzdata \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/lib/swift/linux /usr/lib/swift/linux
COPY --from=builder /app/OrchivisteAnalyse/.build/release/OrchivisteAnalyse /usr/local/bin/OrchivisteAnalyse

ENV LD_LIBRARY_PATH=/usr/lib/swift/linux
ENV ORCHIVISTE_ANALYSE_HOST=0.0.0.0
ENV ORCHIVISTE_ANALYSE_PORT=28781
EXPOSE 28781

CMD ["OrchivisteAnalyse"]
