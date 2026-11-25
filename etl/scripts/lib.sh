# Sourced by the scripts in etl/scripts. Defines `sqlib`, which runs the sqlib
# command line: the command in $SQLIB if it is set, or else the sqlib-cli
# Docker image. The image mounts the repository at its own path, so paths
# relative to the current directory work in both.
# Build the image from the sqlib repository:
#   docker build -f examples/docker/cli-minimal/Dockerfile -t sqlib-cli .
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

sqlib() {
  if [ -n "${SQLIB:-}" ]; then
    # shellcheck disable=SC2086
    $SQLIB "$@"
  else
    mkdir -p "$root/etl/.cache/duckdb"
    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
      -v "$root:$root" -v "$root/etl/.cache/duckdb:/tmp/.duckdb" -w "$PWD" \
      "${SQLIB_IMAGE:-sqlib-cli}" "$@"
  fi
}
