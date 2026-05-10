output "ecs_public_ip" {
  description = "Public IP address of the LiteLLM ECS instance"
  value       = huaweicloud_vpc_eip.litellm_eip.address
}

output "ecs_instance_id" {
  description = "ID of the LiteLLM ECS instance"
  value       = huaweicloud_compute_instance.litellm_ecs.id
}

output "ecs_name" {
  description = "Name of the LiteLLM ECS instance"
  value       = huaweicloud_compute_instance.litellm_ecs.name
}

# GA accelerator IP will be output after GA creation via API

output "kms_key_id" {
  description = "ID of the KMS master key"
  value       = huaweicloud_kms_key.litellm_master_key.id
}

output "csms_secret_name" {
  description = "Name of the CSMS secret"
  value       = huaweicloud_csms_secret.maas_api_key.name
}

output "agency_name" {
  description = "Name of the IAM agency"
  value       = huaweicloud_identity_agency.litellm_agency.name
}

output "security_group_id" {
  description = "ID of the security group"
  value       = huaweicloud_networking_secgroup.litellm_sg.id
}

output "litellm_endpoint" {
  description = "LiteLLM proxy endpoint URL"
  value       = "http://${huaweicloud_vpc_eip.litellm_eip.address}:4000"
}

output "litellm_admin_endpoint" {
  description = "LiteLLM admin endpoint URL"
  value       = "http://${huaweicloud_vpc_eip.litellm_eip.address}:4001"
}

output "ssh_connection_command" {
  description = "SSH connection command to the ECS instance"
  value       = "ssh ubuntu@${huaweicloud_vpc_eip.litellm_eip.address}"
}