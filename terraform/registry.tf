resource "oci_artifacts_container_repository" "app" {
  compartment_id = oci_identity_compartment.burrito.id
  display_name   = "burrito/app"
  is_public      = false
}
