#Create VPC HA
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "vpc-retar"
  cidr = "10.10.0.0/20"

  # Specify at least one of: intra_subnets, private_subnets, or public_subnets
  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24"]
  public_subnets  = ["10.10.3.0/24", "10.10.4.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60
}

#Create S3 bucket
module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "s3-retar"
  acl    = "private"

  tags = {
    Owner = "retar"
  }

  versioning = {
    enabled = true
  }

  # S3 bucket-level Public Access Block configuration
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  force_destroy = true
}

#Create object in bucket
module "object" {
  source = "./terraform/modules/s3_bucket/modules/object"

  bucket = module.s3_bucket.s3_bucket_id
  key    = "texto.txt"

  file_source = "./archivos/texto.txt"

  tags = {
    owner = "retar"
  }
}

#Create APIGW to invoke Lambda Function
module "api_gateway" {
  source = "terraform-aws-modules/apigateway-v2/aws"

  name          = "apigw-retar"
  description   = "Show content from S3 bucket triggering Lambda Function"
  protocol_type = "HTTP"

  cors_configuration = {
    allow_headers = ["content-type", "x-amz-date", "authorization", "x-api-key", "x-amz-security-token", "x-amz-user-agent"]
    allow_methods = ["*"]
    allow_origins = ["*"]
  }

  create_api_domain_name = false

  default_route_settings = {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 100
    throttling_rate_limit    = 100
  }

  # Custom domain
  #domain_name                 = "terraform-aws-modules.modules.tf"
  #domain_name_certificate_arn = "arn:aws:acm:eu-west-1:052235179155:certificate/2b3a7ed9-05e1-4f9e-952b-27744ba06da6"

  # Access logs
  /*  default_stage_access_log_destination_arn = module.api_gateway.apigatewayv2_api_arn
  default_stage_access_log_format          = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId $context.integrationErrorMessage"
 */
  # Routes and integrations
  integrations = {
/*     "GET /" = {
      lambda_arn              = module.lambda_function_in_vpc.lambda_function_arn
      integration_http_method = "GET"
      payload_format_version  = "2.0"
      timeout_milliseconds    = 12000
    } */

    "GET /${module.lambda_function_in_vpc.lambda_function_name}" = {
      lambda_arn              = module.lambda_function_in_vpc.lambda_function_arn
      integration_http_method = "GET"
      payload_format_version  = "2.0"
      timeout_milliseconds    = 12000
    }

    "$default" = {
      lambda_arn = module.lambda_function_in_vpc.lambda_function_arn
    }
  }

  tags = {
    Name = "http-apigateway-retar"
  }
}

module "api_gateway_security_group" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "api-gateway-sg-retar"
  description = "API Gateway group for example usage"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp"]

  egress_rules = ["all-all"]
}

#Create Lambda Function to read objects in S3
module "lambda_function_in_vpc" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "lambda_retar"
  description   = "Lambda to read object in S3"
  handler       = "function.lambda_handler"
  runtime       = "python3.9"

  source_path = "./archivos/function.py"

  attach_cloudwatch_logs_policy = false

  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [module.vpc.default_security_group_id]

  publish = true

  attach_network_policy    = true
  attach_policy_statements = true
  policy_statements = {
    s3_read = {
      effect    = "Allow",
      actions   = ["s3:GetObject"],
      resources = ["arn:aws:s3:::${module.s3_bucket.s3_bucket_id}/*"]
    }
  }
  allowed_triggers = {
    APIGatewayAny = {
      service    = "apigateway",
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/${module.lambda_function_in_vpc.lambda_function_name}"
    }
  }
}
