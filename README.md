# Vikunja on GKE Autopilot with Terraform & Cloud Build (from absolute zero)

This repo shows **every step** from creating a Google Cloud account to a **pipeline** that
provisions infra with **Terraform** and deploys **Vikunja** (open-source to‑do app) to **GKE Autopilot** using **Helm**.
It uses **Cloud SQL (Postgres)** and **Secret Manager**, and authenticates pods to Cloud SQL via **Workload Identity** (no keys).

---

## 0) Create Google Cloud account & project (Console)

1. Go to https://cloud.google.com → **Get started for free** → create your account (add billing).
2. Open the console: https://console.cloud.google.com/
3. Top navbar → **Project selector** → **New Project**:
   - Name: `vikunja-case`
   - Copy the **Project ID** (e.g. `vikunja-case-123456`). We'll use it below.

---

## 1) Install CLI tools locally

- **Google Cloud SDK** (gcloud): https://cloud.google.com/sdk/docs/install
- **kubectl** (install via gcloud):
  ```bash
  gcloud components install kubectl
  ```
- **Helm**: https://helm.sh/docs/intro/install/
- **Terraform**: https://developer.hashicorp.com/terraform/downloads

Verify:
```bash
gcloud version
kubectl version --client
helm version
terraform version
```

Authenticate & set project:
```bash
gcloud init
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default login   # so Terraform can auth with ADC locally (optional)
```

---

## 2) Enable required APIs (one-time)

```bash
gcloud services enable   artifactregistry.googleapis.com   cloudbuild.googleapis.com   container.googleapis.com   firestore.googleapis.com   secretmanager.googleapis.com   sqladmin.googleapis.com   iam.googleapis.com   serviceusage.googleapis.com
```

---

## 3) Create a GCS bucket for Terraform state (bootstrap)

Terraform's GCS backend needs a bucket that exists **before** `terraform init`.

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
export REGION="us-central1"
export TF_BUCKET="${PROJECT_ID}-tfstate"

gcloud storage buckets create gs://$TF_BUCKET --location=$REGION --uniform-bucket-level-access
gcloud storage buckets update gs://$TF_BUCKET --versioning
```

You'll pass this bucket to both local Terraform and the Cloud Build pipeline.

---

## 4) Grant Cloud Build the right IAM (so the pipeline can run Terraform and deploy)

```bash
PROJECT_NUM=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
CB_SA="$PROJECT_NUM@cloudbuild.gserviceaccount.com"

# Allow Cloud Build to create/manage infra and secrets:
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CB_SA" --role="roles/resourcemanager.projectIamAdmin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CB_SA" --role="roles/serviceusage.serviceUsageAdmin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CB_SA" --role="roles/container.admin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CB_SA" --role="roles/cloudsql.admin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CB_SA" --role="roles/secretmanager.admin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$CB_SA" --role="roles/iam.serviceAccountAdmin"
```

> For a stricter setup, scope roles more narrowly later. Above is easiest for first deploys.

---

## 5) Repo layout

```
.
├─ infra/
│  └─ terraform/        # all infra as code
│     ├─ main.tf
│     ├─ variables.tf
│     ├─ outputs.tf
│     └─ versions.tf
├─ helm/
│  └─ vikunja/          # Helm chart for Vikunja (API + Cloud SQL Proxy + Frontend + PVC)
│     ├─ Chart.yaml
│     ├─ values.yaml
│     └─ templates/*.yaml
└─ cloudbuild.yaml       # pipeline: terraform apply → helm upgrade
```

---

## 6) Initialize & apply Terraform **locally** (optional, to test)

> You can skip to step 7 and let **Cloud Build** run Terraform.
> Doing it once locally helps catch issues faster.

```bash
cd infra/terraform
terraform init -backend-config="bucket=$TF_BUCKET" -backend-config="prefix=vikunja/state"
terraform apply -auto-approve -var="project_id=$PROJECT_ID" -var="region=$REGION"
```

This creates:
- **GKE Autopilot** cluster
- **Cloud SQL Postgres** (public IP)
- DB `vikunja`, user `vikunja`, password in **Secret Manager**
- **GSA** (`vikunja-sql@...`) with `cloudsql.client` role
- **IAM binding** so KSA `vikunja/vikunja-api` can impersonate the GSA (Workload Identity)

Outputs:
- `instance_connection_name` – used by the Cloud SQL Proxy

---

## 7) Set up Cloud Build Trigger (Console)

1. Open **Cloud Build → Triggers → Create trigger**.
2. Connect your repo (GitHub/Cloud Source Repos).
3. Event: **Push to branch** → `main`
4. Config: **cloudbuild.yaml** at repo root.
5. **Substitutions**:
   - `_TFSTATE_BUCKET` = your TF bucket name (e.g., `${PROJECT_ID}-tfstate`)
   - `_REGION` = `us-central1` (or your region)

Now every push to `main` runs: **Terraform apply → Helm deploy**.

---

## 8) First pipeline run (commit & push)

```bash
git add .
git commit -m "Initial infra + helm + pipeline for Vikunja"
git push origin main
```

Watch Cloud Build logs. On success:
- GKE cluster exists
- K8s namespace `vikunja` contains:
  - `vikunja-api` + **Cloud SQL Proxy** sidecar
  - `vikunja-frontend`
  - `Service`s, `PVC`, `HPA`, `PDB`

Test quickly (no ingress):
```bash
gcloud container clusters get-credentials todo --region $REGION --project $PROJECT_ID
kubectl -n vikunja get svc
kubectl -n vikunja port-forward svc/vikunja-frontend 8080:80
# Open http://localhost:8080
```

---

## 9) (Optional) Ingress + HTTPS

- Set `ingress.enabled=true` and `ingress.host=todo.example.com` in Helm values or via Helm `--set` flags.
- Add a DNS A record pointing to the Ingress IP.
- For automatic TLS, add a GKE ManagedCertificate (not included to keep it minimal).

---

## 10) Clean up

```bash
cd infra/terraform
terraform destroy -auto-approve
gcloud storage rm -r gs://$TF_BUCKET
```

---

## Troubleshooting tips

- If Terraform fails with API permission errors, confirm Step 4 IAM roles are granted to the Cloud Build SA.
- If pods can’t reach DB, check:
  - KSA annotation → matches GSA email
  - Cloud SQL Proxy args → correct `instance_connection_name`
  - DB password secret exists in the `vikunja` namespace
- View logs:
  ```bash
  kubectl -n vikunja logs deploy/vikunja-api -c api --tail=100
  kubectl -n vikunja logs deploy/vikunja-api -c cloud-sql-proxy --tail=100
  ```