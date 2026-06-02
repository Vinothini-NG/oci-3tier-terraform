#CREATE VCN
resource "oci_core_vcn" "main_vcn_github" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "main-vcn-github"
  dns_label      = "main"
}

#PUPLIC SUBNET CREATION STEPS
#CREATE INTERNET GATEWAY
resource "oci_core_internet_gateway" "main_igw_github" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn_github.id
  display_name   = "internet-gw-tf-github"
  enabled        = true
}

#CREATE PUBLIC-ROUTE-TABLE FOR GATEWAY
resource "oci_core_route_table" "public_rt_github" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn_github.id
  display_name   = "publicRT-tf-github"

  # ADD RULES FOR THAT PUBLIC-ROUTE-TABLE
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main_igw_github.id
  }
}

# ADDING PUBLIC-SECURITYLIST AND THEIR INGRESS AND EGRESS RULES
resource "oci_core_security_list" "public_security_list_github" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn_github.id
  display_name   = "public-security-list-tf-github"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1"

    icmp_options {
      type = 3
    }
  }
  # Allow HTTP traffic to Load Balancer
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"

    tcp_options {
      min = 80
      max = 80
    }
  }
}

#CREATING PUBLIC-SUBNET
resource "oci_core_subnet" "public_subnet_github" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main_vcn_github.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "public-subnet-tf-github"
  dns_label                  = "publicsubnet"
  prohibit_public_ip_on_vnic = false

  route_table_id = oci_core_route_table.public_rt_github.id

  security_list_ids = [
    oci_core_security_list.public_security_list_github.id
  ]
}

#CREATE BASTION HOST
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = "VM.Standard.E5.Flex"

  sort_by    = "TIMECREATED"
  sort_order = "DESC"
}

resource "oci_core_instance" "bastion_host_github" {
  availability_domain = "eaWm:AP-SYDNEY-1-AD-1"
  compartment_id      = var.compartment_ocid
  display_name        = "bastion-host-tf-github"
  shape               = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet_github.id
    assign_public_ip = true
    display_name     = "bastion-vnic"
    hostname_label   = "bastionhost"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  metadata = {
    ssh_authorized_keys = file("${path.module}/id_rsa.pub")
  }
}

#CREATE PRIVATE SUBNET
#CREATING NAT GATEWAY
resource "oci_core_nat_gateway" "private_nat_gateway_github" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn_github.id
  display_name   = "private-nat-gateway-tf-github"
}

#CREATING SERVICE GATEWAY
resource "oci_core_service_gateway" "service_gateway_github" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn_github.id
  display_name   = "service-gateway-tf-github"

  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }
}

data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

#CREATING PRIVATE ROUTE TABLE
resource "oci_core_route_table" "private_rt_github" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn_github.id
  display_name   = "privateRT-tf-github"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.private_nat_gateway_github.id
  }

  route_rules {
    destination       = lookup(data.oci_core_services.all_services.services[0], "cidr_block")
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.service_gateway_github.id
  }
}

#CREATE SECURITYLIST
resource "oci_core_security_list" "private_security_list_github" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn_github.id
  display_name   = "private-security-list-tf-github"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "10.0.0.0/16"
    protocol = "6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source   = "10.0.0.0/16"
    protocol = "1"

    icmp_options {
      type = 3
    }
  }

  ingress_security_rules {
    source   = "10.0.0.0/16"
    protocol = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }
}

#CREATE PRIVATE SUBNET
resource "oci_core_subnet" "private_subnet_github" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main_vcn_github.id
  cidr_block                 = "10.0.2.0/24"
  display_name               = "private-subnet-tf-github"
  dns_label                  = "privatesubnet"
  prohibit_public_ip_on_vnic = true

  route_table_id = oci_core_route_table.private_rt_github.id

  security_list_ids = [
    oci_core_security_list.private_security_list_github.id
  ]
}

#CREATING APPLICATION NODE1
resource "oci_core_instance" "application_node1_github" {
  availability_domain = "eaWm:AP-SYDNEY-1-AD-1"
  compartment_id      = var.compartment_ocid
  display_name        = "application-node1-tf-github"
  shape               = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private_subnet_github.id
    assign_public_ip = false
    display_name     = "application-vnic"
    hostname_label   = "appnode1"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  metadata = {
    ssh_authorized_keys = file("${path.module}/id_rsa.pub")
  }
}

