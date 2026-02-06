# Lets' get started! Hands-on!

*__Note:__ hopefully you checked the [Prerequisites](PREREQUISITES.md) before starting the bootstrap!*

After you fork or clone this repository, you should replace:

- Git repository URLs from `git@github.com:InternalDeveloperPlatform/pe-gitops-course.git` to your own repository URL
- Domain names from `https://pe-gitops-0.stackit.run/` to your own domain


Hiarchical overview of the setup:

```
┌──────────────────────────┐
│  Git Repository (Fork)   │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│        Argo CD           │  ← GitOps Engine (self-managed)
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│  Platform Components     │
│  (Kubara General Distro) │
│                          │
│  - External Secrets      │
│  - External DNS          │
│  - cert-manager          │
│  - Gateway API / Envoy   │
│  - Monitoring, Policy…   │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│ Secrets Manager / DNS /  │
│ Cloud Provider Services  │
└──────────────────────────┘
```

Let's get started!

## Step 1: Apply required CRDs (cluster-wide)

CRDs are applied **separately** to avoid:

* Helm upgrade issues
* annotation size limits
* GitOps drift

```bash
kubectl apply --server-side --force-conflicts \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml

kubectl apply --server-side --force-conflicts \
  -f managed-service-catalog/helm/crds/external-secrets/

kubectl apply --server-side --force-conflicts \
  -f managed-service-catalog/helm/crds/kube-prometheus-stack/crds/
```

---

## Step 2: Bootstrap Argo CD

### Render and apply Argo CD manifests

```bash
helm dependency build managed-service-catalog/helm/argo-cd

helm template argocd managed-service-catalog/helm/argo-cd \
  --values customer-service-catalog/helm/pe-gitops/argo-cd/values.yaml \
  --namespace argocd \
  --create-namespace \
| kubectl apply -f -
```

At this point:

* Argo CD is installed
* It will later manage itself via GitOps and also the CRDs (without kubernetes gateway-api)

---

## Step 3: Repository access (bootstrap secret)

**Only required if your fork or clone is private.**
**Do not store this secret in Git.**

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: https-init-repo-access
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  name: https-init-repo-access
  project: pe-gitops-prod
  url: https://github.com/<your-org>/<your-repo>.git
  username: <github-username>
  password: <github-pat>
  enableLfs: "true"
  forceHttpBasicAuth: "true"
  insecure: "false"
EOF
```

check if argo started doing its job by applying all enabled service.

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open your browser at `https://localhost:8080` and login with:

* Username: `admin`
* Password: initial admin password from:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```
*__Note:__ If will take about 5 - 10 minutes until everything is running. You are deploying a full platform after all :)*

If you still see applications in a Degraded state, try refreshing or syncing them manually in the Argo CD UI.

Some applications may remain OutOfSync even after synchronization. This can be expected, especially during the initial bootstrap phase or when resources are mutated by controllers or admission policies.

If the affected applications are otherwise healthy and functioning as expected, you can safely configure Argo CD to ignore specific differences for those resources to avoid persistent noise.

---

## Step 4: Connect External Secrets Operator to a Secrets Manager

You will need to connect External Secrets Operator to your Secrets Manager / Vault by creating:

- a Kubernetes Secret with credentials
- a ClusterSecretStore resource

### 4.1 Credentials Secret

Example for STACKIT Secrets Manager / Vault.

Secret:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: stackit-secrets-manager-cred
  namespace: external-secrets
type: Opaque
stringData:
  username: "<vault-username>"
  password: "<vault-password>"
EOF
```

### 4.2 ClusterSecretStore

```bash
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: pe-gitops-prod
spec:
  provider:
    vault:
      server: https://prod.sm.eu01.stackit.cloud
      path: <path-id>
      version: v2
      auth:
        userPass:
          path: userpass
          username: "<vault-username>"
          secretRef:
            name: stackit-secrets-manager-cred
            namespace: external-secrets
            key: password
EOF
```

After this step:

* External Secrets Operator can fetch secrets
* Plain secrets are no longer needed. Please remove them after bootstrap, store them only in the Secrets Manager and let External Secrets Operator sync them.

---

## Step 5: External DNS

ExternalDNS is preconfigured via Helm values.

You must adapt if you forgot to replace domain names with your own domain:

```yaml
external-dns:
  txtOwnerId: pe-gitops-prod
  domainFilters:
    - your-domain.example
```
And you will need to create a secret with your DNS provider credentials. Here is an example for STACKIT DNS:

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
stringData:
  PROJECT_ID: "38867e9e..."
  SA_KEY_JSON: "{"active":true,"createdAt":"2026-01-10T17:05:14.082Z","credentials":{"aud":"https://stackit-service-ac..."
kind: Secret
metadata:
  name: external-dns-webhook
  namespace: external-dns
