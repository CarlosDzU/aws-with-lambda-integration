# 1. Configuración de Logs para API Gateway

resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/apigateway/image-processor-api-${var.environment}"
  retention_in_days = 14
}

# 2. Definición de la API HTTP (v2)

resource "aws_apigatewayv2_api" "http_api" {
  name          = "image-processor-api-${var.environment}"
  protocol_type = "HTTP"
  
  # Habilitación de CORS según los requerimientos del diseño
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

# Configuración del Stage por defecto con despliegue automático habilitado
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  # Configuración de los logs de acceso en formato JSON para análisis
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format          = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }
  
  # Configuración de límites de tráfico (Throttling) establecidos en 10,000 rps
  default_route_settings {
    throttling_burst_limit = 10000
    throttling_rate_limit  = 10000
  }
}

# 3. Integración de API Gateway con la función Lambda

# Configuración del enlace entre el endpoint y la lógica de subida (Payload 2.0)
resource "aws_apigatewayv2_integration" "lambda_upload" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.upload_lambda.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Definición de la ruta específica para la carga de imágenes
resource "aws_apigatewayv2_route" "post_upload" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_upload.id}"
}

# 4. Configuración de Permisos de Invocación

# Permite que el servicio de API Gateway ejecute la función Lambda correspondiente
resource "aws_lambda_permission" "api_gw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# 5. Definición de Salidas (Outputs)

# Endpoint público generado para pruebas de integración con herramientas externas
output "api_url" {
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/upload"
  description = "URL del endpoint público para la subida de archivos"
}