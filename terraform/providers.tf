# Auth is explicit (no ~/.oci/config dependency) so the same code runs on a
# laptop and in CI. Locally, terraform.tfvars sets oci_private_key_path; in
# GitHub Actions, TF_VAR_oci_private_key carries the key content directly.
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key      = var.oci_private_key != "" ? var.oci_private_key : null
  private_key_path = var.oci_private_key_path != "" ? var.oci_private_key_path : null
  region           = var.region
}
