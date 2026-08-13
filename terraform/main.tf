resource "oci_identity_compartment" "burrito" {
  name           = "burrito"
  description    = "Compartment for the burrito project"
  compartment_id = var.tenancy_ocid
  enable_delete  = true
}
