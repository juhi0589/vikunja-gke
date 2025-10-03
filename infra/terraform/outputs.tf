# GKE Autopilot cluster name (used by Cloud Build step 2)
output "gke_autopilot_name" {
  value = google_container_cluster.autopilot.name
}

# NOTE: Do NOT define "instance_connection_name" here.
# It already exists in main.tf to avoid the duplicate-output error.
