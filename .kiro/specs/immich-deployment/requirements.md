# Requirements Document

## Introduction

Deploy Immich, a self-hosted photo and video management solution, to the existing Kubernetes homelab cluster managed by Terraform. Immich will serve as the primary photo/video library, backed by two NFS image directories, with PostgreSQL (pgvecto.rs) for metadata and vector search, Redis for caching, and automated backups following established infrastructure patterns.

## Glossary

- **Immich_Server**: The main Immich application container providing the web UI and API for photo/video management
- **Immich_Machine_Learning**: The Immich ML container that handles facial recognition, object detection, and smart search
- **PostgreSQL_Database**: A PostgreSQL instance with the pgvecto.rs extension, used by Immich for metadata storage and vector-based similarity search
- **Redis_Cache**: A Redis instance used by Immich for job queuing and caching
- **Photography_Library**: The NFS share at 192.168.0.11:/vpool/image-main/Photography containing the user's photography collection
- **My_Life_Library**: The NFS share at 192.168.0.11:/vpool/image-main/my-life containing the user's personal photo/video collection
- **Backup_CronJob**: A Kubernetes CronJob resource that performs scheduled backups of Immich data
- **Ingress_Resource**: A Kubernetes Ingress that routes external traffic to the Immich_Server via the NGINX Ingress Controller
- **Immich_Namespace**: The Kubernetes namespace isolating all Immich-related resources

## Requirements

### Requirement 1: Immich Namespace and Core Deployment

**User Story:** As a homelab operator, I want Immich deployed in its own Kubernetes namespace following existing conventions, so that it is isolated and consistent with the rest of the cluster.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create an Immich_Namespace named "immich" with a label `name = "immich"`
2. THE Terraform_Configuration SHALL define all Immich resources in a file named `applications-immich.tf`
3. WHEN the Immich_Server deployment is created, THE Terraform_Configuration SHALL set `wait_for_rollout` to false to match existing deployment patterns
4. THE Immich_Server deployment SHALL use the official Immich container image `ghcr.io/immich-app/immich-server`
5. THE Immich_Machine_Learning deployment SHALL use the official Immich ML container image `ghcr.io/immich-app/immich-machine-learning`

### Requirement 2: NFS Photo Library Mounts

**User Story:** As a homelab operator, I want Immich to access my two NFS photo directories, so that Immich can manage and index my existing photo and video collections.

#### Acceptance Criteria

1. THE Immich_Server SHALL mount the Photography_Library from NFS server 192.168.0.11 at path `/vpool/image-main/Photography` as a read-write volume
2. THE Immich_Server SHALL mount the My_Life_Library from NFS server 192.168.0.11 at path `/vpool/image-main/my-life` as a read-write volume
3. THE Immich_Server SHALL mount the Photography_Library at `/mnt/media/photography` inside the container
4. THE Immich_Server SHALL mount the My_Life_Library at `/mnt/media/my-life` inside the container
5. THE Immich_Server pod spec SHALL set `fs_group` to 1000 in the security context to match existing NFS access patterns

### Requirement 3: PostgreSQL Database with pgvecto.rs

**User Story:** As a homelab operator, I want Immich backed by a PostgreSQL database with vector search support, so that Immich can store metadata and perform smart search on my photos.

#### Acceptance Criteria

1. THE PostgreSQL_Database SHALL use the `tensorchord/pgvecto-rs:pg16-v0.2.0` container image to provide the pgvecto.rs extension
2. THE PostgreSQL_Database SHALL store its data on a persistent NFS volume at `192.168.0.2:/volume1/Apps/immich/postgres`
3. THE PostgreSQL_Database SHALL expose port 5432 via a ClusterIP Service named `immich-postgres`
4. THE PostgreSQL_Database SHALL configure the database name, username, and password via environment variables
5. WHEN the PostgreSQL_Database container starts, THE PostgreSQL_Database SHALL run a readiness probe against port 5432 to confirm availability

### Requirement 4: Redis Cache

**User Story:** As a homelab operator, I want a Redis instance for Immich, so that job queuing and caching work correctly.

#### Acceptance Criteria

1. THE Redis_Cache SHALL use the `redis:7-alpine` container image
2. THE Redis_Cache SHALL expose port 6379 via a ClusterIP Service named `immich-redis`
3. THE Redis_Cache SHALL store data on a persistent NFS volume at `192.168.0.2:/volume1/Apps/immich/redis`
4. WHEN the Redis_Cache container starts, THE Redis_Cache SHALL run a readiness probe using `redis-cli ping` to confirm availability

