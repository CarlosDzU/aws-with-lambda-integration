// src/upload-lambda/index.js
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { v4: uuidv4 } = require("uuid");
const busboy = require("busboy"); 

const s3 = new S3Client();

exports.handler = async (event) => {
    try {
        // Generación de un identificador único para el nombre de la imagen
        const filename = `${uuidv4()}.png`;
        const key = `${process.env.UPLOAD_PREFIX}${filename}`;

        // Gestión de la decodificación del cuerpo de la solicitud en Base64 (API Gateway)
        const imageBuffer = event.isBase64Encoded
            ? Buffer.from(event.body, 'base64')
            : Buffer.from(event.body);

        // Persistencia de la imagen original en el bucket de almacenamiento S3
        await s3.send(new PutObjectCommand({
            Bucket: process.env.S3_BUCKET,
            Key: key,
            Body: imageBuffer,
            ContentType: "image/png"
        }));

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: "Imagen subida con éxito",
                file: key
            })
        };
    } catch (error) {
        console.error("Error subiendo imagen:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: "Fallo al subir la imagen" })
        };
    }
};