FROM rocker/r-base:latest

# Minimal image for the docker-spawn sandbox backend.  The UDS socket is
# bind-mounted from the host at runtime (see sandbox-docker-spawn.R) so no
# additional setup is needed beyond a working R installation.
#
# Build:
#   docker build -t securer/r-sandbox:latest -f inst/docker/Dockerfile .
# Use:
#   SECURER_SANDBOX_MODE=docker-spawn \
#     SECURER_DOCKER_IMAGE=securer/r-sandbox:latest \
#     Rscript -e 'securer::execute_r("1 + 1")'

RUN install2.r --error --skipinstalled \
      callr \
      jsonlite \
      processx \
      R6 \
      S7 \
    && rm -rf /tmp/downloaded_packages /tmp/*.rds

WORKDIR /work