type: Opaque
EOF
```

And also overwrite values for providers if you are not using STACKIT DNS, but e.g.:

* AWS Route53
* Cloudflare
* Google Cloud DNS
* etc.

---

## Step 6: Gateway API & Envoy Gateway

This setup uses:

* **Gateway API**
* **Envoy Gateway**
* **cert-manager**
* Managed cloud load balancers

Ingress NGINX is **not used** and is expected to be deprecated long-term, Gateway API adoption is increasing and this is the recommended path forward.

Update only need if you forgot to replace domain names with your own domain:

```yaml
gatewaySystem:
  gateway:
    name: shared-gw
    clusterIssuer: letsencrypt-prod-gateway
    wildcardSecretName: wildcard-pe-gitops-tls
    mainHostname: your-domain.example
```

---

## Step 7: Grafana admin password

We are not using a default password for Grafana.
Like I mentioned multiple times before, this general distro enforces a lot of best practices out of the box.
Even I removed some of them to make it easier for you to bootstrap and get started :)

Grafana expect a secret named `grafana-admin-credentials` in the `kube-rpmetheus-stack` namespace with keys `username` and `password`.
If you are using a Secrets manager, then you will just un-comment the relevant section in the Helm values file here:

`customer-service-catalog/helm/pe-gitops/kube-prometheus-stack/values.yaml`

```yaml
externalSecrets:
  secretStoreRef:
    kind: ClusterSecretStore
    name: "pe-gitops-prod"
  secrets:
    - target: grafana-admin-credentials
      dataFrom:
        - remoteKey: grafana_credentials
```

Otherwise, you can create the secret manually like this:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
stringData:
  admin-password: "Vz>*9]%Z]XY82376"
  admin-user: "RIWKBbW6"
kind: Secret
metadata:
  name: grafana-admin-credentials
  namespace: kube-prometheus-stack

type: Opaque
EOF
```

---

## Optional: Enable Single Sign-On (SSO)

To provide a consistent authentication experience across the platform, you can enable **Single Sign-On (SSO)** for user-facing components such as:

* **Argo CD**
* **Grafana**

SSO is **not required** for the platform to function, but it is **strongly recommended** for:

* multi-user environments
* production setups
* auditability and access control
* avoiding shared local accounts


### Supported Identity Providers (IdPs)

This setup supports multiple OAuth/OIDC-compatible identity providers, including:

* **GitHub**
* **Microsoft Entra ID (Azure AD)**
* **Auth0**
* **Google Cloud Identity**
* **Okta**
* **Forgejo / Gitea**
* **and more**

The concrete configuration depends on the chosen provider.
Below, GitHub is used as the **reference example**, as it is commonly available and easy to set up.

To enable full Single Sign-On experience, you’ll need:

A GitHub Organization and at least one Team
Create three GitHub OAuth Apps under your org's Developer Settings → OAuth Apps:

1. Argo CD SSO

   - Homepage URL: https://cp.your-domain.stackit.run/argocd
   - Callback URL: https://cp.your-domain.stackit.run/argocd/api/dex/callback

2. Grafana SSO
   - Homepage URL: https://cp.your-domain.stackit.run/grafana
   - Callback URL: https://cp.your-domain.stackit.run/grafana/login/github

You only need to store the **Client ID** and **Client Secret** of each OAuth application in your **Secrets Manager** and configure the corresponding Helm values to reference those secrets.

If you are using **STACKIT Secrets Manager** or **HashiCorp Vault**, the required configuration is **already present but commented out** in the Helm values provided by this repository.

To enable it, search for `oauth2` in the `customer-service-catalog` directory and **uncomment the relevant sections** in the Argo CD and Grafana values files, then adjust the referenced secret keys if necessary.

I put your 2 configuration that works out of the box for GitHub and GitLab under the `customer-service-catalog/helm/pe-gitops/argo-cd/values.yaml` file. For GitHub you should take a look how to setup OAuth App in GitHub Developer Settings. And for GitLab you should take a look how to setup OAuth Application under Group Settings -> Applications -> New application.

---

## Optional: Disable in-cluster services (local setups)

For KinD or minimal clusters, you may want only:

* Argo CD
* Argo Rollouts
* External Secrets Operator
* Cert-Manager

Disable others via labels in:


`customer-service-catalog/helm/pe-gitops/argo-cd/values.yaml`

```yaml
# customer-service-catalog/helm/pe-gitops/argo-cd/values.yaml

inClusterSecretLabels:
  # Core control-plane components (recommended to keep enabled)
  argocd: "enabled"
  argo-rollouts: "enabled"
  external-secrets: "enabled"
  cert-manager: "enabled"

  # Optional / platform services (disable for local or minimal setups)
  external-dns: "disabled"
  kube-prometheus-stack: "disabled"
  kyverno: "disabled"
  kyverno-policies: "disabled"
  kyverno-policy-reporter: "disabled"
  loki: "disabled"
  homer-dashboard: "disabled"
  envoy-gateway: "disabled"
  flux-operator: "disabled"
  projectsveltos: "disabled"
```

---

## Final notes

* This repository reflects **real-world platform constraints**
* Manual bootstrap steps are **intentional**, because we are not using here the kubara framework binary itself.
* Everything after bootstrap is **fully GitOps-managed**

If you want a more opinionated framework with less manual wiring, see or ask private access to kubara by saying hi from artem :)

👉 [https://kubara.io](https://kubara.io)
