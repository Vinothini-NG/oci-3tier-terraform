#CREATE VCN
resource "oci_core_vcn" "main_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "main-vcn"
  dns_label      = "main"
}

#PUPLIC SUBNET CREATION STEPS
#CREATE INTERNET GATEWAY
resource "oci_core_internet_gateway" "main_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "internet-gw-tf"
  enabled        = true
}

#CREATE PUBLIC-ROUTE-TABLE FOR GATEWAY
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "publicRT-tf"

  # ADD RULES FOR THAT PUBLIC-ROUTE-TABLE
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main_igw.id
  }
}

# ADDING PUBLIC-SECURITYLIST AND THEIR INGRESS AND EGRESS RULES
resource "oci_core_security_list" "public_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "public-security-list-tf"

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
resource "oci_core_subnet" "public_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main_vcn.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "public-subnet-tf"
  dns_label                  = "publicsubnet"
  prohibit_public_ip_on_vnic = false

  route_table_id = oci_core_route_table.public_rt.id

  security_list_ids = [
    oci_core_security_list.public_security_list.id
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

resource "oci_core_instance" "bastion_host" {
  availability_domain = "eaWm:AP-SYDNEY-1-AD-1"
  compartment_id      = var.compartment_ocid
  display_name        = "bastion-host-tf"
  shape               = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
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
resource "oci_core_nat_gateway" "private_nat_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "private-nat-gateway-tf"
}

#CREATING SERVICE GATEWAY
resource "oci_core_service_gateway" "service_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "service-gateway-tf"

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
resource "oci_core_route_table" "private_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "privateRT-tf"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.private_nat_gateway.id
  }

  route_rules {
    destination       = lookup(data.oci_core_services.all_services.services[0], "cidr_block")
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.service_gateway.id
  }
}

#CREATE SECURITYLIST
resource "oci_core_security_list" "private_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "private-security-list-tf"

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
resource "oci_core_subnet" "private_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main_vcn.id
  cidr_block                 = "10.0.2.0/24"
  display_name               = "private-subnet-tf"
  dns_label                  = "privatesubnet"
  prohibit_public_ip_on_vnic = true

  route_table_id = oci_core_route_table.private_rt.id

  security_list_ids = [
    oci_core_security_list.private_security_list.id
  ]
}

#CREATING APPLICATION NODE1
resource "oci_core_instance" "application_node1" {
  availability_domain = "eaWm:AP-SYDNEY-1-AD-1"
  compartment_id      = var.compartment_ocid
  display_name        = "application-node1-tf"
  shape               = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private_subnet.id
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
resource "oci_database_autonomous_database" "autonomous_db_tf" {
  compartment_id = var.compartment_ocid
  display_name   = "autonomous_db_tf"
  db_name        = "MYAUTONOMOUSDBTF"
  db_workload    = "OLTP"
  admin_password = "Oracle123456"
  is_free_tier   = true
}

# DOWNLOAD AUTONOMOUS DB WALLET
resource "oci_database_autonomous_database_wallet" "adb_wallet" {
  autonomous_database_id = oci_database_autonomous_database.autonomous_db_tf.id
  password               = "Oracle@123456"
  base64_encode_content  = true
}

# SAVE WALLET ZIP LOCALLY
resource "local_file" "wallet_zip" {
  filename       = "${path.module}/wallet.zip"
  content_base64 = oci_database_autonomous_database_wallet.adb_wallet.content
}

# CREATE OBJECT STORAGE BUCKET

resource "oci_objectstorage_bucket" "tf_bucket" {
  compartment_id = var.compartment_ocid
  name           = "terraform-bucket-tf"
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}

resource "oci_objectstorage_object" "wallet_upload" {
  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.tf_bucket.name
  object    = "wallet.zip"

  source = "${path.module}/wallet.zip"

  depends_on = [local_file.wallet_zip]
}

# GET OBJECT STORAGE NAMESPACE

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# CREATE PRE-AUTHENTICATED REQUEST (PAR)

resource "oci_objectstorage_preauthrequest" "wallet_par" {
  namespace    = data.oci_objectstorage_namespace.ns.namespace
  bucket       = oci_objectstorage_bucket.tf_bucket.name
  name         = "wallet-par"
  access_type  = "ObjectRead"
  object_name  = oci_objectstorage_object.wallet_upload.object
  time_expires = "2030-12-31T23:59:59Z"
}

# STORE PAR URL IN TXT FILE

resource "local_file" "par_url_file" {
  filename = "C:/terraform/oci-3tier/par-url.txt"
  content  = "https://objectstorage.ap-sydney-1.oraclecloud.com${oci_objectstorage_preauthrequest.wallet_par.access_uri}"
}

# CREATE LOAD BALANCER
resource "oci_load_balancer_load_balancer" "load_balancer_tf" {
  compartment_id = var.compartment_ocid
  display_name   = "load-balancer-tf"
  shape          = "flexible"
  is_private     = false

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }

  subnet_ids = [
    oci_core_subnet.public_subnet.id
  ]
}

