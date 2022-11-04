output "data-bucket-name" {
  description = "Name of data bucket"
  value       = google_storage_bucket.basic-data.name
}

output "dataproc-zone" {
  value = google_dataproc_cluster.basic-cluster.cluster_config[0].gce_cluster_config[0].zone
}

output "dataproc-master-node" {
  value = google_dataproc_cluster.basic-cluster.cluster_config[0].master_config[0].instance_names[0]
}
