resource "oci_core_vcn" "burrito" {
  compartment_id = oci_identity_compartment.burrito.id
  display_name   = "burrito-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "burrito"
}

resource "oci_core_internet_gateway" "burrito" {
  compartment_id = oci_identity_compartment.burrito.id
  vcn_id         = oci_core_vcn.burrito.id
  display_name   = "burrito-igw"
}

resource "oci_core_route_table" "burrito" {
  compartment_id = oci_identity_compartment.burrito.id
  vcn_id         = oci_core_vcn.burrito.id
  display_name   = "burrito-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.burrito.id
  }
}

# Intentionally empty: security lists apply subnet-wide and would overlap with
# the NSG below. An empty list makes the NSG the single source of truth.
resource "oci_core_security_list" "empty" {
  compartment_id = oci_identity_compartment.burrito.id
  vcn_id         = oci_core_vcn.burrito.id
  display_name   = "burrito-sl-empty"
}

resource "oci_core_subnet" "burrito" {
  compartment_id    = oci_identity_compartment.burrito.id
  vcn_id            = oci_core_vcn.burrito.id
  display_name      = "burrito-subnet"
  cidr_block        = "10.0.1.0/24"
  dns_label         = "pub"
  route_table_id    = oci_core_route_table.burrito.id
  security_list_ids = [oci_core_security_list.empty.id]
}

resource "oci_core_network_security_group" "node" {
  compartment_id = oci_identity_compartment.burrito.id
  vcn_id         = oci_core_vcn.burrito.id
  display_name   = "burrito-nsg"
}

resource "oci_core_network_security_group_security_rule" "ssh" {
  network_security_group_id = oci_core_network_security_group.node.id
  description               = "SSH from my IP only"
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.my_ip_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

# No k8s API (6443) ingress rule: CI reaches the API via SSH port-forward
# through the Cloudflare Tunnel (see terraform/cloudflare.tf), and local
# kubectl uses the same forward over direct SSH (scripts/fetch-kubeconfig.sh).

resource "oci_core_network_security_group_security_rule" "http" {
  network_security_group_id = oci_core_network_security_group.node.id
  description               = "HTTP to Traefik ingress"
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "https" {
  network_security_group_id = oci_core_network_security_group.node.id
  description               = "HTTPS to Traefik ingress"
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "egress_all" {
  network_security_group_id = oci_core_network_security_group.node.id
  description               = "Allow all egress"
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}
