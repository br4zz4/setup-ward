#!/usr/bin/env bash
# install.sh — download a ward release, verify its checksum and put it on PATH.
set -euo pipefail

VERSION="${WARD_VERSION:?WARD_VERSION is not set}"
VERSION="${VERSION#v}"
BASE="https://github.com/br4zz4/ward/releases/download/v${VERSION}"

case "$(uname -s)" in
  Linux) OS=linux ;;
  Darwin) OS=darwin ;;
  *) echo "::error::unsupported OS $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) ARCH=amd64 ;;
  arm64 | aarch64) ARCH=arm64 ;;
  *) echo "::error::unsupported architecture $(uname -m)"; exit 1 ;;
esac

ARCHIVE="ward_${OS}_${ARCH}.tar.gz"
DEST="${RUNNER_TEMP:-$(mktemp -d)}/ward-${VERSION}"
mkdir -p "${DEST}"

curl -fsSL --retry 3 --retry-delay 2 -o "${DEST}/${ARCHIVE}" "${BASE}/${ARCHIVE}"
curl -fsSL --retry 3 --retry-delay 2 -o "${DEST}/checksums.txt" "${BASE}/checksums.txt"

EXPECTED="$(grep " ${ARCHIVE}\$" "${DEST}/checksums.txt" | awk '{print $1}')"
if [ -z "${EXPECTED}" ]; then
  echo "::error::${ARCHIVE} is not listed in the checksums of ward v${VERSION}"
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "${DEST}/${ARCHIVE}" | awk '{print $1}')"
else
  ACTUAL="$(shasum -a 256 "${DEST}/${ARCHIVE}" | awk '{print $1}')"
fi
if [ "${EXPECTED}" != "${ACTUAL}" ]; then
  echo "::error::checksum mismatch for ${ARCHIVE}"
  exit 1
fi

tar -xzf "${DEST}/${ARCHIVE}" -C "${DEST}" ward
chmod +x "${DEST}/ward"
echo "${DEST}" >> "${GITHUB_PATH:?GITHUB_PATH is not set}"
"${DEST}/ward" version