### Requirement 5: Service Networking and DNS Resolution

**User Story:** As a homelab operator, I want Immich accessible at `immich.home` and via its cluster IP, so that I can access it from any device on my network.

#### Acceptance Criteria

1. THE Immich_Server SHALL be exposed via a ClusterIP Service named `immich-server` on port 2283
2. THE Ingress_Resource SHALL route traffic for host `immich.home` to the `immich-server` Service on port 2283
3. THE Ingress_Resource SHALL use the `nginx` ingress class to match existing ingress patterns
4. THE Ingress_Resource SHALL include the annotation `nginx.ingress.kubernetes.io/proxy-body-size` set to `0` to allow unlimited upload sizes for photos and videos
5. THE Terraform_Configuration SHALL declare a variable `immich_host` with a default value of `immich.home`

### Requirement 6: Immich Configuration and Inter-Service Communication

**User Story:** As a homelab operator, I want all Immich components properly configured to communicate with each other, so that the application functions correctly as a whole.

#### Acceptance Criteria

1. THE Immich_Server SHALL receive the PostgreSQL connection string via the `DB_URL` environment variable pointing to the `immich-postgres` Service
2. THE Immich_Server SHALL receive the Redis connection string via the `REDIS_HOSTNAME` environment variable pointing to the `immich-redis` Service
3. THE Immich_Machine_Learning SHALL expose port 3003 via a ClusterIP Service named `immich-machine-learning`
4. THE Immich_Server SHALL reference the Immich_Machine_Learning service URL via the `IMMICH_MACHINE_LEARNING_URL` environment variable
5. THE Immich_Server SHALL set the `UPLOAD_LOCATION` environment variable to `/usr/src/app/upload` for Immich-managed uploads
6. THE Immich_Server SHALL store upload data on a persistent NFS volume at `192.168.0.2:/volume1/Apps/immich/upload`

### Requirement 7: Automated Backup of Immich Data

**User Story:** As a homelab operator, I want consistent automated backups of Immich's database and upload data, so that I can recover from data loss.

#### Acceptance Criteria

1. THE Backup_CronJob SHALL run a PostgreSQL database dump daily at 2:30 AM using `pg_dump`
2. THE Backup_CronJob SHALL store database dumps on the NFS backup volume at `192.168.0.2:/volume1/Apps/kube-backups/immich`
3. THE Backup_CronJob SHALL retain the last 7 daily backups and 4 weekly backups of the database
4. THE Backup_CronJob SHALL run an upload directory backup daily at 3:30 AM using rsync
5. THE Backup_CronJob SHALL store upload backups on the NFS backup volume at `192.168.0.2:/volume1/Apps/kube-backups/immich/uploads`
6. IF a Backup_CronJob fails, THEN THE Backup_CronJob SHALL set `restartPolicy` to `OnFailure` to retry the backup
7. THE Backup_CronJob SHALL use the `backup` namespace and `backup` service account consistent with existing backup infrastructure
8. THE Terraform_Configuration SHALL add the Immich backup scripts to the existing `backup-scripts` ConfigMap

### Requirement 8: Resource Limits and Health Checks

**User Story:** As a homelab operator, I want appropriate resource limits and health checks on all Immich components, so that the cluster remains stable and services recover from failures.

#### Acceptance Criteria

1. THE Immich_Server SHALL request 1 CPU and 2Gi memory, with limits of 2 CPU and 4Gi memory
2. THE Immich_Machine_Learning SHALL request 1 CPU and 2Gi memory, with limits of 2 CPU and 4Gi memory
3. THE PostgreSQL_Database SHALL request 500m CPU and 2Gi memory, with limits of 1 CPU and 4Gi memory
4. THE Redis_Cache SHALL define CPU and memory resource requests and limits
5. WHEN the Immich_Server is running, THE Immich_Server SHALL respond to HTTP health checks on `/api/server/ping` on port 2283
6. WHEN the Immich_Machine_Learning is running, THE Immich_Machine_Learning SHALL respond to HTTP health checks on `/ping` on port 3003

### Requirement 9: Cluster Resource Availability

**User Story:** As a homelab operator, I want to ensure the cluster has sufficient resources for Immich, so that the deployment does not starve existing workloads.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL document that the Immich stack requires a total of 5 CPU (2 server + 2 ML + 1 PostgreSQL) and 12Gi memory (4Gi server + 4Gi ML + 4Gi PostgreSQL) at peak limits
2. WHEN the Immich deployments are created, THE Terraform_Configuration SHALL use `depends_on` to ensure the Immich_Namespace exists before any Immich resources are created
