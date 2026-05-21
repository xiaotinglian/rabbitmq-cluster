#!/usr/bin/env bash

set -euo pipefail

namespace="${NAMESPACE:-rabbitmq}"
release_name="${RELEASE_NAME:-rabbitmq}"
chart_name="${CHART_NAME:-rabbitmq-cluster}"
cluster_domain="${CLUSTER_DOMAIN:-cluster.local}"
fullname="${FULLNAME_OVERRIDE:-${release_name}-${chart_name}}"
headless_service="${HEADLESS_SERVICE_NAME:-${fullname}-headless}"
secret_name="${TLS_SECRET_NAME:-${fullname}-tls-local}"
ca_common_name="${CA_COMMON_NAME:-${fullname} Local CA}"
server_common_name="${SERVER_COMMON_NAME:-localhost}"
ca_validity_days="${CA_VALIDITY_DAYS:-3650}"
cert_validity_days="${CERT_VALIDITY_DAYS:-397}"

for required_command in kubectl openssl; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Missing required command: $required_command" >&2
    exit 1
  fi
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

dns_names=(
  "localhost"
  "$fullname"
  "$fullname.$namespace"
  "$fullname.$namespace.svc"
  "$fullname.$namespace.svc.$cluster_domain"
  "$headless_service"
  "$headless_service.$namespace"
  "$headless_service.$namespace.svc"
  "$headless_service.$namespace.svc.$cluster_domain"
)

if [[ -n "${EXTRA_DNS_NAMES:-}" ]]; then
  IFS=',' read -r -a extra_dns_names <<<"$EXTRA_DNS_NAMES"
  dns_names+=("${extra_dns_names[@]}")
fi

ip_addresses=("127.0.0.1")

if [[ -n "${EXTRA_IP_ADDRESSES:-}" ]]; then
  IFS=',' read -r -a extra_ip_addresses <<<"$EXTRA_IP_ADDRESSES"
  ip_addresses+=("${extra_ip_addresses[@]}")
fi

cat >"$tmp_dir/ca.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_ca

[ dn ]
CN = $ca_common_name

[ v3_ca ]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

cat >"$tmp_dir/server.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[ dn ]
CN = $server_common_name

[ v3_req ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
EOF

dns_index=1
for dns_name in "${dns_names[@]}"; do
  if [[ -n "$dns_name" ]]; then
    echo "DNS.$dns_index = $dns_name" >>"$tmp_dir/server.cnf"
    dns_index=$((dns_index + 1))
  fi
done

ip_index=1
for ip_address in "${ip_addresses[@]}"; do
  if [[ -n "$ip_address" ]]; then
    echo "IP.$ip_index = $ip_address" >>"$tmp_dir/server.cnf"
    ip_index=$((ip_index + 1))
  fi
done

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$tmp_dir/ca.key" \
  -out "$tmp_dir/ca.crt" \
  -days "$ca_validity_days" \
  -config "$tmp_dir/ca.cnf" >/dev/null 2>&1

openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$tmp_dir/tls.key" \
  -out "$tmp_dir/tls.csr" \
  -config "$tmp_dir/server.cnf" >/dev/null 2>&1

openssl x509 -req \
  -in "$tmp_dir/tls.csr" \
  -CA "$tmp_dir/ca.crt" \
  -CAkey "$tmp_dir/ca.key" \
  -CAcreateserial \
  -out "$tmp_dir/tls.crt" \
  -days "$cert_validity_days" \
  -sha256 \
  -extensions v3_req \
  -extfile "$tmp_dir/server.cnf" >/dev/null 2>&1

kubectl get namespace "$namespace" >/dev/null 2>&1 || kubectl create namespace "$namespace" >/dev/null

kubectl -n "$namespace" create secret generic "$secret_name" \
  --from-file=ca.crt="$tmp_dir/ca.crt" \
  --from-file=tls.crt="$tmp_dir/tls.crt" \
  --from-file=tls.key="$tmp_dir/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Created or updated TLS secret '$secret_name' in namespace '$namespace'."
echo
echo "Use it with:"
echo "  helm upgrade --install $release_name charts/$chart_name --namespace $namespace --create-namespace --set rabbitmq.tls.existingSecret=$secret_name"