terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "sk-tf-state-exp"
    prefix = "terraform/gke"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  count                   = var.create_vpc ? 1 : 0
  name                    = var.network
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  count         = var.create_vpc ? 1 : 0
  name          = var.subnetwork
  region        = var.region
  network       = google_compute_network.vpc[0].id
  ip_cidr_range = var.vpc_cidr
}

module "gke_cluster" {
  source = "../terraform/modules/gke-cluster"

  cluster_name          = var.cluster_name
  region                = var.region
  regional              = var.regional
  zones                 = var.zones
  deletion_protection   = var.deletion_protection
  network               = var.create_vpc ? google_compute_network.vpc[0].name : var.network
  subnetwork            = var.create_vpc ? google_compute_subnetwork.subnet[0].name : var.subnetwork
  service_account_email = var.service_account_email

  clickhouse_node_count   = var.clickhouse_node_count
  clickhouse_disk_size_gb = var.clickhouse_disk_size_gb
  clickhouse_disk_type    = var.clickhouse_disk_type

  keeper_node_count   = var.keeper_node_count
  keeper_disk_size_gb = var.keeper_disk_size_gb
  keeper_disk_type    = var.keeper_disk_type

  general_node_count   = var.general_node_count
  general_disk_size_gb = var.general_disk_size_gb
  general_disk_type    = var.general_disk_type
}
