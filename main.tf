##### Versions #####
terraform {
    required_version = ">=1.2.6"
    required_providers {
        ibm = {
        source           = "IBM-Cloud/ibm"
        version          = ">= 1.48.0"
        }
    }
}

provider "ibm" {
    ibmcloud_api_key = var.ibmcloud_api_key
}

##### Variables #####

variable "ibmcloud_api_key" {
    description = "IBM Cloud API key"
    type        = string
    default     = ""
}

variable "resource_group" {
    description = "Existing resource group name"
    type        = string
    default     = "nrt-lop-veeam-testing"
}

variable "kms_resource_instance_name" {
    description = "The name of the Key Protect instance"
    type        = string
    default     = "nrt-veeam-testing"
}

variable "kms_resource_instance_region" {
    description = "The region where Key Protect instance is to be deployed"
    type        = string
    default     = "eu-de"
}

variable "kms_resource_instance_tags" {
    description = "List of tags for the Key Protect instance"
    type        = list(string)
    default     = ["owner:nrt", "env:nrt-veeam-testing"]
}

variable "kms_resource_instance_service_endpoints" {
    description = "Allow Key Protect service requests through both private and public networks or private only"
    type        = string
    default     = "public-and-private"
}

variable "kms_key_name" {
    description = "Name of the encryption key"
    type        = string
    default     = "root-key-1"
}

variable "tracking_resource_instance_name" {
    description = "The name of the resource instance for tracking"
    type        = string
    default     = "nrt-veeam-testing"
}

variable "tracking_resource_instance_region" {
    description = "The region where tracking instance is to be deployed"
    type        = string
    default     = "eu-de"
}

variable "tracking_resource_instance_tags" {
    description = "List of tags for the tracking resource instance"
    type        = list(string)
    default     = ["owner:nrt", "env:nrt-veeam-testing"]
}

variable "tracking_resource_instance_plan" {
    description = "The plan for the tracking resource instance"
    type        = string
    default     = "30-day"
}

variable "tracking_key_name" {
    description = "The name for the tracking ingestion key"
    type        = string
    default     = "access-key"
}

variable "monitoring_resource_instance_name" {
    description = "The name of the resource instance for monitoring"
    type        = string
    default     = "nrt-veeam-testing"
}

variable "monitoring_resource_instance_region" {
    description = "The region where the monitoring instance is to be deployed"
    type        = string
    default     = "eu-de"
}

variable "monitoring_resource_instance_tags" {
    description = "List of tags for the monitoring resource instance"
    type        = list(string)
    default     = ["owner:nrt", "env:nrt-veeam-testing"]
}

variable "monitoring_resource_instance_plan" {
    description = "The plan for the monitoring resource instance"
    type        = string
    default     = "graduated-tier"
}

variable "monitoring_key_name" {
    description = "The name for the monitoring ingestion key"
    type        = string
    default     = "access-key"
}

variable "cos_resource_instance_name" {
    description = "Name of the IBM Cloud Object Storage instance"
    type        = string
    default     = "nrt-veeam-testing"
}

variable "cos_resource_instance_tags" {
    description = "List of tags for the IBM Cloud Object Storage instance"
    type        = list(string)
    default     = ["owner:nrt", "env:nrt-veeam-testing"]
}

variable "cos_bucket_name" {
    description = "Name of IBM COS bucket"
    type        = string
    default     = "nrt-veeam-testing-bucket-01"
}

variable "cos_bucket_type" {
    description = "One of cross_regional, regional or single_site"
    type        = string
    default     = "regional"
}

variable "cos_location" {
    description = "Location of the IBM COS bucket"
    type        = string
    default     = "eu-de"
}

variable "cos_storage_class" {
    description = "Class of the IBM COS bucket"
    type        = string
    default     = "smart"
}

variable "cos_endpoint_type" {
    description = "Endpoint type of the IBM COS bucket"
    type        = string
    default     = "public"
}

variable "cos_allowed_ips" {
    description = "IPs allowed to access the bucket e.g. the Veeam server or null"
    type        = list(string)
    default     = null #["10.10.10.10"]
}

##### Get the resourcegroup ID #####

data "ibm_resource_group" "resource_group" {
    name = var.resource_group
}

##### Create Activity Tracker and Monitoring instances with keys for COS #####

