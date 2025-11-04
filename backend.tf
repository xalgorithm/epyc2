# Terraform Backend Configuration
# Stores state on NFS mount at 192.168.0.7:/data/kubernetes/terraform-state
#
# Mount paths (automatically set by setup script):
#   macOS:  /Volumes/nfs-k8s/terraform-state/terraform.tfstate
#   Linux:  /mnt/nfs-k8s/terraform-state/terraform.tfstate

# Comment out to disable NFS backend and use local state
terraform {
  backend "local" {
    # macOS path
    path = "/Volumes/nfs-k8s/terraform-state/terraform.tfstate"

    # Linux path (uncomment if on Linux):
    # path = "/mnt/nfs-k8s/terraform-state/terraform.tfstate"
  }
}

# Note: Before running terraform init, ensure NFS is mounted:
#   Run: sudo ./scripts/deployment/setup-nfs-backend.sh

