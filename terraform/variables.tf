variable "tenancy_ocid" {
  description = "OCID of the tenancy (root compartment)"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the IAM user terraform authenticates as"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key"
  type        = string
}

variable "oci_private_key" {
  description = "PEM content of the API signing key (used in CI; mutually exclusive with oci_private_key_path)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oci_private_key_path" {
  description = "Path to the API signing key (used locally; mutually exclusive with oci_private_key)"
  type        = string
  default     = ""
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-sanjose-1"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form; SSH (22) is only open to this"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key installed on the k3s node (personal access)"
  type        = string
}

variable "ci_ssh_public_key" {
  description = "SSH public key for the dedicated CI identity, reached only via the Cloudflare Tunnel (never a broadened NSG rule). Not secret; the matching private key lives in 1Password as CI_SSH_PRIVATE_KEY."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPE40DBooP7feS9JI5Ubo1t8WtFp7TLm6QwORWqe6ou burrito-ci"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Tunnel/Access/DNS edit, Zone read)"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (not secret, just an identifier)"
  type        = string
  default     = "a2307e3c074e5ba8067e3220eeaf53c0"
}

variable "node_ocpus" {
  description = "OCPUs for the k3s node (Always Free A1 allowance is 4 total)"
  type        = number
  default     = 1
}

variable "node_memory_gb" {
  description = "Memory in GB for the k3s node (Always Free A1 allowance is 24 total)"
  type        = number
  default     = 6
}
