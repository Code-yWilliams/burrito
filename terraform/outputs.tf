data "oci_objectstorage_namespace" "ns" {}

output "node_public_ip" {
  description = "Reserved public IP of the k3s node"
  value       = oci_core_public_ip.k3s.ip_address
}

output "compartment_id" {
  value = oci_identity_compartment.burrito.id
}

output "image_repo" {
  description = "Full OCIR path for the app image"
  value       = "sjc.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/${oci_artifacts_container_repository.app.display_name}"
}

output "api_url" {
  description = "Public HTTPS URL of the API (Cloudflare Tunnel -> Traefik)"
  value       = "https://${local.api_hostname}"
}

output "web_url" {
  description = "Public HTTPS URL of the frontend (Cloudflare Pages)"
  value       = "https://${local.web_hostname}"
}

output "fetch_kubeconfig" {
  description = "Command to fetch a working kubeconfig from the node"
  value       = "scripts/fetch-kubeconfig.sh ${oci_core_public_ip.k3s.ip_address}"
}
