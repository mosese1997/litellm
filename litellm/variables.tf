variable "access_key" {
  description = "Huawei Cloud access key"
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "Huawei Cloud secret key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Huawei Cloud region"
  type        = string
  default     = "la-north-2"
}

variable "project_id" {
  description = "Huawei Cloud project ID"
  type        = string
  default     = "<PROJECT_ID>"
}

variable "account_id" {
  description = "Huawei Cloud account ID"
  type        = string
  default     = "<DOMAIN_ID>"
}

variable "domain_name" {
  description = "Domain name for IAM agency"
  type        = string
  default     = "<DOMAIN_ID>"
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
  default     = "vpc-default"
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
  default     = "subnet-default"
}

variable "image_id" {
  description = "ECS image ID (Ubuntu 22.04)"
  type        = string
  default     = ""  # 使用数据源自动查找
}

variable "ecs_password" {
  description = "ECS instance password"
  type        = string
  sensitive   = true
  default     = "<ECS_PASSWORD>"
}

variable "ssh_public_key" {
  description = "SSH public key for ECS access"
  type        = string
  sensitive   = true
}

variable "maas_api_key" {
  description = "MaaS API key for Hong Kong endpoint"
  type        = string
  sensitive   = true
}

variable "maas_domain" {
  description = "MaaS Hong Kong domain"
  type        = string
  default     = "api-ap-southeast-1.modelarts-maas.com"
}

variable "maas_endpoint_ip" {
  description = "MaaS Hong Kong endpoint IP address"
  type        = string
}

variable "litellm_master_key" {
  description = "LiteLLM master key"
  type        = string
  sensitive   = true
  default     = "<LITELLM_MASTER_KEY>"
}