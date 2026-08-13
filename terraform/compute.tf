data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "k3s" {
  compartment_id      = oci_identity_compartment.burrito.id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "burrito-k3s"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.burrito.id
    display_name     = "burrito-k3s-vnic"
    hostname_label   = "k3s"
    nsg_ids          = [oci_core_network_security_group.node.id]
    assign_public_ip = false # a reserved (stable) public IP is attached below instead
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  preserve_boot_volume = false

  lifecycle {
    # A newer Ubuntu image being published must not force node replacement.
    ignore_changes = [source_details]
  }
}

# Attach a reserved public IP to the instance's primary private IP, so the
# address survives instance recreation.
data "oci_core_vnic_attachments" "k3s" {
  compartment_id = oci_identity_compartment.burrito.id
  instance_id    = oci_core_instance.k3s.id
}

data "oci_core_private_ips" "k3s" {
  vnic_id = data.oci_core_vnic_attachments.k3s.vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "k3s" {
  compartment_id = oci_identity_compartment.burrito.id
  display_name   = "burrito-k3s-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.k3s.private_ips[0].id
}
