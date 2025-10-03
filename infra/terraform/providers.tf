# Tell the Google provider which project/region to use
provider "google" {
  project = var.project_id
  region  = var.region
}

# (Optional) keep in case you ever use google-beta resources later
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
