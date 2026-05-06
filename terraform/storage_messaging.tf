# storage_messaging.tf

# 1. SQS: COLAS DE MENSAJERÍA

# Cola de mensajes fallidos 
resource "aws_sqs_queue" "dlq" {
  name                      = "image-processor-${var.environment}-image-dlq"
  message_retention_seconds = 1209600 # Retención de 14 días
}

# Cola principal para procesamiento de imágenes
resource "aws_sqs_queue" "main_queue" {
  name                       = "image-processor-${var.environment}-image-queue"
  visibility_timeout_seconds = 360   # Margen de visibilidad (6x timeout de Lambda)
  message_retention_seconds  = 86400 # Retención de 1 día
  receive_wait_time_seconds  = 20    # Optimización mediante Long Polling
  
  # Redirección a DLQ tras 3 intentos fallidos
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# Política de acceso para permitir que S3 envíe mensajes a SQS
resource "aws_sqs_queue_policy" "main_queue_policy" {
  queue_url = aws_sqs_queue.main_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main_queue.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_s3_bucket.images.arn }
        }
      }
    ]
  })
}

# 2. S3: ALMACENAMIENTO DE OBJETOS

# Bucket principal para imágenes
resource "aws_s3_bucket" "images" {
  bucket = "image-processor-${var.environment}-images-${var.bucket_suffix}"
}

# Bloqueo estricto de acceso público
resource "aws_s3_bucket_public_access_block" "images_private" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Control de versiones
resource "aws_s3_bucket_versioning" "images_versioning" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration { status = "Enabled" }
}

# Cifrado del lado del servidor (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "images_encryption" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Reglas de ciclo de vida para optimización de almacenamiento
resource "aws_s3_bucket_lifecycle_configuration" "images_lifecycle" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "expire-uploads"
    status = "Enabled"
    filter { prefix = "uploads/" }
    expiration { days = 30 }
  }

  rule {
    id     = "expire-processed"
    status = "Enabled"
    filter { prefix = "processed/" }
    expiration { days = 90 }
  }
}

# 3. CONFIGURACIÓN DE NOTIFICACIONES

# Disparador para notificar a SQS sobre nuevos objetos en uploads/
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.images.id

  queue {
    queue_arn     = aws_sqs_queue.main_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }
  
  # Dependencia explícita para asegurar la existencia de la política de SQS
  depends_on = [aws_sqs_queue_policy.main_queue_policy]
}