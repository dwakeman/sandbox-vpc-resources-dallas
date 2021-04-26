terraform {
  required_version = ">= 0.13"
  required_providers {
    ibm = {
      source  = "ibm-cloud/ibm"
      version = "1.23.2"
    }
  }
}


provider "ibm" {
    //generation = var.generation
    region     = var.region
    //version    = "~> 1.23"

}