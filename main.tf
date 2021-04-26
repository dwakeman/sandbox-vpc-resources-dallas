data "ibm_schematics_workspace" "vpc" {
    workspace_id = var.vpc_schematics_workspace_id
}

data "ibm_schematics_output" "vpc" {
    workspace_id = var.vpc_schematics_workspace_id
    template_id  = data.ibm_schematics_workspace.vpc.runtime_data[0].id
}


data "ibm_resource_group" "app_resource_group" {
    name = var.app_resource_group
}

data "ibm_is_vpc" "vpc1" {
    name = var.vpc_name
}

data "ibm_is_subnet" "app_subnet1" {
    identifier = data.ibm_schematics_output.vpc.output_values.app_subnet1_id
}

data "ibm_is_subnet" "app_subnet2" {
    identifier = data.ibm_schematics_output.vpc.output_values.app_subnet2_id
}

data "ibm_is_subnet" "app_subnet3" {
    identifier = data.ibm_schematics_output.vpc.output_values.app_subnet3_id
}


data "ibm_resource_group" "cos_group" {
  name = var.admin_resource_group
}

data "ibm_resource_instance" "cos_instance" {
  name              = var.cos_registry_instance
  resource_group_id = data.ibm_resource_group.cos_group.id
  service           = "cloud-object-storage"
}

data "ibm_resource_group" "kms_group" {
  name = var.kms_resource_group
}

data "ibm_resource_instance" "kms_instance" {
  name              = var.kms_instance
  resource_group_id = data.ibm_resource_group.kms_group.id
  service           = "kms"
}

locals {
    ocp_01_name = "${var.environment}-ocp-01"
    iks_01_name = "${var.environment}-iks-01"
    zone1       = "${var.region}-1"
    zone2       = "${var.region}-2"
    zone3       = "${var.region}-3"
}


##############################################################################
# Create a customer root key
##############################################################################
resource "ibm_kp_key" "ocp_01_kp_key" {
    key_protect_id = data.ibm_resource_instance.kms_instance.guid
    key_name       = "kube-${local.ocp_01_name}-crk"
    standard_key   = false
}

##############################################################################
# Create OCP Cluster
##############################################################################
resource "ibm_container_vpc_cluster" "app_ocp_cluster_01" {
    name                            = local.ocp_01_name
    vpc_id                          = data.ibm_schematics_output.vpc.output_values.vpc_id
    flavor                          = "bx2.8x32"
    kube_version                    = "4.6_openshift"
    worker_count                    = "1"
    //entitlement                     = "cloud_pak"
    wait_till                       = "MasterNodeReady"
    disable_public_service_endpoint = false
    cos_instance_crn                = data.ibm_resource_instance.cos_instance.id
    resource_group_id               = data.ibm_resource_group.app_resource_group.id
    tags                            = ["env:${var.environment}","vpc:${var.vpc_name}","schematics:${var.schematics_workspace_id}"]
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet1_id
        name      = local.zone1
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet2_id
        name      = local.zone2
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet3_id
        name      = local.zone3
    }

    kms_config {
        instance_id = data.ibm_resource_instance.kms_instance.guid
        crk_id = ibm_kp_key.ocp_01_kp_key.key_id
        private_endpoint = true
    }

    depends_on = [
        ibm_kp_key.ocp_01_kp_key

    ]
}

##############################################################################
# Create Worker Pool for Portworx or Openshift Container Storage (SDS) 
##############################################################################
resource "ibm_container_vpc_worker_pool" "sds_pool" {
    count             = var.install_ocs == "true" ? 1 : 0
    cluster           = ibm_container_vpc_cluster.app_ocp_cluster_01.name
    worker_pool_name  = "sds"
    flavor            = "cx2.16x32"
    vpc_id            = data.ibm_schematics_output.vpc.output_values.vpc_id
    worker_count      = 1
    //entitlement       = "cloud_pak"
    resource_group_id = data.ibm_resource_group.app_resource_group.id

    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet1_id
        name      = local.zone1
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet2_id
        name      = local.zone2
    }
    zones {
        subnet_id = data.ibm_schematics_output.vpc.output_values.app_subnet3_id
        name      = local.zone3
    }

    timeouts {
        create = "30m"
        delete = "30m"
    }

    depends_on = [ibm_container_vpc_cluster.app_ocp_cluster_01]
}



##############################################################################
# Create instance of Cloud Object Storage for use with OCS in OCP Cluster
##############################################################################
resource "ibm_resource_instance" "nooba_store" {
    //count             = var.install_ocs == "true" ? 1 : 0
    name              = "nooba-store-${ibm_container_vpc_cluster.app_ocp_cluster_01.name}"
    service           = "cloud-object-storage"
    plan              = "standard"
    location          = "global"
    resource_group_id = data.ibm_resource_group.app_resource_group.id
    tags              = ["env:${var.environment}",
                         "vpc:${var.vpc_name}",
                         "cluster:${ibm_container_vpc_cluster.app_ocp_cluster_01.id}",
                         "schematics:${var.schematics_workspace_id}"]

    timeouts {
        create = "30m"
        delete = "15m"
    }

    depends_on = [ibm_container_vpc_cluster.app_ocp_cluster_01]
}


##############################################################################
# Create credentials for Cloud Object Storage instance above
##############################################################################
resource "ibm_resource_key" "cos_credentials" {
    //count                = var.install_ocs == "true" ? 1 : 0
    name                 = "${ibm_container_vpc_cluster.app_ocp_cluster_01.name}-creds"
    role                 = "Writer"
    resource_instance_id = ibm_resource_instance.nooba_store.id
    parameters           = { "HMAC" = true }

    depends_on = [ibm_resource_instance.nooba_store]
}

##############################################################################
# Get the configuration file for the cluster created above
##############################################################################
data "ibm_container_cluster_config" "mycluster" {
  cluster_name_id = ibm_container_vpc_cluster.app_ocp_cluster_01.name

  depends_on = [
    ibm_container_vpc_cluster.app_ocp_cluster_01
  ]
}

##############################################################################
# Defines a provider that can connect to the cluster above
##############################################################################
provider "kubernetes" {
  //load_config_file       = "false"
  host                   = data.ibm_container_cluster_config.mycluster.host
  token                  = data.ibm_container_cluster_config.mycluster.token
  //cluster_ca_certificate = data.ibm_container_cluster_config.mycluster.ca_certificate
}


resource "kubernetes_namespace" "ocs" {
    //count = var.install_ocs == "true" ? 1 : 0
    metadata {
      labels = {
        "openshift.io/cluster-monitoring" = "true"
      }
      name = "dw-openshift-storage"
    }
    depends_on = [
      ibm_container_vpc_cluster.app_ocp_cluster_01
    ]
}

resource "kubernetes_secret" "ibm_cloud_cos_credentials" {
  metadata {
    name = "ibm-cloud-cos-creds"
    namespace = "dw-openshift-storage"
  }

  data = {
    IBM_COS_ACCESS_KEY_ID = lookup(ibm_resource_key.cos_credentials.credentials, "cos_hmac_keys.access_key_id")
    IBM_COS_SECRET_ACCESS_KEY = lookup(ibm_resource_key.cos_credentials.credentials, "cos_hmac_keys.secret_access_key")
  }

  type = "Opaque"

  depends_on = [
    ibm_resource_key.cos_credentials
  ]
}
