#!/usr/bin/env bash
set -euo pipefail

VERSION="3.15.2"
ARCHIVE_NAME="python-${VERSION}-iOS-XCframework.tar.gz"
DOWNLOAD_URL="https://www.python.org/ftp/python/${VERSION}/${ARCHIVE_NAME}"
EXPECTED_SHA256="0f9fc7f61ceb8278a69fc7ec6089aad81789a96fa42f31cfe6d2f5f860d20a62"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${ROOT_DIR}/Python.xcframework"
CACHE_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/personalagent-cpython-${VERSION}"
ARCHIVE="${CACHE_ROOT}/${ARCHIVE_NAME}"
EXTRACTED="${CACHE_ROOT}/extracted"

mkdir -p "${CACHE_ROOT}" "${EXTRACTED}"

if [[ ! -f "${ARCHIVE}" ]]; then
    curl --fail --location --retry 3 --retry-all-errors \
        --output "${ARCHIVE}" "${DOWNLOAD_URL}"
fi

echo "${EXPECTED_SHA256}  ${ARCHIVE}" | shasum -a 256 -c -

rm -rf "${EXTRACTED}"
mkdir -p "${EXTRACTED}"
tar -xzf "${ARCHIVE}" -C "${EXTRACTED}"

FRAMEWORK_SOURCE="$(find "${EXTRACTED}" -type d -name "Python.xcframework" -print -quit)"
if [[ -z "${FRAMEWORK_SOURCE}" ]]; then
    echo "CPython ${VERSION} archive did not contain Python.xcframework" >&2
    exit 1
fi

if [[ ! -f "${FRAMEWORK_SOURCE}/build/utils.sh" ]]; then
    echo "CPython ${VERSION} XCFramework is missing the upstream build/utils.sh helper" >&2
    exit 1
fi

rm -rf "${DESTINATION}"
ditto "${FRAMEWORK_SOURCE}" "${DESTINATION}"

test -f "${DESTINATION}/build/utils.sh"
echo "Prepared official CPython ${VERSION} iOS XCFramework at ${DESTINATION}"
