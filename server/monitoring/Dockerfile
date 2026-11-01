# Agent de supervision VIGIROAD (construction depuis la racine du dépôt) :
#   docker build -f server/monitoring/Dockerfile -t vigiroad-agent .
FROM dart:stable AS build
WORKDIR /app/server/monitoring
COPY server/monitoring/pubspec.yaml ./
RUN dart pub get
COPY server/monitoring ./
RUN mkdir -p /app/bin && dart pub get --offline && dart compile exe bin/agent.dart -o /app/bin/agent

# Image Debian minimale : `df` est nécessaire pour l'espace disque de l'hôte.
FROM debian:bookworm-slim
COPY --from=build /app/bin/agent /app/bin/agent
EXPOSE 9100
ENTRYPOINT ["/app/bin/agent"]
