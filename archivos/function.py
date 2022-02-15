# coding: utf-8

import boto3
import json

def lambda_handler(event, context):

    s3 = boto3.client('s3')

    print('Original object from the S3 bucket:')
    original = s3.get_object(
    Bucket='s3-retar',
    Key='texto.txt')
    record = original['Body'].read().decode('utf-8')
    print(original['Body'].read().decode('utf-8'))
    
    return(json.dumps(record))