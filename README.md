# RabbitMQ Cluster

This workspace contains a Helm chart and a kind cluster config for a local RabbitMQ 4.3 management deployment with three StatefulSet replicas.

## What is included

- `charts/rabbitmq-cluster`: Helm chart for a 3-node RabbitMQ cluster based on the `rabbitmq:4.3-management` image
- `kind-config.yaml`: kind cluster config that pins `localhost:5671` and `localhost:15671` to the chart's fixed NodePorts

## Recreate kind with local port mappings

If your current `kind-kind` cluster was created without `kind-config.yaml`, kind cannot add the host port mappings in place. Recreate the cluster instead.

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
kind delete cluster
kind create cluster --config kind-config.yaml
```

If you are not using podman as the kind provider, omit the `KIND_EXPERIMENTAL_PROVIDER` export.

## Install the Helm chart

```bash
helm upgrade --install rabbitmq charts/rabbitmq-cluster \
  --namespace rabbitmq \
  --create-namespace

kubectl rollout status statefulset/rabbitmq-rabbitmq-cluster -n rabbitmq
```

## Local access

- Management UI: `https://localhost:15671`
- AMQPS: `amqps://admin:admin123@localhost:5671`
- Default credentials: `admin` / `admin123`

The chart generates a shared self-signed certificate so all three replicas can answer on the same TLS endpoints. Your browser or client will warn until you trust the generated CA certificate.

This setup does not enable mutual TLS. RabbitMQ still presents a server certificate on `15671` and `5671`, but clients are not required to present their own certificates.

To export the CA certificate:

```bash
kubectl get secret rabbitmq-rabbitmq-cluster-tls -n rabbitmq -o jsonpath='{.data.ca\.crt}' | base64 -d > rabbitmq-ca.crt
```

## Trust the local CA in one command

The repository includes a helper that fetches the CA certificate from Kubernetes and installs it into the Linux trust store.

```bash
./scripts/trust-local-ca.sh
```

The script supports both `update-ca-certificates` and `update-ca-trust`. If your browser still warns afterwards, restart it. Firefox may also need the CA imported into its own certificate store.

## Use an OpenSSL-generated certificate instead

If you want the chart to use a certificate generated outside Helm, create a Kubernetes TLS secret with the provided helper and point the chart at it.

```bash
./scripts/generate-tls-secret.sh

helm upgrade --install rabbitmq charts/rabbitmq-cluster \
  --namespace rabbitmq \
  --create-namespace \
  --set rabbitmq.tls.existingSecret=rabbitmq-rabbitmq-cluster-tls-local

kubectl rollout status statefulset/rabbitmq-rabbitmq-cluster -n rabbitmq
```

The helper uses OpenSSL to generate a local CA and a server certificate signed by that CA. It includes `localhost` and the default service DNS names in the SAN list so the browser and clients can validate the server certificate once the CA is trusted.

If you need different names, override them when generating the secret:

```bash
TLS_SECRET_NAME=my-rabbitmq-tls \
EXTRA_DNS_NAMES=broker.local,rmq.local \
./scripts/generate-tls-secret.sh
```

## Persistence

The default chart settings use `emptyDir` for local development so it works on a fresh kind cluster without relying on a storage class.

To enable persistent volumes instead:

```bash
helm upgrade --install rabbitmq charts/rabbitmq-cluster \
  --namespace rabbitmq \
  --create-namespace \
  --set persistence.enabled=true
```

If your cluster requires a specific storage class, also set `persistence.storageClass`.