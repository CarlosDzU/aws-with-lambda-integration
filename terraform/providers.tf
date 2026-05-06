terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Esto agregará etiquetas sutomaticamente segun se creen los recursos
  default_tags {
    tags = {
      Environment = terraform.workspace
      Project     = "ImageProcessor"
      ManagedBy   = "Terraform"
    }
  }
}