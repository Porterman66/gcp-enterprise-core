terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  region  = "us-central1"
  zone    = "us-central1-a"
}

# Variable placeholder for safety - do not hardcode secrets
variable "billing_account_id" {
  type        = string
  description = "Your GCP Free Trial Billing Account ID from gcloud"
  default     = "01677B-AA1005-C006BD" 
}

# 1. Dedicated Shared Network Host Project
resource "google_project" "network_host" {
  name            = "prj-shared-network"
  project_id      = "porterman66-net-host-prod"
  billing_account = var.billing_account_id
}

# 2. Dedicated Production Workload Project 
resource "google_project" "app_prod" {
  name            = "prj-app-production"
  project_id      = "porterman66-app-prod"
  billing_account = var.billing_account_id
}
# ==========================================================================
# 5. SERVICE API ENABLEMENT (Required before provisioning any network assets)
# ==========================================================================

resource "google_project_service" "compute_host" {
  project            = google_project.network_host.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute_app" {
  project            = google_project.app_prod.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# ==========================================================================
# 6. LOCAL NETWORKS (Independent VPCs per project boundary)
# ==========================================================================

# Network for the Host/Hub project
resource "google_compute_network" "host_vpc" {
  name                    = "vpc-host-core"
  project                 = google_project.network_host.project_id
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute_host]
}

resource "google_compute_subnetwork" "host_subnet" {
  name          = "sb-hub-services"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  project       = google_project.network_host.project_id
  network       = google_compute_network.host_vpc.self_link
}

# Network for the Production Application project
resource "google_compute_network" "app_vpc" {
  name                    = "vpc-app-core"
  project                 = google_project.app_prod.project_id
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute_app]
}

resource "google_compute_subnetwork" "app_subnet" {
  name          = "sb-production-apps"
  ip_cidr_range = "10.0.2.0/24" # Changed to avoid overlapping IP blocks
  region        = "us-central1"
  project       = google_project.app_prod.project_id
  network       = google_compute_network.app_vpc.self_link
}

# ==========================================================================
# 7. TRIAL-COMPLIANT INTER-PROJECT CONNECTIVITY (VPC Peering)
# ==========================================================================

# Connection going from Host VPC over to App VPC
resource "google_compute_network_peering" "host_to_app" {
  name         = "peer-host-to-app"
  network      = google_compute_network.host_vpc.self_link
  peer_network = google_compute_network.app_vpc.self_link
}

# Connection going from App VPC back over to Host VPC
resource "google_compute_network_peering" "app_to_host" {
  name         = "peer-app-to-host"
  network      = google_compute_network.app_vpc.self_link
  peer_network = google_compute_network.host_vpc.self_link
}

# ==========================================================================
# 8. APPLICATION COMPUTE ENGINE WORKLOAD
# ==========================================================================

resource "google_compute_instance" "app_server" {
  name         = "vm-prod-app-01"
  project      = google_project.app_prod.project_id
  machine_type = "e2-micro" # Highly cost-effective for Student Free Trials
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network    = google_compute_network.app_vpc.self_link
    subnetwork = google_compute_subnetwork.app_subnet.self_link
    
    # Leaving this block completely empty ensures the VM receives NO Public IP.
    # It remains entirely private and secure within our internal network.
  }

  metadata = {
    enable-oslogin = "TRUE"
  }
}

# ==========================================================================
# 9. CENTRAL FIREWALL ENGINE (Ingress Guards for Peered Topology)
# ==========================================================================

# Rules for the Host Network (vpc-host-core)
resource "google_compute_firewall" "host_allow_internal" {
  name    = "fw-host-allow-internal"
  project = google_project.network_host.project_id
  network = google_compute_network.host_vpc.name

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  # Allow incoming traffic explicitly from the peered production application subnet
  source_ranges = ["10.0.2.0/24"]
}

# Rules for the Production Application Network (vpc-app-core)
resource "google_compute_firewall" "app_allow_iap_ingress" {
  name    = "fw-app-allow-iap-ingress"
  project = google_project.app_prod.project_id
  network = google_compute_network.app_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"] # Enforce secure SSH landing controls
  }

  # Strictly whitelist only Google's official Identity-Aware Proxy routing block
  source_ranges = ["35.235.240.0/20"]
}