# CREATE AUTONOMOUS DATABASE
resource "oci_database_autonomous_database" "autonomous_db_tf_github" {
  compartment_id = var.compartment_ocid
  display_name   = "autonomous_db_tf_github_v2"
  db_name        = "MYAUTONOMOUSDBTFGITHUB2"
  db_workload    = "OLTP"
  admin_password = "Oracle123456"
  is_free_tier   = true
}

# DOWNLOAD AUTONOMOUS DB WALLET
resource "oci_database_autonomous_database_wallet" "adb_wallet_github" {
  autonomous_database_id = oci_database_autonomous_database.autonomous_db_tf_github.id
  password               = "Oracle@123456"
  base64_encode_content  = true
}

# SAVE WALLET ZIP LOCALLY
resource "local_file" "wallet_zip_github" {
  filename       = "${path.module}/wallet.zip"
  content_base64 = oci_database_autonomous_database_wallet.adb_wallet_github.content
}

# GET OBJECT STORAGE NAMESPACE

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# CREATE OBJECT STORAGE BUCKET

resource "oci_objectstorage_bucket" "tf_bucket_github" {
  compartment_id = var.compartment_ocid
  name           = "terraform-bucket-tf-github-v1"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}

resource "oci_objectstorage_object" "wallet_upload_github" {
  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.tf_bucket_github.name
  object    = "wallet.zip"

  source = "${path.module}/wallet.zip"

  depends_on = [local_file.wallet_zip_github]
}

# CREATE PRE-AUTHENTICATED REQUEST (PAR)

resource "oci_objectstorage_preauthrequest" "wallet_par_github" {
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  bucket       = oci_objectstorage_bucket.tf_bucket_github.name
  name         = "wallet-par-github"
  access_type  = "ObjectRead"
  object_name  = oci_objectstorage_object.wallet_upload_github.object
  time_expires = "2030-12-31T23:59:59Z"
}

# STORE PAR URL IN TXT FILE

resource "local_file" "par_url_file" {
  filename = "C:/terraform/oci-3tier/par-url.txt"
  content  = "https://objectstorage.ap-sydney-1.oraclecloud.com${oci_objectstorage_preauthrequest.wallet_par_github.access_uri}"
}

# CREATE LOAD BALANCER
resource "oci_load_balancer_load_balancer" "load_balancer_tf_gitgub" {
  compartment_id = var.compartment_ocid
  display_name   = "load-balancer-tf-github"
  shape          = "flexible"
  is_private     = false

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }

  subnet_ids = [
    oci_core_subnet.public_subnet_github.id
  ]
}

# CREATE BACKEND SET
resource "oci_load_balancer_backend_set" "lb_backend_set_github" {
  load_balancer_id = oci_load_balancer_load_balancer.load_balancer_tf_gitgub.id
  name             = "lb-backend-set-tf-github"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "HTTP"
    port              = 80
    url_path          = "/"
    return_code       = 200
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}

# ADD APPLICATION NODE1 AS BACKEND
resource "oci_load_balancer_backend" "lb_backend_node1_github" {
  load_balancer_id = oci_load_balancer_load_balancer.load_balancer_tf_gitgub.id
  backendset_name  = oci_load_balancer_backend_set.lb_backend_set_github.name
  ip_address       = oci_core_instance.application_node1_github.private_ip
  port             = 80
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

# CREATE HTTP LISTENER
resource "oci_load_balancer_listener" "lb_listener_http_github" {
  load_balancer_id         = oci_load_balancer_load_balancer.load_balancer_tf_gitgub.id
  name                     = "lb-listener-http-tf-github"
  default_backend_set_name = oci_load_balancer_backend_set.lb_backend_set_github.name
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 60
  }
}

# OUTPUT LOAD BALANCER PUBLIC IP
output "load_balancer_public_ip" {
  value = oci_load_balancer_load_balancer.load_balancer_tf_gitgub.ip_address_details[0].ip_address
}

#CREATING NULL RESOURCE
