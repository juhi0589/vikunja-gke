provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable necessary APIs
resource "google_project_service" "service" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "container.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "iam.googleapis.com",
    "serviceusage.googleapis.com"
  ])
  project = var.project_id
  service = each.key
}

# GKE Autopilot cluster
resource "google_container_cluster" "autopilot" {
  name             = "todo"
  location         = var.region
  enable_autopilot = true
  deletion_protection = false
}

# Cloud SQL Postgres (public IP; proxy handles secure access)
resource "google_sql_database_instance" "pg" {
  name             = "vikunja-db"
  region           = var.region
  database_version = "POSTGRES_14"
  settings {
    tier = "db-custom-1-3840"
    ip_configuration {
      ipv4_enabled = true
    }
    availability_type = "ZONAL"
    backup_configuration {
      enabled = true
    }
  }
  deletion_protection = false
  depends_on = [google_project_service.service]
}

resource "google_sql_database" "db" {
  name     = "vikunja"
  instance = google_sql_database_instance.pg.name
}

resource "random_password" "dbpass" {
  length  = 20
  special = true
}

resource "google_sql_user" "user" {
  instance = google_sql_database_instance.pg.name
  name     = "vikunja"
  password = random_password.dbpass.result
}

# Store DB password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "vikunja-db-password"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_password_v" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.dbpass.result
}

# GSA used by the pod (via Workload Identity) to access Cloud SQL through the proxy
resource "google_service_account" "vikunja_sql_gsa" {
  account_id   = "vikunja-sql"
  display_name = "Vikunja Cloud SQL Client"
}

# Grant Cloud SQL Client role to GSA
resource "google_project_iam_member" "vikunja_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.vikunja_sql_gsa.email}"
}

# Allow KSA vikunja/vikunja-api to impersonate GSA (Workload Identity)
resource "google_service_account_iam_member" "wi_bind" {
  service_account_id = google_service_account.vikunja_sql_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[vikunja/vikunja-api]"
}

output "instance_connection_name" {
  value = google_sql_database_instance.pg.connection_name
}