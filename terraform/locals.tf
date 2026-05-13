########################################################################
# locals.tf — shared values used across all resources
########################################################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = "hybrid"
    ManagedBy   = "terraform"
  }
}
