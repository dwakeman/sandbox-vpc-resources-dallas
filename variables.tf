/*
variable "ssh_key" {
    description = "The name of the SSH key to be used for VSIs"
}

variable "ibmcloud_api_key" {
    description = "A valid API Key for IBM Cloud.  Not needed if using Schematics"
}
*/

variable "region" {
    default = "us-south"
}

variable "generation" {
    default = 2
}

variable "environment" {
    default = "engg"
}

variable "vpc_name" {
    default = "engineering-dallas"
}

variable "vpc_schematics_workspace_id" {
    description = "The schematics workspace ID that provisioned the VPC. Used to get VPC and subnets."
    default = "not-using-schematics"
}

variable "schematics_workspace_id" {
    description = "The id of this schematics workspace.  Used to tag resources."
    default = "not-using-schematics"
}

variable "app_resource_group" {
    description = "The name of the resource group for the App IKS cluster"
}

variable "admin_resource_group" {
    description = "The name of the resource group for the Admin IKS cluster"
    default = "account-admin-services"
}

variable "cos_registry_instance" {
    description = "the name of the COS instance for the Openshift Registry bucket"
    default = "cos-openshift-registry"
}

variable "kms_resource_group" {
    description = "The name of the resource group for the Key Protect or HPCS instance"
    default = "account-shared-services"
}

variable "kms_instance" {
    description = "the name of the Key Protect or HPCS instance where the key will be created"
    default = "key-protect-dallas-dw"

}