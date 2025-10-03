output "instance_connection_name" {
  description = "Cloud SQL instance connection name PROJECT:REGION:INSTANCE"
  value       = google_sql_database_instance.pg.connection_name
}