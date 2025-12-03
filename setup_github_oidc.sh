#!/bin/bash

# Variables
GITHUB_ORG="jorgecontreras" # Tu usuario de GitHub
GITHUB_REPO="jorgecontreras" # Tu repositorio
S3_BUCKET="jorgecontreras.dev" # Tu bucket
ROLE_NAME="GitHubActionsDeployRole"

# 1. Crear Proveedor OIDC (si no existe)
echo "Verificando proveedor OIDC..."
EXISTING_PROVIDER=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" --output text)

if [ -z "$EXISTING_PROVIDER" ]; then
    echo "Creando proveedor OIDC..."
    aws iam create-open-id-connect-provider \
        --url "https://token.actions.githubusercontent.com" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
else
    echo "Proveedor OIDC ya existe: $EXISTING_PROVIDER"
fi

# 2. Crear Política de Confianza (Trust Policy)
echo "Generando Trust Policy..."
cat > trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main"
                }
            }
        }
    ]
}
EOF

# 3. Crear Rol
echo "Creando Rol IAM..."
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json || echo "El rol ya existe, actualizando política de confianza..." && aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://trust-policy.json

# 4. Crear Política de Permisos (S3 + CloudFront)
echo "Generando Política de Permisos..."
cat > deploy-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::$S3_BUCKET",
                "arn:aws:s3:::$S3_BUCKET/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudfront:CreateInvalidation"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# 5. Adjuntar Política al Rol
echo "Adjuntando permisos..."
aws iam put-role-policy --role-name $ROLE_NAME --policy-name S3CloudFrontDeploy --policy-document file://deploy-policy.json

# 6. Output Final
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query "Role.Arn" --output text)
echo "--------------------------------------------------"
echo "✅ Configuración completada."
echo "--------------------------------------------------"
echo "Ve a GitHub -> Settings -> Secrets and variables -> Actions -> New repository secret"
echo "Nombre: AWS_ROLE_ARN"
echo "Valor: $ROLE_ARN"
echo "--------------------------------------------------"
echo "Recuerda también configurar AWS_S3_BUCKET y CLOUDFRONT_DISTRIBUTION_ID si no lo has hecho."

# Limpieza
rm trust-policy.json deploy-policy.json

