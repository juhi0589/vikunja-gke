############################################
# main.tf  —  vikunja-case / europe-west4 #
############################################

# Assumes:
# - providers.tf sets google/google-beta with project = var.project_id, region = var.region
# - backend.tf configures the GCS backend
# - variables.tf defines var.project_id and var.region
# - outputs.tf exports gke_autopilot_name from this cluster

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

  # Keep accidental deletes blocked (we avoid replacements via ignore_changes below)
  deletion_protection = true

  # Prevent Terraform from trying to "unset" Autopilot-managed/computed fields
  lifecycle {
    ignore_changes = [
      # Autopilot-surfaced pools & defaults
      node_pool,
      node_pool_defaults,
      node_pool_auto_config,

      # Control-plane / cluster-level configs that drift or are managed by GKE
      logging_config,
      monitoring_config,
      release_channel,
      workload_identity_config,
      pod_autoscaling,
      vertical_pod_autoscaling,
      gateway_api_config,
      security_posture_config,
      service_external_ips_config,
      notification_config,
      addons_config,
      confidential_nodes,
      ip_allocation_policy,
      master_authorized_networks_config,
      mesh_certificates,
      rbac_binding_config,
      default_snat_status,
      private_cluster_config,
      enterprise_config,
      identity_service_config,
      gke_auto_upgrade_config,
      cost_management_config,
      database_encryption,
    ]
  }
}

##################################
# Cloud SQL Postgres (public IP) #
##################################

# Strong password for DB user (use 'override_special' with random provider v3)
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
    tier              = "db-custom-1-3840"  # 1 vCPU / 3.75 GB (adjust if needed)
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
    # Provider v7+: 'auto {}' replaces the old 'automatic = true'
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

# Used by Cloud Build step 2 to wire Cloud SQL into Helm if present
output "instance_connection_name" {
  value       = google_sql_database_instance.pg.connection_name
  description = "Cloud SQL instance connection name (PROJECT:REGION:INSTANCE)"
}
