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

FROM swift:5.9-jammy

WORKDIR /app/OrchivisteAnalyse
COPY --from=builder /app/OrchivisteAnalyse/.build/release/OrchivisteAnalyse /usr/local/bin/OrchivisteAnalyse

ENV ORCHIVISTE_ANALYSE_HOST=0.0.0.0
ENV ORCHIVISTE_ANALYSE_PORT=28781
EXPOSE 28781

CMD ["OrchivisteAnalyse"]
