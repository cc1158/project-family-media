#!/bin/sh
set -eu

external_binary="/opt/family-media/bin/family-media-server"
bundled_binary="/app/family-media-server"
runtime_binary="/tmp/family-media-server"

if [ -e "${external_binary}" ] || [ -L "${external_binary}" ]; then
    if [ ! -f "${external_binary}" ]; then
        echo "External server path exists but is not a regular file: ${external_binary}" >&2
        exit 1
    fi
    if [ ! -r "${external_binary}" ]; then
        echo "External server is not readable: ${external_binary}" >&2
        exit 1
    fi

    echo "Starting external family media server: ${external_binary}"
    cp "${external_binary}" "${runtime_binary}"
    chmod 700 "${runtime_binary}"
    export FAMILY_MEDIA_BINARY_SOURCE="external"
    exec "${runtime_binary}" "$@"
fi

echo "External server not found; starting bundled family media server"
export FAMILY_MEDIA_BINARY_SOURCE="bundled"
exec "${bundled_binary}" "$@"
