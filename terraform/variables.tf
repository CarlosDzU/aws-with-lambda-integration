#
variable "aws_region" {
  description = "La region de AWS donde se desplegara el sistema"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "El entorno actual (dev, qa, prod)"
  type        = string
}

variable "bucket_suffix" {
  description = "Sufijo unico para el bucket S3"
  type        = string
}