# 1. Configuración de CloudWatch (Logs y Alarmas)

# Grupo de logs para la Lambda de subida (Upload)
resource "aws_cloudwatch_log_group" "upload_log_group" {
  name              = "/aws/lambda/upload-lambda-${var.environment}"
  retention_in_days = 14
}

# Grupo de logs para la Lambda de procesamiento (Crop)
resource "aws_cloudwatch_log_group" "crop_log_group" {
  name              = "/aws/lambda/crop-lambda-${var.environment}"
  retention_in_days = 14
}

# Tópico SNS para la notificación de alertas del sistema
resource "aws_sns_topic" "alarm_topic" {
  name = "dlq-alarm-topic-${var.environment}"
}

# Alarma para monitorear la presencia de mensajes en la Dead Letter Queue (DLQ)
resource "aws_cloudwatch_metric_alarm" "dlq_alarm" {
  alarm_name          = "dlq-messages-alarm-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0 # Se activa si existe cualquier mensaje pendiente en la DLQ
  alarm_description   = "Notifica si hay mensajes que no pudieron ser procesados y terminaron en la DLQ"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
  
  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }
}

# 2. Despliegue de Funciones Lambda

# Función Lambda para la subida de archivos (Upload)
resource "aws_lambda_function" "upload_lambda" {
  function_name = "upload-lambda-${var.environment}"
  role          = aws_iam_role.role_upload.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  memory_size   = 256 
  timeout       = 30

  # Código base temporal (será reemplazado por el despliegue de la aplicación)
  filename         = "${path.module}/../src/upload-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/upload-lambda.zip")

  # Configuración de red: Ejecución dentro de subredes privadas con Security Groups específicos
  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.sg_upload_lambda.id]
  }

  # Definición de variables de entorno necesarias para la lógica de negocio
  environment {
    variables = {
      S3_BUCKET     = aws_s3_bucket.images.bucket
      UPLOAD_PREFIX = "uploads/"
    }
  }

  depends_on = [aws_cloudwatch_log_group.upload_log_group]
}

# Función Lambda para el procesamiento de imágenes (Crop)
resource "aws_lambda_function" "crop_lambda" {
  function_name = "crop-lambda-${var.environment}"
  role          = aws_iam_role.role_crop.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  memory_size   = 512 # Asignación de memoria superior para procesamiento de imágenes
  timeout       = 60

  filename         = "${path.module}/../src/crop-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/crop-lambda.zip")

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.sg_crop_lambda.id]
  }

  environment {
    variables = {
      S3_BUCKET        = aws_s3_bucket.images.bucket
      PROCESSED_PREFIX = "processed/"
    }
  }

  depends_on = [aws_cloudwatch_log_group.crop_log_group]
}

# 3. Integración SQS -> Lambda (Trigger)

# Configuración del disparador para procesar mensajes de SQS en lotes
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn        = aws_sqs_queue.main_queue.arn
  function_name           = aws_lambda_function.crop_lambda.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
}