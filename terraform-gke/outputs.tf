output "cluster_name" {
  value = module.gke_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.gke_cluster.cluster_endpoint
}

output "cluster_ca_certificate" {
  value = module.gke_cluster.cluster_ca_certificate
  sensitive = true
}
