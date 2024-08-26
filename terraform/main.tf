provider "google" {
  project     = "terraform-expense-gcp"
  credentials = file("terraform-expense-gcp-311df481f672.json")
  region      = "us-central1"
  zone        = "us-central1-a"
}

# Data source to get project details
data "google_project" "project" {}

# Networking resources
resource "google_compute_network" "vpc_network" {
  name                    = "my-app-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "my-app-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
}

# Firewall Rules
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "needed-ports" {
  name    = "needed-ports"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = [
      "5000",   # backend
      "80",     # HTTP
      "443",    # HTTPS
      "8080",   # Jenkins
      "9090",   # Prometheus
      "3000",   # Grafana
      "9093",   # Alert Manager
      "5001",   #alert webhook
    ]
  }

  source_ranges = ["0.0.0.0/0"]
}

# VM Instances
resource "google_compute_instance" "vm_tooling" {
  name         = "vm-tooling"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {}
  }

  metadata = {
    ssh-keys = "yassirdiri:${file("/home/yassir/.ssh/gcp_key.pub")}"
  }

  tags = ["tooling"]
}

resource "google_compute_instance" "vm_app" {
  name         = "vm-app"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {}
  }

  metadata = {
    ssh-keys = "yassirdiri:${file("/home/yassir/.ssh/gcp_key.pub")}"
  }

  tags = ["app"]
}

# Output VM IP addresses
output "tooling_vm_ip" {
  value = google_compute_instance.vm_tooling.network_interface[0].access_config[0].nat_ip
}

output "app_vm_ip" {
  value = google_compute_instance.vm_app.network_interface[0].access_config[0].nat_ip
}

# Cloud Function resources for VM automation

# Storage bucket to store function archives
resource "google_storage_bucket" "function_bucket" {
  name     = "yas-bucket-44"
  location = "US"
}

# Upload function ZIP archives
resource "google_storage_bucket_object" "stop_vms_archive" {
  name   = "stop_vms.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = "/home/yassir/Desktop/cloud_functions/stop_vms.zip"
}

resource "google_storage_bucket_object" "start_vms_archive" {
  name   = "start_vms.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = "/home/yassir/Desktop/cloud_functions/start_vms.zip"
}

# Deploy Cloud Functions
resource "google_cloudfunctions_function" "stop_vms" {
  name        = "stop-vms"
  runtime     = "python39"
  entry_point = "stop_vms"
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.stop_vms_archive.name
  trigger_http = true
  available_memory_mb = 256
}

resource "google_cloudfunctions_function" "start_vms" {
  name        = "start-vms"
  runtime     = "python39"
  entry_point = "start_vms"
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.start_vms_archive.name
  trigger_http = true
  available_memory_mb = 256
}

# Cloud Scheduler jobs for triggering Cloud Functions

resource "google_cloud_scheduler_job" "stop_vms_scheduler" {
  name        = "stop-vms-scheduler"
  description = "Schedule to stop VMs at 9:30 PM Casablanca time"
  schedule    = "30 21 * * 1-5"
  time_zone   = "Africa/Casablanca"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.stop_vms.https_trigger_url
    oidc_token {
      service_account_email = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
    }
  }
}

resource "google_cloud_scheduler_job" "start_vms_scheduler" {
  name        = "start-vms-scheduler"
  description = "Schedule to start VMs at 7:30 AM Casablanca time"
  schedule    = "30 7 * * 1-5"
  time_zone   = "Africa/Casablanca"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.start_vms.https_trigger_url
    oidc_token {
      service_account_email = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
    }
  }
}

# New IAM bindings for Cloud Scheduler and Cloud Functions

resource "google_cloudfunctions_function_iam_member" "invoker_start" {
  project        = data.google_project.project.project_id
  region         = google_cloudfunctions_function.start_vms.region
  cloud_function = google_cloudfunctions_function.start_vms.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_cloudfunctions_function_iam_member" "invoker_stop" {
  project        = data.google_project.project.project_id
  region         = google_cloudfunctions_function.stop_vms.region
  cloud_function = google_cloudfunctions_function.stop_vms.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "function_compute_admin" {
  project = data.google_project.project.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${data.google_project.project.project_id}@appspot.gserviceaccount.com"
}