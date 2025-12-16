terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

provider "oci" {
  region = "us-ashburn-1"
}

# --- VARIABLES ---

variable "compartment_id" {
  default = "ocid1.tenancy.oc1..aaaaaaaadeivc3duoyx3pffmgzkcv2zo2gyuq2ftxybicrpianpnmeccgeba"
}

variable "ssh_public_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDc/Xc6A4g+2Px5bZ+3OPpR6JwR2/ZHpMKBPlhNcgUOyH+pmHAwOe4dvWGG9K3fmlFgQK/Pq8DeM8lWaC5M6QhW3G+ZsKu/i2t/TDYJ+jApYpcAHCYeW0b8+TTS2UKINwLpl35fIGrjuuTT7yYGZ9K8G7W1+tpVIE2Jx9ltzuUQ/7DnrL7msIytgabFQDJB+nXB64oqUArVNyQhCqRPtLbrNEz9q+857Q16BL8yWwEvMMAwItQU+tTTOErh22cabOkVeG7fbAEx6ZbY14h2LVh3Unq1Bcc6exgQYuyVlwQdX7gkyKc2n/A1nRhWwGLNYgXikItSqBTFhCp7QDm8bNcp ssh-key-2025-11-13"
}

# --- NETWORK ---

resource "oci_core_vcn" "free_k8s_vcn" {
  compartment_id = var.compartment_id
  cidr_block     = "10.0.0.0/16"
  display_name   = "free-k8s-vcn"
}

resource "oci_core_internet_gateway" "free_igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.free_k8s_vcn.id
  display_name   = "free-k8s-igw"
  enabled        = true
}

resource "oci_core_route_table" "free_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.free_k8s_vcn.id
  display_name   = "free-k8s-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.free_igw.id
  }
}

resource "oci_core_security_list" "k8s_public_sl" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.free_k8s_vcn.id
  display_name   = "k8s-public-sl"

# --- NEW RULES START HERE ---

  # Allow HTTP (Port 80) from Anywhere
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # Allow HTTPS (Port 443) from Anywhere
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

# --- NEW RULES END HERE ---

  # Allow K8s API (6443)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Allow SSH (22)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }
  
  # Allow Internal Communication
  ingress_security_rules {
    protocol = "all"
    source   = "10.0.0.0/16"
  }

  # Allow Egress (Internet Access for Nodes)
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# SUBNET 1: For API Endpoint & Load Balancers
resource "oci_core_subnet" "public_subnet" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.free_k8s_vcn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "free-k8s-api-subnet"
  route_table_id    = oci_core_route_table.free_rt.id
  security_list_ids = [oci_core_security_list.k8s_public_sl.id]
}

# SUBNET 2: For Worker Nodes (NEW)
resource "oci_core_subnet" "node_subnet" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.free_k8s_vcn.id
  cidr_block        = "10.0.2.0/24" # Different CIDR
  display_name      = "free-k8s-node-subnet"
  route_table_id    = oci_core_route_table.free_rt.id
  security_list_ids = [oci_core_security_list.k8s_public_sl.id]
}

# --- CLUSTER ---

resource "oci_containerengine_cluster" "k8s_cluster" {
  compartment_id     = var.compartment_id
  kubernetes_version = "v1.34.1"
  name               = "oke-cluster"
  vcn_id             = oci_core_vcn.free_k8s_vcn.id
  type               = "BASIC_CLUSTER"

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.public_subnet.id
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.public_subnet.id]
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
  }
}

# --- NEW POOL (Green: v1.34, 2 Nodes, Split Resources) ---

resource "oci_containerengine_node_pool" "pool_1_34" {
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = var.compartment_id
  kubernetes_version = "v1.34.1"   # <--- New Version
  name               = "pool-canepro"
  node_shape         = "VM.Standard.A1.Flex"

  node_config_details {
    size = 2  # <--- SCALING UP TO 2 NODES

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.node_subnet.id
    }
  }

  node_shape_config {
    # SPLITTING THE RESOURCES (To stay free)
    memory_in_gbs = 12 
    ocpus         = 2
  }

  node_source_details {
    # Terraform will find the Image for v1.34 automatically using the data block below
    image_id    = data.oci_core_images.node_pool_image_1_34.images[0].id
    source_type = "IMAGE"
  }

  ssh_public_key = var.ssh_public_key
}

# Helper to find the v1.34 Image
data "oci_core_images" "node_pool_image_1_34" {
  compartment_id           = var.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# --- DATA HELPERS ---

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

output "connect_command" {
  value = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.k8s_cluster.id} --file $HOME/.kube/config --region us-ashburn-1 --token-version 2.0.0"
}