# CREATE BACKEND SET
resource "oci_load_balancer_backend_set" "lb_backend_set" {
  load_balancer_id = oci_load_balancer_load_balancer.load_balancer_tf.id
  name             = "lb-backend-set-tf"
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
resource "oci_load_balancer_backend" "lb_backend_node1" {
  load_balancer_id = oci_load_balancer_load_balancer.load_balancer_tf.id
  backendset_name  = oci_load_balancer_backend_set.lb_backend_set.name
  ip_address       = oci_core_instance.application_node1.private_ip
  port             = 80
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

# CREATE HTTP LISTENER
resource "oci_load_balancer_listener" "lb_listener_http" {
  load_balancer_id         = oci_load_balancer_load_balancer.load_balancer_tf.id
  name                     = "lb-listener-http-tf"
  default_backend_set_name = oci_load_balancer_backend_set.lb_backend_set.name
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 60
  }
}

# OUTPUT LOAD BALANCER PUBLIC IP
output "load_balancer_public_ip" {
  value = oci_load_balancer_load_balancer.load_balancer_tf.ip_address_details[0].ip_address
}

#CREATING NULL RESOURCE


#STOP APPLICATION NODE1
resource "null_resource" "stop_application_node1" {
  depends_on = [oci_core_instance.application_node1]

  provisioner "local-exec" {
    command = "oci compute instance action --instance-id ${oci_core_instance.application_node1.id} --action STOP"
  }
}

#CREATE CUSTOM IMAGE FOR APPLICATION NODE1
resource "oci_core_image" "application_node1_custom_image" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.application_node1.id
  display_name   = "application-node1-custom-image-tf"

  launch_mode = "NATIVE"

  timeouts {
    create = "60m"
  }
}

#START THE STOPPED APPLICATION NODE1 TF
resource "null_resource" "start_application_node1" {
  depends_on = [oci_core_image.application_node1_custom_image]

  provisioner "local-exec" {
    command = "oci compute instance action --instance-id ${oci_core_instance.application_node1.id} --action START"
  }
}

#CREATING APPLICATION NODE2 TF
resource "oci_core_instance" "application_node2" {

  compartment_id      = var.compartment_ocid
  availability_domain = "eaWm:AP-SYDNEY-1-AD-1"
  display_name        = "application-node2-tf"
  shape               = "VM.Standard.E5.Flex"
  shape_config {
    ocpus         = 1
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private_subnet.id
    assign_public_ip = false
    display_name     = "app-node2-vnic"
    hostname_label   = "appnode2"
  }

  source_details {
    source_type = "image"

    source_id = oci_core_image.application_node1_custom_image.id
  }

  metadata = {
    ssh_authorized_keys = file("${path.module}/id_rsa.pub")
  }

  depends_on = [
    oci_core_image.application_node1_custom_image
  ]
}

# ADD APPLICATION NODE2 AS BACKEND
resource "oci_load_balancer_backend" "lb_backend_node2" {
  load_balancer_id = oci_load_balancer_load_balancer.load_balancer_tf.id
  backendset_name  = oci_load_balancer_backend_set.lb_backend_set.name

  ip_address = oci_core_instance.application_node2.private_ip
  port       = 80

  backup  = false
  drain   = false
  offline = false
  weight  = 1
}
