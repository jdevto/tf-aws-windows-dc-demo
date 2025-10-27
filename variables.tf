variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "windows-dc"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}

variable "one_nat_gateway_per_az" {
  description = "Should be true if you want one NAT Gateway per availability zone. Otherwise, one NAT Gateway will be used for all AZs."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Active Directory domain name (FQDN)"
  type        = string
  default     = "contoso.local"
}

variable "domain_netbios_name" {
  description = "NetBIOS name for the Active Directory domain"
  type        = string
  default     = "CONTOSO"
}

variable "dc_instance_type" {
  description = "EC2 instance type for the domain controller"
  type        = string
  default     = "m6i.large"
}
