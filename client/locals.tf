locals {
  project_name = "windows-dc"
  environment  = "dev"

  tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}
