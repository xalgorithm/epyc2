# Design Document: Immich Deployment

## Overview

This design describes the Terraform-managed deployment of Immich into the existing K3s homelab cluster. The deployment follows established patterns: raw Kubernetes resources in Terraform (not Helm), NFS-backed persistent storage, NGINX Ingress with `.home` domain routing, and CronJob-based backups to the central NFS backup location.

The Immich stack consists of four components: the Immich server (web UI + API), the Immich machine learning service (facial recognition, smart search), PostgreSQL with pgvecto.rs (metadata + vector search), and Redis (job queue + cache). Two external NFS photo libraries are mounted read-write into the server container.

## Architecture

```mermaid
graph TB
    subgraph "External Network"
        Client[Browser / Mobile App]
    end

    subgraph "Kubernetes Cluster"
        subgraph "immich namespace"
            IS[Immich Server<br/>:2283]
            ML[Immich ML<br/>:3003]
            PG[PostgreSQL + pgvecto.rs<br/>:5432]
            RD[Redis<br/>:6379]
        end

        subgraph "ingress"
            ING[NGINX Ingress<br/>immich.home]
        end

        subgraph "backup namespace"
            BK_DB[DB Backup CronJob<br/>2:30 AM daily]
            BK_UP[Upload Backup CronJob<br/>3:30 AM daily]
        end
    end

    subgraph "NFS Storage"
        NFS_PHOTO1[192.168.0.11<br/>/vpool/image-main/Photography]
        NFS_PHOTO2[192.168.0.11<br/>/vpool/image-main/my-life]
        NFS_CONFIG[192.168.0.2<br/>/volume1/Apps/immich/]
        NFS_BACKUP[192.168.0.2<br/>/volume1/Apps/kube-backups/immich/]
    end

    Client --> ING --> IS
    IS --> ML
    IS --> PG
    IS --> RD
    IS --> NFS_PHOTO1
    IS --> NFS_PHOTO2
    IS --> NFS_CONFIG
    PG --> NFS_CONFIG
    RD --> NFS_CONFIG
    BK_DB --> PG
    BK_DB --> NFS_BACKUP
    BK_UP --> NFS_CONFIG
    BK_UP --> NFS_BACKUP
```

## Components and Interfaces

### 1. Immich Server (Deployment + Service)

- Image: `ghcr.io/immich-app/immich-server:release`
- Port: 2283 (HTTP)
- Service: `immich-server` (ClusterIP)
- Volumes:
  - Photography library (NFS 192.168.0.11): mounted at `/mnt/media/photography`
  - My-life library (NFS 192.168.0.11): mounted at `/mnt/media/my-life`
  - Upload storage (NFS 192.168.0.2): mounted at `/usr/src/app/upload`
- Environment variables:
  - `DB_URL`: `postgresql://immich:${password}@immich-postgres.immich.svc.cluster.local:5432/immich`
  - `REDIS_HOSTNAME`: `immich-redis.immich.svc.cluster.local`
  - `IMMICH_MACHINE_LEARNING_URL`: `http://immich-machine-learning.immich.svc.cluster.local:3003`
  - `UPLOAD_LOCATION`: `/usr/src/app/upload`
  - `TZ`: `America/Los_Angeles`
- Resources: requests 1 CPU / 2Gi, limits 2 CPU / 4Gi
- Health check: HTTP GET `/api/server/ping` on port 2283

### 2. Immich Machine Learning (Deployment + Service)

- Image: `ghcr.io/immich-app/immich-machine-learning:release`
- Port: 3003 (HTTP)
- Service: `immich-machine-learning` (ClusterIP)
- Volumes:
  - Model cache (NFS 192.168.0.2): mounted at `/cache`
- Environment variables:
  - `IMMICH_HOST`: `0.0.0.0`
  - `IMMICH_PORT`: `3003`
- Resources: requests 1 CPU / 2Gi, limits 2 CPU / 4Gi
- Health check: HTTP GET `/ping` on port 3003

### 3. PostgreSQL with pgvecto.rs (Deployment + Service)

- Image: `tensorchord/pgvecto-rs:pg16-v0.2.0`
- Port: 5432
- Service: `immich-postgres` (ClusterIP)
- Volumes:
  - Data directory (NFS 192.168.0.2): mounted at `/var/lib/postgresql/data`
