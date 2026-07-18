# GCP Sandbox Enterprise Landing Zone via Terraform

A programmatic multi-project infrastructure topology engineered within the strict guardrails of a GCP Student / Free Trial environment.

## 🏗️ Architecture Design Matrix

```text
  ┌─────────────────────────────────────────────────────────────┐
  │                   GOOGLE CLOUD PLATFORM                     │
  │                     [ Billing Account ]                     │
  └──────────────────────────────┬──────────────────────────────┘
                                 │
         ┌───────────────────────┴───────────────────────┐
         ▼                                               ▼
┌──────────────────────────────┐                ┌──────────────────────────────┐
│  PROJECT: network-host-prod  │                │     PROJECT: app-prod        │
├──────────────────────────────┤                ├──────────────────────────────┤
│  VPC: vpc-host-core          │                │  VPC: vpc-app-core           │
│  CIDR: 10.0.1.0/24           │                │  CIDR: 10.0.2.0/24           │
│  SUBNET: sb-hub-services     │                │  SUBNET: sb-production-apps  │
└──────────────┬───────────────┘                └───────────────┬──────────────┘
               │                                                │
               │         🤝 GLOBAL VPC PEERING ROUTE            │
               └────────────────────────────────────────────────┘
                                        ▲
                                        │
                         🔒 IDENTITY-AWARE PROXY (IAP)
                               [ 35.235.240.0/20 ]
                                        │
                                        ▼
                        ┌──────────────────────────────┐
                        │   INSTANCE: vm-prod-app-01   │
                        ├──────────────────────────────┤
                        │   • No Public IP Interface   │
                        │   • Ingress restricted to 22 │
                        └──────────────────────────────┘

## 🧠 Engineering Adaptations & Core Pivots

### 1. The "No Organization" Paradigm Pivot
* **The Challenge:** Enterprise landing zones traditionally mandate an Organization root node to deploy hierarchical folders and `Shared VPC` networks (`google_compute_shared_vpc_host_project`). Attempting this on a standard GCP Student/Free Trial account triggers a destructive `Error 400: The project has no organization` API refusal.
* **The Solution:** Transformed the network topology into a **Bilateral VPC Peering Engine** across separate billing-linked projects (`porterman66-net-host-prod` and `porterman66-app-prod`), cleanly replicating isolated corporate tiering without an enterprise organizational wrapper.

### 2. Zero-Trust Ingress Hardening
* **The Challenge:** Securing `vm-prod-app-01` without exposing public IPs or launching costly bastion hosts that burn through trial credits.
* **The Solution:** Provisioned an entirely private interface decoupled from the public internet. Access controls are routed exclusively through Google's **Identity-Aware Proxy (IAP)**, locking ingress down strictly to the cryptographic block `35.235.240.0/20` over port `22`.

## 🚀 How to Validate Routing Connectivity

To securely traverse the IAP proxy tunnel and connect directly to the private application node, execute the tunnel wrapper from your terminal:

```bash
gcloud compute ssh vm-prod-app-01 \
    --project="porterman66-app-prod" \
    --zone="us-central1-a" \
    --tunnel-through-iap