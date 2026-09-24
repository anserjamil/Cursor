#!/usr/bin/env bash
# Run the .NET 9 SDK from a container with the repository mounted at /src.
#
# --network host so the container reaches the agent proxy on 127.0.0.1 (NuGet restore)
# and SQL Server on localhost:1433. The proxy re-terminates TLS, so its CA bundle is
# mounted and pointed at with SSL_CERT_FILE.
set -euo pipefail
exec docker run --rm -i --network host \
  -v /home/user/Cursor:/src \
  -v /home/user/.nuget:/root/.nuget \
  -v /root/.ccr:/ccr:ro \
  -w /src \
  -e HOME=/root \
  -e HTTPS_PROXY="${HTTPS_PROXY:-}" \
  -e SSL_CERT_FILE=/ccr/ca-bundle.crt \
  -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e DOTNET_NOLOGO=1 \
  -e DOTNET_ROLL_FORWARD=LatestMajor \
  -e DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
  mcr.microsoft.com/dotnet/sdk:9.0 "$@"
