# Prerequisites

This a short checklist of prerequisites you need before starting the bootstrap process.

## Local tooling

You need the following tools installed locally:

* `kubectl`
* `helm`
* `git`
* `argocd` CLI
* `flux` CLI (used later / optional)
* `sveltoctl` CLI (optional, advanced)

## Kubernetes cluster

You need access to **one Kubernetes cluster** acting as the **control plane cluster**.

This can be:

* KinD (for learning), but then with a limited feature set
* A managed service such as:

  * AWS EKS
  * Azure AKS
  * Google GKE
  * STACKIT Kubernetes Service (SKE)
  * OTC Cloud Container Engine (CCE)
  * Civo
  * etc.

## External services (recommended)

Without an secrets manager and DNS provider, you can still run the bootstrap and the GitOps setup, but some features will be limited or not work properly. Especially for the secrets managemnt part.

* A **Secrets Manager**

  * STACKIT Secrets Manager
  * HashiCorp Vault
  * Bitwarden Secrets Manager - Personal recommended for personal use (here you can find a [setup guide](examples/bonus/setup-bitwarden-with-external-secrets.md))
  * etc.

* A **DNS provider**

  * STACKIT DNS
  * AWS Route53
  * Cloudflare
  * Google Cloud DNS
  * etc.

With a DNS provider, you can set up proper domain names and TLS certificates for the control plane services.
Automatic TLS via Let's Encrypt is supported out of the box.

