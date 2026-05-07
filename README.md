# AWS Image Processor: Integración S3 + SQS + Lambda

Este repositorio contiene una infraestructura completa como código (Terraform) y el código de aplicación (Node.js) para un sistema serverless de procesamiento de imágenes. El sistema permite subir imágenes a través de un API Gateway, almacenarlas en S3, y procesarlas automáticamente (recorte circular 40x40) mediante una arquitectura basada en eventos.

# Herramientas a utilizar

Para desplegar y trabajar en este proyecto, necesitarás:

*   **Node.js v20.x** (En este caso fue gestionado con **NVM**)
*   **Terraform** 
*   **AWS CLI** 
*   **Zip** (para empaquetar las funciones Lambda)
*   **curl** (para subir las imagenes)

# Modificaciones al Diagrama 

Aunque esta basado en el `architecture.mermaid`, se aplicaron varias modificaciones:

1.  **S3 Gateway Endpoint:** Se añadió un endpoint de tipo Gateway para S3. Esto permite que las Lambdas (en subredes privadas) se comuniquen con el bucket S3 sin salir a internet y aws no cobre por el tráfico de datos (no tengo dinero).
2.  **HTTP API v2:** Se optó por la versión 2 de API Gateway. Es más rápida, moderna y mucho más económica que la REST API tradicional.
3.  **Batch Processing:** La integración SQS -> Lambda está configurada con un `batch_size` de 5 y `ReportBatchItemFailures` para un manejo de errores más robusto.

# Reducción de Costos

Este diseño está optimizado para mantener la factura de AWS lo más baja posible:


*   **Dodge del NAT Gateway:** El tráfico de imágenes (que puede ser pesado) viaja a través del **S3 Gateway Endpoint**. Esto evita el cargo de **$0.045 por GB** procesado por el NAT Gateway.
*   **Ciclos de Vida (Lifecycle):** Las imágenes originales se eliminan a los 30 días y las procesadas a los 90 días, evitando costos de almacenamiento infinito.
*   **SQS Native Integration:** Al usar notificaciones nativas de S3 a SQS, no pagas por Lambdas interconectadas que solo mueven datos.

# Flujo de Trabajo

Sigue estos pasos desde que clonas el repositorio para poner todo en marcha:

### 1. Configuración del Entorno Node.js
Primero, asegúrate de tener la versión correcta de Node:

```bash
source ~/.bashrc
nvm install 20
nvm use 20
```

### 2. Instalación de Dependencias y Empaquetado
Debemos instalar las librerías necesarias en cada carpeta de las Lambdas y crear los archivos `.zip` que Terraform subirá a AWS.

**Para la Lambda de Subida (Upload):**
```bash
cd src/upload-lambda
npm install @aws-sdk/client-s3 uuid busboy
npm install sharp@0.33
cp -r ../node_modules .
zip -r ../upload-lambda.zip *
cd ..
```

**Para la Lambda de Procesamiento (Crop):**
```bash
cd src/crop-lambda
npm install @aws-sdk/client-s3 uuid busboy
npm install sharp@0.33
cp -r ../node_modules .
zip -r ../crop-lambda.zip *
cd ..
cd ..
```

### 3. Despliegue de Infraestructura con Terraform
Ahora vamos con los fierros:

```bash
cd terraform
terraform init

# Creamos los entornos de desarrollo
terraform workspace new dev
terraform workspace new qa
terraform workspace new prod

# Seleccionamos el entorno de desarrollo
terraform workspace select dev

# Aplicamos los cambios
terraform apply -var-file="dev.tfvars" -auto-approve
```

Al finalizar el `apply`, Terraform te entregará una `api_url`. Úsala para subir una imagen:

```bash
# Sube una imagen (de preferencia, que se llame foto.png y este en la raíz del repo)
curl -X POST <TU_API_URL_AQUI> \
  -H "Content-Type: image/png" \
  --data-binary "@../foto.png"
```
# Ahora toca repetir el proceso para los otros entornos.

```bash
terraform workspace select qa
terraform apply -var-file="qa.tfvars" -auto-approve
curl -X POST <TU_API_URL_AQUI> \
  -H "Content-Type: image/png" \
  --data-binary "@../foto.png"
```
# Solo se pueden desplegar dos entornos a la vez sin ampliar la maquina virtual. 
# Pasar a limpieza y luego desplegar el ultimo entorno.
```bash
terraform workspace select prod
terraform apply -var-file="prod.tfvars" -auto-approve
curl -X POST <TU_API_URL_AQUI> \
  -H "Content-Type: image/png" \
  --data-binary "@../foto.png"
```
### 5. Limpieza
Para evitar cargos innecesarios cuando termines tus pruebas:

```bash
terraform workspace select dev
terraform destroy -var-file="dev.tfvars" -auto-approve
```
```bash
terraform workspace select prod
terraform destroy -var-file="prod.tfvars" -auto-approve
```
```bash
terraform workspace select qa
terraform destroy -var-file="qa.tfvars" -auto-approve
```