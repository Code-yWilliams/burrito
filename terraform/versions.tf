terraform {
  required_version = ">= 1.6"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  # Terraform state lives in OCI Object Storage via its S3-compatible API.
  # Bucket "burrito-tfstate" (versioned) was created once via the OCI CLI in
  # the tenancy root compartment, outside terraform, to avoid a chicken-and-egg.
  # Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars
  # (an OCI "customer secret key").
  backend "s3" {
    bucket = "burrito-tfstate"
    key    = "terraform.tfstate"
    region = "us-sanjose-1"

    endpoints = {
      s3 = "https://ax9hmp43wxua.compat.objectstorage.us-sanjose-1.oraclecloud.com"
    }

    # OCI's S3 compatibility layer isn't real AWS; skip AWS-specific checks.
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
