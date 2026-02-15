FROM swift:5.9-jammy AS builder

WORKDIR /app
COPY OrchivisteSharedKit ./OrchivisteSharedKit
COPY OrchivisteWorker ./OrchivisteWorker

WORKDIR /app/OrchivisteWorker
RUN swift build -c release --product OrchivisteWorker

FROM swift:5.9-jammy

WORKDIR /app/OrchivisteWorker
COPY --from=builder /app/OrchivisteWorker/.build/release/OrchivisteWorker /usr/local/bin/OrchivisteWorker

ENV ORCHIVISTE_REDIS_URL=redis://redis:6379

CMD ["OrchivisteWorker"]
