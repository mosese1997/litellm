terraform {
  required_version = ">= 1.0"
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.70.0"
    }
  }
}

provider "huaweicloud" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
  project_id = var.project_id
}

data "huaweicloud_availability_zones" "azs" {}

data "huaweicloud_vpc" "vpc" {
  name = var.vpc_name
}

data "huaweicloud_vpc_subnet" "subnet" {
  name   = var.subnet_name
  vpc_id = data.huaweicloud_vpc.vpc.id
}

data "huaweicloud_images_image" "ubuntu" {
  name_regex = "^Ubuntu 24.04"
  most_recent = true
}

resource "huaweicloud_identity_agency" "litellm_agency" {
  name                   = "litellm_agency"
  delegated_service_name = "op_svc_ecs"
  description           = "Agency for LiteLLM ECS instance to access DEW and other services"
  duration              = "FOREVER"
}

resource "huaweicloud_kms_key" "litellm_master_key" {
  key_alias       = "litellm_master_key"
  key_description = "Master key for LiteLLM proxy"
  pending_days    = 7
  key_usage       = "ENCRYPT_DECRYPT"
}

resource "huaweicloud_csms_secret" "maas_api_key" {
  name        = "maas_api_key"
  description = "MaaS API key for Hong Kong endpoint"
  secret_text = var.maas_api_key
}

# 华为云ECS使用密码登录
# resource "huaweicloud_compute_keypair" "litellm_keypair" {
#   name       = "litellm_keypair"
#   public_key = var.ssh_public_key
# }

resource "huaweicloud_networking_secgroup" "litellm_sg" {
  name        = "litellm_sg"
  description = "Security group for LiteLLM proxy"
}

resource "huaweicloud_networking_secgroup_rule" "allow_all_inbound_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.litellm_sg.id
  port_range_min    = 1
  port_range_max    = 65535
}

resource "huaweicloud_networking_secgroup_rule" "allow_all_inbound_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.litellm_sg.id
  port_range_min    = 1
  port_range_max    = 65535
}

resource "huaweicloud_networking_secgroup_rule" "allow_all_inbound_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.litellm_sg.id
}

resource "huaweicloud_networking_secgroup_rule" "allow_all_outbound_tcp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.litellm_sg.id
  port_range_min    = 1
  port_range_max    = 65535
}

resource "huaweicloud_networking_secgroup_rule" "allow_all_outbound_udp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.litellm_sg.id
  port_range_min    = 1
  port_range_max    = 65535
}

resource "huaweicloud_networking_secgroup_rule" "allow_all_outbound_icmp" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.litellm_sg.id
}

resource "huaweicloud_vpc_eip" "litellm_eip" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "litellm_bandwidth"
    size        = 10
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "huaweicloud_compute_instance" "litellm_ecs" {
  name              = "litellm-proxy-ecs"
  image_id          = data.huaweicloud_images_image.ubuntu.id
  flavor_id         = "c9.large.2"
  availability_zone = data.huaweicloud_availability_zones.azs.names[0]
  # key_pair          = huaweicloud_compute_keypair.litellm_keypair.name
  admin_pass        = var.ecs_password

  system_disk_type = "SSD"
  system_disk_size = 40

  network {
    uuid = data.huaweicloud_vpc_subnet.subnet.id
  }

  security_group_ids = [huaweicloud_networking_secgroup.litellm_sg.id]

  agency_name = huaweicloud_identity_agency.litellm_agency.name

  tags = {
    purpose = "litellm-proxy"
    env     = "production"
  }
}

resource "huaweicloud_compute_eip_associate" "litellm_eip_associate" {
  public_ip   = huaweicloud_vpc_eip.litellm_eip.address
  instance_id = huaweicloud_compute_instance.litellm_ecs.id
}

# GA accelerator for MaaS access - created via API due to Terraform provider limitations
# GA endpoint only supports EIP type in Terraform, but MaaS requires CUSTOM type
# Will be created using Huawei Cloud API directly