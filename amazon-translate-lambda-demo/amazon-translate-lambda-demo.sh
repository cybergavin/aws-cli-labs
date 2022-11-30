#!/bin/bash
# AWS CLI demo of a lambda function that is triggered by a file upload to S3, to translate the file using Amazon translate and store the output in another S3 bucket.
# Uses sample code from https://aws.amazon.com/blogs/machine-learning/translating-documents-with-amazon-translate-aws-lambda-and-the-new-batch-translate-api/
# This is just a conversion of the AWS CloudFormation stack (URL above) to AWS CLI
#########################################################################################################################################
script_location="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"
script_name=`basename $0`
config=${script_location}/${script_name%%.*}.cfg
function_zip=${script_location}/${script_name%%.*}.zip
myrnd=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c5) # My random string to try to ensure unique names for AWS resources
#
# Check for Lambda package
#
if [ ! -s $function_zip ]; then
    echo "Missing Lambda function zip file ${function_zip}. Exiting!"
    exit 100
fi
#
# Source config
#
if [ -s $config ]; then
    source $config
else
    echo "Missing config file ${config}. Exiting!"
    exit 200
fi
#
# Validate config
#
if [ -z "${REGION}" -o -z "${APP_NAME}" -o -z "${ACCOUNT}" -o -z "${SOURCE_LANGUAGE}" -o -z "${TARGET_LANGUAGE}" ]; then
   echo "Missing value for a parameter in the config file ${config}. Exiting!"
   exit 300
fi
#
# App Variables
#
INPUT_BUCKET="${APP_NAME}-s3-input-${myrnd,,}"
OUTPUT_BUCKET="${APP_NAME}-s3-output-${myrnd,,}"
FUNCTION_NAME="${APP_NAME}-lambda-${myrnd,,}"
POLICY_NAME="${APP_NAME}-iam-policy"
ROLE_NAME="${APP_NAME}-iam-role"
#
# Create IAM Policy for Lambda function to access CloudWatch and S3
#
sed "s/~~ACCOUNT~~/${ACCOUNT}/g;s/~~FUNCTION_NAME~~/${FUNCTION_NAME}/g;s/~~INPUT_BUCKET~~/${INPUT_BUCKET}/g;s/~~OUTPUT_BUCKET~~/${OUTPUT_BUCKET}/g" lambda-policy-template.json > lambda-policy.json
aws iam create-policy \
    --policy-name $POLICY_NAME \
    --description "SALD: Cloudwatch and S3 permissions" \
    --policy-document file://lambda-policy.json
#
# Create IAM Role for Lambda function to assume (with permissions for CloudWatch, S3 and Translate)
#
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://lambda-trust-policy.json
aws iam attach-role-policy \
    --policy-arn arn:aws:iam::${ACCOUNT}:policy/$POLICY_NAME \
    --role-name $ROLE_NAME
aws iam attach-role-policy \
    --policy-arn arn:aws:iam::aws:policy/TranslateReadOnly \
    --role-name $ROLE_NAME
#
# Sleep for IAM role propagation
#
sleep 10
#
# Deploy Function
#
sed "s/~~SOURCE_LANGUAGE~~/${SOURCE_LANGUAGE}/g;s/~~TARGET_LANGUAGE~~/${TARGET_LANGUAGE}/g;s/~~TARGET_BUCKET~~/${OUTPUT_BUCKET}/g" lambda-variables-template.json > lambda-variables.json
aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --runtime python3.7 \
    --zip-file fileb://amazon-translate-lambda-demo.zip \
    --handler index.lambda_handler \
    --role arn:aws:iam::${ACCOUNT}:role/${ROLE_NAME} \
    --environment file://lambda-variables.json \
    --region $REGION
#
# Create S3 bucket for input text files
#
aws s3api create-bucket \
    --bucket $INPUT_BUCKET \
    --region $REGION 
#
# Create S3 bucket for output text files
#
aws s3api create-bucket \
    --bucket $OUTPUT_BUCKET \
    --region $REGION
#
# Grant permission to execute Lambda function to S3
#
aws lambda add-permission \
    --function-name $FUNCTION_NAME  \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::$INPUT_BUCKET \
    --statement-id 7777${myrnd,,}
#
# Configure S3 trigger for Lambda function
#
sed "s/~~REGION~~/${REGION}/g;s/~~ACCOUNT~~/${ACCOUNT}/g;s/~~FUNCTION_NAME~~/${FUNCTION_NAME}/g" s3-trigger-template.json > s3-trigger.json
aws s3api put-bucket-notification-configuration \
    --bucket $INPUT_BUCKET \
    --notification-configuration file://s3-trigger.json
