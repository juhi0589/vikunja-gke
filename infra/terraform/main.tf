############################################
# main.tf  —  vikunja-case / europe-west4 #
############################################

locals {
  cluster_name = "vikunja-autopilot"
  sql_name     = "vikunja-pg"
  db_name      = "vikunja"
  db_user      = "vikunja"
}

#############################
# GKE Autopilot (regional)  #
#############################
resource "google_container_cluster" "autopilot" {
  name             = local.cluster_name
  location         = var.region
  enable_autopilot = true
}

##################################
# Cloud SQL Postgres (public IP) #
##################################

# Strong password for DB user; NOTE: use override_special (not override_characters)
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!@#%^*-_=+"
}

resource "google_sql_database_instance" "pg" {
  name             = local.sql_name
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier              = "db-custom-1-3840" # 1 vCPU / 3.75 GB (adjust if needed)
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled = true
    }
  }
}

resource "google_sql_database" "vikunja" {
  name     = local.db_name
  instance = google_sql_database_instance.pg.name
}

resource "google_sql_user" "vikunja" {
  name     = local.db_user
  instance = google_sql_database_instance.pg.name
  password = random_password.db.result
}

#######################################
# Secret Manager: DB password storage #
#######################################
resource "google_secret_manager_secret" "db_password" {
  secret_id = "vikunja-db-password"

  replication {
    # Provider v7+: use auto {}    (old 'automatic = true' is invalid)
    auto {}
  }

  labels = {
    app = "vikunja"
  }
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

########################
# Required TF outputs  #
########################

# Cloud Build step 2 reads this to inject into Helm if present
output "instance_connection_name" {
  value       = google_sql_database_instance.pg.connection_name
  description = "Cloud SQL instance connection name (PROJECT:REGION:INSTANCE)"
}
