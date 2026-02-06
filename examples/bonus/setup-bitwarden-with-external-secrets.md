# Using Bitwarden Secrets Manager with External Secrets Operator (ESO)

Why? Because if you don't have access to Secrets Manager or don't want to pay for it, you can use Bitwarden on personal use plan for free and still manage secrets in Kubernetes. And Bitwarden Secrets Manager working well with External Secrets Operator.

This guide explains how to integrate **Bitwarden Secrets Manager** with the **Kubernetes External Secrets Operator (ESO)** using the **official provider**, including:

* Bitwarden Machine Accounts
* Bitwarden SDK Server (required)
* cert-manager TLS
* Working `ClusterSecretStore` and `ExternalSecret`

---

## Architecture Overview

```
Bitwarden Secrets Manager
        │
        │ (Machine Account Access Token)
        ▼
External Secrets Operator
        │
        │ (HTTPS)
        ▼
Bitwarden SDK Server (in-cluster)
        │
        ▼
Kubernetes Secret
        │
        ▼
Application Pod
```

---

## Prerequisites

* Kubernetes ≥ 1.21
* External Secrets Operator (Helm)
* cert-manager installed
* Bitwarden **Secrets Manager** (not Password Vault)
* Machine Account with access to:

  * Organization
  * Project containing secrets
* Cluster allows:

  * `readOnlyRootFilesystem`
  * `allowPrivilegeEscalation=false`
  * resource requests/limits (Kyverno)

---

## 1. Install External Secrets Operator with Bitwarden SDK Server

The Bitwarden Secrets Manager provider **requires** the Bitwarden SDK Server.

If you are using the kubara general distro setup, you need to enable the sdk under `customer-service-catalog/helm/pe-gitops/external-secrets/values.yaml`.

```yaml
clusterSecretStores: {}
namespace:
  labels:
    project-name: "pe-gitops"
    stage: "prod"
external-secrets:
  serviceMonitor:
    enabled: true
    additionalLabels:
      monitoring.instance: "pe-gitops-prod"
  bitwarden-sdk-server:
    enabled: true #HERE
```
It should be running out of the box, if the argo cd instance is running and working.
---

## 2. Create TLS Certificates with cert-manager

The SDK Server **must use HTTPS**.

### Issuer + Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: bitwarden-sdk-selfsigned
  namespace: external-secrets
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: bitwarden-sdk-server-cert
  namespace: external-secrets
spec:
  secretName: bitwarden-tls-certs
  duration: 2160h
  renewBefore: 360h
  commonName: bitwarden-sdk-server.external-secrets.svc
  dnsNames:
    - bitwarden-sdk-server
    - bitwarden-sdk-server.external-secrets
    - bitwarden-sdk-server.external-secrets.svc
    - bitwarden-sdk-server.external-secrets.svc.cluster.local
  issuerRef:
    name: bitwarden-sdk-selfsigned
```

Apply:

```bash
kubectl apply -f bitwarden-sdk-tls.yaml
```

Verify:

```bash
kubectl -n external-secrets get secret bitwarden-tls-certs
```

---

## 3. Create Bitwarden Machine Account Token Secret

From Bitwarden UI:

* Secrets Manager → Machine Accounts
* Create Access Token

Store it in Kubernetes:

```bash
kubectl -n external-secrets create secret generic bitwarden-access-token \
  --from-literal=token="<BITWARDEN_MACHINE_ACCOUNT_TOKEN>"
```

---

## 4. Create ClusterSecretStore (Correct & Hardened)

**Important points:**

* `ClusterSecretStore` requires explicit `credentials.namespace`
* Use **EU endpoints** if your tenant is EU
* Use `caProvider` instead of inline `caBundle` (more robust)

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: bitwarden-eu-demo
spec:
  provider:
    bitwardensecretsmanager:
      apiURL: "https://vault.bitwarden.eu/api"
      identityURL: "https://vault.bitwarden.eu/identity"
      organizationID: "<ORG_ID>"
      projectID: "<PROJECT_ID>"

      auth:
        secretRef:
          credentials:
            name: bitwarden-access-token
            namespace: external-secrets
            key: token

      bitwardenServerSDKURL: "https://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998"

      caProvider:
        type: Secret
        name: bitwarden-tls-certs
        namespace: external-secrets
        key: ca.crt
```

