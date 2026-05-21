#!/usr/bin/env bash

set -euo pipefail

namespace="${NAMESPACE:-rabbitmq}"
release_name="${RELEASE_NAME:-rabbitmq}"
chart_name="${CHART_NAME:-rabbitmq-cluster}"
fullname="${FULLNAME_OVERRIDE:-${release_name}-${chart_name}}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Missing required command: kubectl" >&2
  exit 1
fi

secret_candidates=()
if [[ -n "${TLS_SECRET_NAME:-}" ]]; then
  secret_candidates+=("$TLS_SECRET_NAME")
else
  secret_candidates+=("${fullname}-tls-local" "${fullname}-tls")
fi

secret_name=""
for candidate in "${secret_candidates[@]}"; do
  if kubectl -n "$namespace" get secret "$candidate" >/dev/null 2>&1; then
    secret_name="$candidate"
    break
  fi
done

if [[ -z "$secret_name" ]]; then
  echo "Could not find a TLS secret in namespace '$namespace'. Checked: ${secret_candidates[*]}" >&2
  exit 1
fi

tmp_ca="$(mktemp)"
trap 'rm -f "$tmp_ca"' EXIT

kubectl -n "$namespace" get secret "$secret_name" -o jsonpath='{.data.ca\.crt}' | base64 -d >"$tmp_ca"

sudo_prefix=()
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Root access is required to install the CA certificate, but sudo is not available." >&2
    exit 1
  fi
  sudo_prefix=(sudo)
fi

if command -v update-ca-certificates >/dev/null 2>&1; then
  destination="/usr/local/share/ca-certificates/${secret_name}.crt"
  "${sudo_prefix[@]}" cp "$tmp_ca" "$destination"
  "${sudo_prefix[@]}" update-ca-certificates >/dev/null
elif command -v update-ca-trust >/dev/null 2>&1; then
  destination="/etc/pki/ca-trust/source/anchors/${secret_name}.crt"
  "${sudo_prefix[@]}" cp "$tmp_ca" "$destination"
  "${sudo_prefix[@]}" update-ca-trust extract >/dev/null
else
  echo "Could not detect a supported Linux CA trust command." >&2
  exit 1
fi

echo "Trusted CA from secret '$secret_name'. Restart your browser before reopening https://localhost:15671."