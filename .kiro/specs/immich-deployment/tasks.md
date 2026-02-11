# Implementation Plan: Immich Deployment

## Overview

Implement the Immich photo/video management stack as Terraform-managed Kubernetes resources, following existing homelab patterns. The implementation proceeds incrementally: variables and namespace first, then supporting services (PostgreSQL, Redis), then the Immich application containers, then networking (Service, Ingress), and finally backup CronJobs.

## Tasks

- [x] 1. Add Immich variables to `variables.tf` and `terraform.tfvars`
  - Add `immich_host` variable (default: `"immich.home"`) to `variables.tf`
  - Add `immich_db_password` sensitive variable to `variables.tf`
  - Add corresponding values to `terraform.tfvars`
  - _Requirements: 5.5_

- [x] 2. Create `applications-immich.tf` with namespace and PostgreSQL
  - [x] 2.1 Create the `immich` namespace resource with `name = "immich"` label
    - Follow existing namespace pattern from `applications-media.tf`
    - Add `depends_on` for `null_resource.kubeconfig_ready` and `null_resource.cluster_api_ready`
    - _Requirements: 1.1, 1.2, 9.2_

  - [x] 2.2 Create the `immich-postgres-secret` Kubernetes Secret
    - Store `POSTGRES_PASSWORD` from `var.immich_db_password`
    - Place in `immich` namespace
    - _Requirements: 3.4_

  - [x] 2.3 Create the PostgreSQL deployment with pgvecto.rs
    - Image: `tensorchord/pgvecto-rs:pg16-v0.2.0`
    - NFS volume at `192.168.0.2:/volume1/Apps/immich/postgres` mounted at `/var/lib/postgresql/data`
    - Environment variables: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` (from secret), `POSTGRES_INITDB_ARGS`
    - Resources: requests 500m/2Gi, limits 1000m/4Gi
    - Readiness probe: TCP socket on port 5432
    - `wait_for_rollout = false`
    - _Requirements: 3.1, 3.2, 3.4, 3.5, 8.3, 1.3_

  - [x] 2.4 Create the `immich-postgres` ClusterIP Service
    - Port 5432 targeting the PostgreSQL deployment
    - _Requirements: 3.3_

- [x] 3. Add Redis deployment and service to `applications-immich.tf`
  - [x] 3.1 Create the Redis deployment
    - Image: `redis:7-alpine`
    - NFS volume at `192.168.0.2:/volume1/Apps/immich/redis` mounted at `/data`
    - Resources: requests 100m/128Mi, limits 250m/256Mi
    - Readiness probe: exec `redis-cli ping`
    - `wait_for_rollout = false`
    - _Requirements: 4.1, 4.3, 4.4, 8.4, 1.3_

  - [x] 3.2 Create the `immich-redis` ClusterIP Service
    - Port 6379 targeting the Redis deployment
    - _Requirements: 4.2_

- [x] 4. Checkpoint - Validate supporting services
  - Run `terraform validate` and `terraform plan` to ensure PostgreSQL and Redis resources are correct. Ask the user if questions arise.

- [x] 5. Add Immich Machine Learning deployment and service
  - [x] 5.1 Create the Immich ML deployment
    - Image: `ghcr.io/immich-app/immich-machine-learning:release`
    - NFS volume at `192.168.0.2:/volume1/Apps/immich/ml-cache` mounted at `/cache`
    - Resources: requests 1000m/2Gi, limits 2000m/4Gi
    - Health check: HTTP GET `/ping` on port 3003
    - `wait_for_rollout = false`
    - _Requirements: 1.5, 8.2, 8.6, 1.3_

  - [x] 5.2 Create the `immich-machine-learning` ClusterIP Service
    - Port 3003 targeting the ML deployment
    - _Requirements: 6.3_

- [x] 6. Add Immich Server deployment, service, and ingress
  - [x] 6.1 Create the Immich Server deployment
    - Image: `ghcr.io/immich-app/immich-server:release`
    - NFS volumes: Photography library at `/mnt/media/photography`, My-life library at `/mnt/media/my-life`, Upload storage at `/usr/src/app/upload`
    - Environment variables: `DB_URL`, `REDIS_HOSTNAME`, `IMMICH_MACHINE_LEARNING_URL`, `UPLOAD_LOCATION`, `TZ`
    - Security context: `fs_group = 1000`
    - Resources: requests 1000m/2Gi, limits 2000m/4Gi
    - Health check: HTTP GET `/api/server/ping` on port 2283
    - `wait_for_rollout = false`
    - _Requirements: 1.4, 2.1, 2.2, 2.3, 2.4, 2.5, 6.1, 6.2, 6.4, 6.5, 6.6, 8.1, 8.5, 1.3_

  - [x] 6.2 Create the `immich-server` ClusterIP Service
    - Port 2283 targeting the Immich Server deployment
    - _Requirements: 5.1_

  - [x] 6.3 Create the Immich Ingress resource
    - Host: `var.immich_host` (default `immich.home`)
    - Ingress class: `nginx`
    - Backend: `immich-server:2283`
    - Annotations: `proxy-body-size: "0"`, `proxy-read-timeout: "600"`, `proxy-send-timeout: "600"`
    - _Requirements: 5.2, 5.3, 5.4_

- [x] 7. Checkpoint - Validate full Immich stack
  - Run `terraform validate` and `terraform plan` to ensure all Immich resources are correct. Ask the user if questions arise.

- [x] 8. Create Immich backup scripts and CronJobs
  - [x] 8.1 Create the `immich-db-backup.sh` script in `scripts/backup/`
    - Use `pg_dump` to dump the Immich database
    - Compress with gzip, name with date stamp
    - Implement retention: keep 7 daily + 4 weekly backups
    - Exit non-zero on failure
    - _Requirements: 7.1, 7.3_

  - [x] 8.2 Create the `immich-upload-backup.sh` script in `scripts/backup/`
    - Use rsync to incrementally sync upload directory to backup location
    - Exit non-zero on failure
    - _Requirements: 7.4_

  - [x] 8.3 Add Immich backup scripts to the existing `backup-scripts` ConfigMap in `backup.tf`
    - Add `immich-db-backup.sh` and `immich-upload-backup.sh` entries
    - _Requirements: 7.8_

  - [x] 8.4 Create the `immich-db-backup` CronJob in `applications-immich.tf`
    - Schedule: `30 2 * * *` (daily at 2:30 AM)
    - Image: `postgres:16-alpine`
    - Backup namespace, backup service account
    - NFS backup volume at `192.168.0.2:/volume1/Apps/kube-backups/immich`
    - Restart policy: OnFailure
    - _Requirements: 7.1, 7.2, 7.6, 7.7_

  - [x] 8.5 Create the `immich-upload-backup` CronJob in `applications-immich.tf`
    - Schedule: `30 3 * * *` (daily at 3:30 AM)
    - Image: `alpine:3.18`
    - Backup namespace, backup service account
    - NFS volumes for source (upload) and destination (backup)
    - Restart policy: OnFailure
    - _Requirements: 7.4, 7.5, 7.6, 7.7_

  - [ ]* 8.6 Write property test for backup retention logic
    - **Property 1: Backup retention preserves exactly 7 daily and 4 weekly backups**
    - **Validates: Requirements 7.3**

- [x] 9. Final checkpoint - Validate complete deployment
  - Run `terraform validate` and `terraform plan` on the entire configuration. Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- All Terraform resources follow existing patterns from `applications-media.tf` and `backup.tf`
- The user must add an `/etc/hosts` entry for `immich.home` pointing to the ingress IP (`var.ingress_ip`) after deployment
- NFS directories on 192.168.0.2 (`/volume1/Apps/immich/*`) must be created and exported before `terraform apply`
- The `immich_db_password` must be set in `terraform.tfvars` before applying
