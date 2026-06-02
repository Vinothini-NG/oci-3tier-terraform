#CREATE VCN
resource "oci_core_vcn" "main_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "main-vcn-github"
  dns_label      = "main"
}