Apply:

```bash
kubectl apply -f clustersecretstore-bitwarden.yaml
```

Verify:

```bash
kubectl describe clustersecretstore bitwarden-eu-demo
```

Status must be:

```
Type: Ready
Status: True
```

---

## 5. Create ExternalSecret

You will first create a secret in Bitwarden Secrets Manager, e.g., `db-password` with value `WHATEVER`.

### Recommended: Reference Secret by UUID, but you can also use Name like:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-db-by-name
  namespace: external-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-com-demo
    kind: ClusterSecretStore
  target:
    name: app-db-by-name
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: "db-password"
```

Apply:

```bash
kubectl apply -f externalsecret.yaml
```

Verify:

```bash
kubectl get secret app-db
kubectl describe externalsecret app-db
```

---

## 6. Use the Secret in a Deployment - JUST AN EXAMPLE, NO NEED!

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-db
        key: DB_PASSWORD
```

## 7. Connect a vCluster or another Cluster - Kubara General Distro

You will first need to create a secret in your Bitwarden Secrets Manager for the vCluster, e.g., `vcluster-project-z` with value `KUBECONFIG`.

Then, add the following to your Argo CD `values.yaml` under `cluster:` section:

`customer-service-catalog/helm/pe-gitops/argo-cd/values.yaml`
```yaml:
  cluster:
    - additionalLabels:
        flux-operator: "enabled"
      name: vcluster-project-z-new
      project: pe-gitops-prod
      remoteRef:
        remoteKey: vcluster-project-z
        remoteKeyProperty: vcluster-project-z
      secretStoreRef:
        kind: ClusterSecretStore
        name: bitwarden-com-demo
```

Argo CD will handle the rest by creating an `ExternalSecret`. Then External Secrets Operator will create the secret and Argo CD will use it to connect to the vCluster and deploy addons or applications based on the labels.

Otherwise, you will need to create a  `ExternalSecret` manually similar to the Secrets already existing External Secrets in the argocd namespace.

---

## Common Failure Modes & Fixes

| Error                            | Cause                             | Fix                      |
| -------------------------------- | --------------------------------- | ------------------------ |
| `failed to append caBundle`      | Invalid inline CA                 | Use `caProvider`         |
| `empty namespace may not be set` | Missing `credentials.namespace`   | Set explicitly           |
| SDK pod Pending                  | Missing TLS secret                | cert-manager Certificate |
| Kyverno violations               | Missing securityContext/resources | Helm values              |
| 401 / auth errors                | Wrong region (.com vs .eu)        | Use correct endpoints    |

---

## Operational Checks

```bash
kubectl -n external-secrets get pods -l app.kubernetes.io/name=bitwarden-sdk-server
kubectl -n external-secrets logs deploy/bitwarden-sdk-server
kubectl describe clustersecretstore bitwarden-eu-demo
```

---

## References

* External Secrets Operator – Bitwarden Secrets Manager
  [https://external-secrets.io/latest/provider/bitwarden-secrets-manager/](https://external-secrets.io/latest/provider/bitwarden-secrets-manager/)

* External Secrets Helm Chart
  [https://github.com/external-secrets/external-secrets/tree/main/charts/external-secrets](https://github.com/external-secrets/external-secrets/tree/main/charts/external-secrets)

* Bitwarden Secrets Manager Docs
  [https://bitwarden.com/help/secrets-manager/](https://bitwarden.com/help/secrets-manager/)

* cert-manager Documentation
  [https://cert-manager.io/docs/](https://cert-manager.io/docs/)
