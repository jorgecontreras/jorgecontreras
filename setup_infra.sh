#!/bin/bash

BUCKET_NAME="jorgecontreras.dev"
REGION="us-east-1"

echo "🚀 Iniciando configuración de infraestructura..."

# 1. Crear Bucket S3
echo "Creando bucket: $BUCKET_NAME..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "El bucket ya existe."
else
    aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
fi

# 2. Desactivar 'Block Public Access' (para hosting estático simple)
echo "Configurando acceso público..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# 3. Política del Bucket (Lectura pública)
echo "Aplicando política de lectura pública..."
cat > bucket-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF
aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file://bucket-policy.json
rm bucket-policy.json

# 4. Habilitar Website Hosting
echo "Habilitando Static Website Hosting..."
aws s3 website "s3://$BUCKET_NAME" --index-document index.html --error-document index.html

# 5. Obtener Endpoint del Website
WEBSITE_ENDPOINT="http://$BUCKET_NAME.s3-website-$REGION.amazonaws.com"
echo "✅ Bucket configurado. Endpoint S3: $WEBSITE_ENDPOINT"

# 6. Crear Distribución de CloudFront (Opcional pero recomendado)
echo "¿Quieres crear la distribución de CloudFront ahora? (Esto puede tardar unos minutos) [s/n]"
read -r CREATE_CF

if [[ "$CREATE_CF" =~ ^[Ss]$ ]]; then
    echo "Creando distribución de CloudFront..."
    echo "⚠️ Nota: Esta es una configuración básica. Para HTTPS con tu dominio necesitarás configurar ACM (Certificados) manualmente después."
    
    CF_ID=$(aws cloudfront create-distribution \
        --origin-domain-name "$BUCKET_NAME.s3-website-$REGION.amazonaws.com" \
        --default-root-object index.html \
        --query "Distribution.Id" \
        --output text)
        
    echo "--------------------------------------------------"
    echo "✅ Distribución creada."
    echo "CloudFront ID: $CF_ID"
    echo "--------------------------------------------------"
    echo "Guarda este ID para agregarlo a tus secretos de GitHub (CLOUDFRONT_DISTRIBUTION_ID)."
else
    echo "Saltando creación de CloudFront."
fi

echo "--------------------------------------------------"
echo "🏁 Infraestructura lista."
echo "Recuerda actualizar tus GitHub Secrets con el CLOUDFRONT_DISTRIBUTION_ID si lo creaste."

