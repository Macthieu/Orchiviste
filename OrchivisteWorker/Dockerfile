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

FROM swift:5.9-jammy

WORKDIR /app/OrchivisteWorker
COPY --from=builder /app/OrchivisteWorker/.build/release/OrchivisteWorker /usr/local/bin/OrchivisteWorker

ENV ORCHIVISTE_REDIS_URL=redis://redis:6379

CMD ["OrchivisteWorker"]
