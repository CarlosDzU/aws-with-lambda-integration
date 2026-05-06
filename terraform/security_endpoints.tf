
# 1. Configuración de Grupos de Seguridad

# Grupo de seguridad para la Lambda de subida (Upload)
resource "aws_security_group" "sg_upload_lambda" {
  name        = "sg-upload-lambda-${var.environment}"
  description = "Permite a la Lambda de subida comunicarse con servicios externos"
  vpc_id      = aws_vpc.main.id

  # Regla de salida: Permite tráfico HTTPS (443) hacia el exterior
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-upload-lambda-${var.environment}" }
}

# Grupo de seguridad para la Lambda de recorte (Crop)
resource "aws_security_group" "sg_crop_lambda" {
  name        = "sg-crop-lambda-${var.environment}"
  description = "Permite a la Lambda de procesamiento comunicarse con servicios externos"
  vpc_id      = aws_vpc.main.id

  # Regla de salida: Permite tráfico HTTPS (443) hacia el exterior
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-crop-lambda-${var.environment}" }
}

# Grupo de seguridad para el VPC Endpoint de SQS
resource "aws_security_group" "sg_vpce_sqs" {
  name        = "sg-vpce-sqs-${var.environment}"
  description = "Controla el acceso al endpoint de SQS desde la red privada"
  vpc_id      = aws_vpc.main.id

  # Regla de entrada: Solo permite conexiones HTTPS desde las Lambdas autorizadas
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [
      aws_security_group.sg_upload_lambda.id, 
      aws_security_group.sg_crop_lambda.id
    ]
  }

  tags = { Name = "sg-vpce-sqs-${var.environment}" }
}


# 2. Configuración de VPC Endpoints

# Gateway Endpoint para S3 (Optimización de tráfico interno)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Asociación con las tablas de ruteo de las subredes privadas
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_b.id
  ]

  # Política de acceso: restringida únicamente a operaciones del bucket de imágenes
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = [
          aws_s3_bucket.images.arn,
          "${aws_s3_bucket.images.arn}/*"
        ]
      }
    ]
  })

  tags = { Name = "vpce-s3-${var.environment}" }
}

# Interface Endpoint para SQS
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true 

  # Ubicación del endpoint en las subredes privadas del proyecto
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  # Vinculación con su grupo de seguridad correspondiente
  security_group_ids = [aws_security_group.sg_vpce_sqs.id]

  tags = { Name = "vpce-sqs-${var.environment}" }
}