provider "google" {
  project = var.project_id
  region  = var.default_region
}

resource "google_service_account" "default" {
  account_id   = "dataproc-default"
  display_name = "Dataproc default"
}

resource "google_dataproc_cluster" "basic-cluster" {
  name   = var.cluster_name
  region = var.default_region


  graceful_decommission_timeout = "120s"

  cluster_config {
    staging_bucket = google_storage_bucket.staging-data.name

    master_config {
      num_instances = 1
      machine_type  = "n1-standard-2" # 7.5 GB Ram
      disk_config {
        boot_disk_type    = "pd-ssd"
        boot_disk_size_gb = 30
      }
    }

    worker_config {
      num_instances = 2
      machine_type  = "n1-standard-2" # 7.5 GB Ram
      disk_config {
        boot_disk_size_gb = 30
        num_local_ssds    = 1
      }
    }

    preemptible_worker_config {
      num_instances = 0 # do not use additional workers
    }

    gce_cluster_config {
      service_account        = google_service_account.default.email
      service_account_scopes = [
        "cloud-platform"
      ]
    }
  }

  depends_on = [
    google_project_iam_binding.default,
    google_storage_bucket.staging-data
  ]
}

resource "google_storage_bucket" "basic-data" {
  name                     = "${var.cluster_name}-dataproc-data"
  location                 = "EU"
  force_destroy            = true
  public_access_prevention = "enforced"
}

resource "google_storage_bucket" "staging-data" {
  name                     = "${var.cluster_name}-datproc-staging-data"
  location                 = "EU"
  force_destroy            = true
  public_access_prevention = "enforced"
}

resource "google_project_iam_binding" "default" {
  for_each = toset([
    "roles/dataproc.worker",
    "roles/storage.admin",
  ])
  role    = each.key
  project = var.project_id
  members = [
    "serviceAccount:${google_service_account.default.email}"
  ]
}