- Environment variables:
  - `POSTGRES_DB`: `immich`
  - `POSTGRES_USER`: `immich`
  - `POSTGRES_PASSWORD`: from Kubernetes Secret
  - `POSTGRES_INITDB_ARGS`: `--data-checksums`
- Resources: requests 500m CPU / 2Gi, limits 1 CPU / 4Gi
- Health check: TCP socket on port 5432
- Note: The pgvecto.rs image includes the vector extension pre-installed. Immich auto-creates the extension on first startup.

### 4. Redis (Deployment + Service)

- Image: `redis:7-alpine`
- Port: 6379
- Service: `immich-redis` (ClusterIP)
- Volumes:
  - Data directory (NFS 192.168.0.2): mounted at `/data`
- Resources: requests 100m CPU / 128Mi, limits 250m CPU / 256Mi
- Health check: exec `redis-cli ping`

### 5. Ingress

- Host: `immich.home` (configurable via `var.immich_host`)
- Ingress class: `nginx`
- Backend: `immich-server:2283`
- Annotations:
  - `nginx.ingress.kubernetes.io/proxy-body-size: "0"` (unlimited uploads)
  - `nginx.ingress.kubernetes.io/proxy-read-timeout: "600"` (long uploads)
  - `nginx.ingress.kubernetes.io/proxy-send-timeout: "600"`

### 6. Backup CronJobs

Two CronJobs in the `backup` namespace, using the existing `backup` service account:

**Database Backup (daily at 2:30 AM)**:
- Image: `postgres:16-alpine`
- Runs `pg_dump` against `immich-postgres.immich.svc.cluster.local`
- Stores compressed dumps at `/volume1/Apps/kube-backups/immich/db/`
- Retention: 7 daily + 4 weekly (managed by naming convention + cleanup script)
- Restart policy: OnFailure

**Upload Backup (daily at 3:30 AM)**:
- Image: `alpine:3.18`
- Runs `rsync` from Immich upload NFS path to backup NFS path
- Stores at `/volume1/Apps/kube-backups/immich/uploads/`
- Incremental sync (only changed files)
- Restart policy: OnFailure

### 7. Kubernetes Secret

- Name: `immich-postgres-secret` in `immich` namespace
- Contains: `POSTGRES_PASSWORD`
- Referenced by both PostgreSQL and Immich Server deployments

### 8. Terraform Variables

New variables added to `variables.tf`:
- `immich_host` (default: `"immich.home"`)
- `immich_db_password` (sensitive, no default)

## Data Models

### NFS Volume Layout

```
192.168.0.11 (TrueNAS - Media)
├── /vpool/image-main/Photography    → mounted at /mnt/media/photography (Immich Server)
└── /vpool/image-main/my-life        → mounted at /mnt/media/my-life (Immich Server)

192.168.0.2 (NFS Primary)
└── /volume1/Apps/immich/
    ├── postgres/                     → mounted at /var/lib/postgresql/data (PostgreSQL)
    ├── redis/                        → mounted at /data (Redis)
    ├── upload/                       → mounted at /usr/src/app/upload (Immich Server)
    └── ml-cache/                     → mounted at /cache (Immich ML)

192.168.0.2 (NFS Backups)
└── /volume1/Apps/kube-backups/immich/
    ├── db/
    │   ├── immich-db-daily-YYYYMMDD.sql.gz    (7 retained)
    │   └── immich-db-weekly-YYYYMMDD.sql.gz   (4 retained)
    └── uploads/                                (rsync mirror)
```

### Kubernetes Resource Relationships

```mermaid
graph LR
    NS[Namespace: immich] --> DEP_S[Deployment: immich-server]
    NS --> DEP_ML[Deployment: immich-ml]
    NS --> DEP_PG[Deployment: immich-postgres]
    NS --> DEP_RD[Deployment: immich-redis]
    NS --> SEC[Secret: immich-postgres-secret]

    DEP_S --> SVC_S[Service: immich-server]
    DEP_ML --> SVC_ML[Service: immich-machine-learning]
    DEP_PG --> SVC_PG[Service: immich-postgres]
    DEP_RD --> SVC_RD[Service: immich-redis]

    SVC_S --> ING[Ingress: immich]

    BK_NS[Namespace: backup] --> CJ_DB[CronJob: immich-db-backup]
    BK_NS --> CJ_UP[CronJob: immich-upload-backup]
```

