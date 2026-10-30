# VigiRoadTrafficAggregator — image portable (Cloud Run, VPS, Fly.io…).
# Construction depuis la racine du dépôt :
#   docker build -f server/Dockerfile -t vigiroad-traffic .
FROM dart:stable AS build
WORKDIR /app
COPY packages/vigiroad_traffic /app/packages/vigiroad_traffic
COPY server/pubspec.yaml /app/server/
WORKDIR /app/server
RUN dart pub get
COPY server /app/server
RUN dart pub get --offline && dart compile exe bin/server.dart -o /app/bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
# Certificats racine pour les appels HTTPS vers les sources.
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
EXPOSE 8080
USER 65534
ENTRYPOINT ["/app/bin/server"]
