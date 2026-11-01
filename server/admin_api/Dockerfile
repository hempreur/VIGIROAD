# API d'administration VIGIROAD (construction depuis la racine du dépôt) :
#   docker build -f server/admin_api/Dockerfile -t vigiroad-admin-api .
FROM dart:stable AS build
WORKDIR /app/server/admin_api
COPY server/admin_api/pubspec.yaml ./
RUN dart pub get
COPY server/admin_api ./
RUN mkdir -p /app/bin && dart pub get --offline && dart compile exe bin/admin_api.dart -o /app/bin/admin_api

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/admin_api /app/bin/admin_api
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY server/database/migrations /app/database/migrations
EXPOSE 8081
USER 65534
ENTRYPOINT ["/app/bin/admin_api"]