### Resource Budget

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| Immich Server | 1000m | 2000m | 2Gi | 4Gi |
| Immich ML | 1000m | 2000m | 2Gi | 4Gi |
| PostgreSQL | 500m | 1000m | 2Gi | 4Gi |
| Redis | 100m | 250m | 128Mi | 256Mi |
| **Total** | **2600m** | **5250m** | **6.1Gi** | **12.25Gi** |


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Most acceptance criteria for this feature are infrastructure configuration checks (specific values in Terraform resources). These are best validated as example-based tests that verify the Terraform plan output contains the expected resource configurations. One criterion (backup retention) represents a universal property.

### Property 1: Backup retention preserves exactly 7 daily and 4 weekly backups

*For any* sequence of dated backup files spanning an arbitrary number of days, running the backup cleanup logic SHALL retain exactly the 7 most recent daily backups and the 4 most recent weekly backups, removing all others.

**Validates: Requirements 7.3**

## Error Handling

### Database Connectivity Failures
- The Immich Server uses Kubernetes service DNS (`immich-postgres.immich.svc.cluster.local`) for database connectivity. If PostgreSQL is unavailable, the readiness probe on the Immich Server will fail, removing it from the Service endpoints until the database recovers.
- The PostgreSQL deployment has a readiness probe on port 5432. Kubernetes will not route traffic to the pod until it passes.

### NFS Mount Failures
- If an NFS server (192.168.0.11 or 192.168.0.2) becomes unreachable, pods mounting those volumes will fail to start and enter `ContainerCreating` state. Kubernetes will retry based on the pod restart policy.
- The `fs_group = 1000` security context ensures consistent NFS permission handling across pod restarts.

### Backup Failures
- Both backup CronJobs use `restartPolicy: OnFailure`, so Kubernetes will retry failed backup jobs.
- `failed_jobs_history_limit = 1` ensures failed job pods are retained for debugging.
- `successful_jobs_history_limit = 3` keeps recent successful runs visible.
- The database backup script should exit with a non-zero code if `pg_dump` fails, triggering the restart policy.

### Resource Exhaustion
- All components have explicit resource limits preventing any single component from consuming unbounded cluster resources.
- The ML component has the highest memory allocation (4Gi limit) to accommodate model loading.

### Upload Size
- The ingress annotation `proxy-body-size: "0"` removes the upload size limit, preventing nginx from rejecting large photo/video uploads.
- Extended proxy timeouts (600s) prevent timeout errors during large file transfers.

## Testing Strategy

### Terraform Validation

Since this is an infrastructure-as-code deployment, the primary testing approach is Terraform plan validation:

1. `terraform validate` — Syntax and provider schema validation
2. `terraform plan` — Verify the plan produces the expected resources without errors
3. Manual review of plan output to confirm resource configurations match requirements

### Unit Tests (Example-Based)

Terraform-native testing or manual plan inspection for specific configuration values:

- Verify namespace name and labels (Req 1.1)
- Verify container images for all four components (Req 1.4, 1.5, 3.1, 4.1)
- Verify NFS volume server IPs and paths for all mounts (Req 2.1–2.4, 3.2, 4.3, 6.6)
- Verify service names, types, and ports (Req 3.3, 4.2, 5.1, 6.3)
- Verify environment variables on Immich Server (Req 6.1–6.5)
- Verify ingress host, class, and annotations (Req 5.2–5.4)
- Verify resource requests and limits match specified values (Req 8.1–8.4)
- Verify health check paths and ports (Req 8.5, 8.6)
- Verify CronJob schedules and backup paths (Req 7.1, 7.2, 7.4, 7.5)
- Verify backup CronJobs use backup namespace and service account (Req 7.7)

### Property-Based Tests

- **Property 1**: Backup retention logic — generate random sequences of dated backup filenames, run the cleanup function, and verify exactly 7 daily + 4 weekly are retained.
  - Library: Use `pytest` with `hypothesis` if backup scripts are testable in isolation, or shell-based testing with generated file lists.
  - Minimum 100 iterations.
  - Tag: **Feature: immich-deployment, Property 1: Backup retention preserves exactly 7 daily and 4 weekly backups**

### Integration Verification

After `terraform apply`:
- Verify all pods in `immich` namespace reach `Running` state
- Verify `immich.home` resolves and returns the Immich web UI
- Verify NFS mounts are accessible inside the Immich Server pod
- Verify backup CronJobs appear in the `backup` namespace