resource "ibm_resource_instance" "activity_tracker" {
    name              = var.tracking_resource_instance_name
    service           = "logdnaat"
    plan              = var.tracking_resource_instance_plan
    location          = var.tracking_resource_instance_region
    resource_group_id = data.ibm_resource_group.resource_group.id
    tags              = var.tracking_resource_instance_tags
}

resource ibm_resource_key tracking_key {
    name                 = var.tracking_key_name
    role                 = "Manager"
    resource_instance_id = ibm_resource_instance.activity_tracker.id
}

resource ibm_resource_instance monitoring {
    name              = var.monitoring_resource_instance_name
    service           = "sysdig-monitor"
    plan              = var.monitoring_resource_instance_plan
    location          = var.monitoring_resource_instance_region
    resource_group_id = data.ibm_resource_group.resource_group.id
    tags              = var.monitoring_resource_instance_tags
}

resource ibm_resource_key monitoring_key {
    name                 = var.monitoring_key_name
    role                 = "Writer"
    resource_instance_id = ibm_resource_instance.monitoring.id
}

##### Create Key Protect instance and Root Key #####

resource "ibm_resource_instance" "kms" {
    name              = var.kms_resource_instance_name
    service           = "kms"
    plan              = "tiered-pricing"
    location          = var.kms_resource_instance_region
    service_endpoints = var.kms_resource_instance_service_endpoints
    resource_group_id = data.ibm_resource_group.resource_group.id
    tags              = var.kms_resource_instance_tags
}

resource "ibm_kms_key" "key" {
    instance_id  = ibm_resource_instance.kms.guid
    key_name     = var.kms_key_name
    standard_key = false
    force_delete = true
}

##### Create COS instance #####

resource ibm_resource_instance cos_instance {
    name              = var.cos_resource_instance_name
    resource_group_id = data.ibm_resource_group.resource_group.id
    service           = "cloud-object-storage"
    plan              = "standard"
    location          = "global"
    tags              = var.cos_resource_instance_tags
}

##### Create authorization to enable COS access to KMS #####

resource "ibm_iam_authorization_policy" "kms_policy" {
    source_service_name         = "cloud-object-storage"
    source_resource_instance_id = ibm_resource_instance.cos_instance.id
    target_service_name         = "kms"
    target_resource_instance_id = ibm_resource_instance.kms.id
    roles                       = ["Reader"]
}

##### Create COS Bucket and Service Credentials with HMAC #####

resource ibm_cos_bucket bucket {
    bucket_name           = var.cos_bucket_name
    resource_instance_id  = ibm_resource_instance.cos_instance.id
    cross_region_location = var.cos_bucket_type == "cross_regional" ? var.cos_location : null
    region_location       = var.cos_bucket_type == "regional" ? var.cos_location : null
    single_site_location  = var.cos_bucket_type == "single_site" ? var.cos_location : null
    storage_class         = var.cos_storage_class
    endpoint_type         = var.cos_endpoint_type
    key_protect           = ibm_kms_key.key.crn
    activity_tracking {
        read_data_events     = true
        write_data_events    = true
        activity_tracker_crn = ibm_resource_instance.activity_tracker.id
    }
    metrics_monitoring {
        usage_metrics_enabled   = true
        request_metrics_enabled = true
        metrics_monitoring_crn  = ibm_resource_instance.monitoring.crn
    }
    allowed_ip = var.cos_allowed_ips
}

resource ibm_resource_key writer_key {
    name                 = "cos-bucket-writer-key"
    resource_instance_id = ibm_resource_instance.cos_instance.id
    parameters           = { "HMAC" = true }
    role                 = "Writer"
}

##### Outputs ######

output "cos_hmac_keys_access_key" {
  description = "COS Access Key"
  value       = nonsensitive(ibm_resource_key.writer_key.credentials["cos_hmac_keys.access_key_id"])
}

output "cos_hmac_keys_secret_access_key" {
  description = "COS Secret Access Key"
  value       = nonsensitive(ibm_resource_key.writer_key.credentials["cos_hmac_keys.secret_access_key"])
}

output "cos_url_private" {
  description = "COS URL for the private endpoint"
  value       = ibm_cos_bucket.bucket.s3_endpoint_private
}

output "cos_bucket_name" {
  description = "COS bucket name"
  value       = ibm_cos_bucket.bucket.bucket_name
}
