terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }

  # OCI Object Storage backend (S3-compatible)
  # Bucket must be created first: oci os bucket create --name terraform-state --compartment-id <compartment_id>
  # Configure via backend.hcl or environment variables (TF_VAR_*)
  backend "s3" {
    bucket = "terraform-state"
    key    = "oke-hub/terraform.tfstate"
    region = "us-ashburn-1"
    endpoints = {
      s3 = "https://iducrocaj9h2.compat.objectstorage.us-ashburn-1.oraclecloud.com"
    }
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
    skip_s3_checksum            = true # OCI doesn't support AWS chunked encoding
    # Credentials via AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY env vars
    # or via backend.hcl: access_key = "..." and secret_key = "..."
  }
}

provider "oci" {
  region = "us-ashburn-1"
}

# --- VARIABLES ---

variable "compartment_id" {
  description = "OCI Compartment OCID (set via terraform.tfvars or TF_VAR_compartment_id)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key to inject into worker nodes (set via terraform.tfvars or TF_VAR_ssh_public_key)"
  type        = string
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

# checkov:skip=CKV_OCI_21:Personal portfolio cluster - SSH with key auth only; public SSH ingress intentional
# checkov:skip=CKV_OCI_22:Personal portfolio cluster - public API access intentional
# tfsec:ignore:oci-networking-no-public-ingress-api
# tfsec:ignore:oci-networking-no-public-ingress-ssh
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

  # Allow K8s API (6443) - Personal cluster, public API access intentional
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0" # Personal use - public API access intentional
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Allow SSH (22) - Personal cluster, key-based authentication only; public SSH ingress intentional
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0" # Personal use - key-based auth, no password login
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
  kubernetes_version = "v1.34.1" # <--- New Version
  name               = "pool-canepro"
  node_shape         = "VM.Standard.A1.Flex"

  node_config_details {
    size = 2 # <--- SCALING UP TO 2 NODES

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

  lifecycle {
    ignore_changes = [
      node_source_details[0].image_id,
    ]
  }
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

data "oci_containerengine_cluster_kube_config" "k8s_kube_config" {
  cluster_id    = oci_containerengine_cluster.k8s_cluster.id
  endpoint      = "PUBLIC_ENDPOINT"
  token_version = "2.0.0"
}

output "connect_command" {
  value = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.k8s_cluster.id} --file $HOME/.kube/config --region us-ashburn-1 --token-version 2.0.0"
}

provider "helm" {
  kubernetes = {
    host                   = oci_containerengine_cluster.k8s_cluster.endpoints[0].public_endpoint
    cluster_ca_certificate = base64decode(yamldecode(data.oci_containerengine_cluster_kube_config.k8s_kube_config.content).clusters[0].cluster["certificate-authority-data"])
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "oci"
      args        = ["ce", "cluster", "generate-token", "--cluster-id", oci_containerengine_cluster.k8s_cluster.id]
    }
  }
}
