// src/crop-lambda/index.js
const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");

const s3 = new S3Client();

exports.handler = async (event) => {
    // Procesamiento de los registros recibidos en el lote (batch) de SQS
    for (const record of event.Records) {
        // Extracción y análisis del cuerpo del mensaje para obtener el evento de S3
        const sqsBody = JSON.parse(record.body);

        for (const s3Event of sqsBody.Records || []) {
            const bucket = s3Event.s3.bucket.name;
            const key = decodeURIComponent(s3Event.s3.object.key.replace(/\+/g, ' '));

            try {
                // 1. Descarga del objeto binario original desde el bucket S3
                const getReq = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
                const chunks = [];
                for await (const chunk of getReq.Body) chunks.push(chunk);
                const imageBuffer = Buffer.concat(chunks);

                // 2. Transformación de imagen: redimensionamiento y aplicación de máscara circular
                const circleSvg = Buffer.from('<svg><circle cx="20" cy="20" r="20" /></svg>');

                const processedBuffer = await sharp(imageBuffer)
                    .resize(40, 40, { fit: 'cover' })
                    .composite([{ input: circleSvg, blend: 'dest-in' }])
                    .png()
                    .toBuffer();

                // 3. Definición de la nueva ruta de almacenamiento procesada
                const newKey = key
                    .replace(process.env.UPLOAD_PREFIX, process.env.PROCESSED_PREFIX)
                    .replace(/\.[^/.]+$/, "") + "_circular.png";

                // 4. Almacenamiento del resultado procesado en el directorio de destino
                await s3.send(new PutObjectCommand({
                    Bucket: process.env.S3_BUCKET,
                    Key: newKey,
                    Body: processedBuffer,
                    ContentType: "image/png"
                }));

                console.log(`Imagen procesada correctamente en: ${newKey}`);

            } catch (error) {
                console.error("Error durante el procesamiento de la imagen:", error);
                // El relanzamiento del error permite a SQS gestionar reintentos o el envío a la DLQ
                throw error;
            }
        }
    }
    return "Procesamiento completado";
};