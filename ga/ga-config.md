# GA Accelerator Configuration for MaaS Hong Kong Access
#
# Created via Huawei Cloud API (Terraform provider has limitations)
# GA is a global service, endpoint: https://ga.myhuaweicloud.com
# Region: la-north-2 (Mexico 2)

# === Existing GA Instance ===
# Accelerator ID: db0078a0-10d8-423c-b2e0-972c09c00536
# Accelerator Name: litellm-maas-ga
# Anycast IP: <GA_ANYCAST_IP>
# Acceleration Area: OUTOFCM (中国大陆以外)
# Status: ACTIVE

# === Listener ===
# Listener ID: 150ab2c5-eb03-409e-9be6-22dac4ed0bca
# Listener Name: maas-tcp-443
# Protocol: TCP
# Port Range: 443

# === Endpoint Group ===
# Endpoint Group ID: 147255f0-3473-4516-baf1-71ad19abdcf3
# Endpoint Group Name: maas-hk-endpoint-group
# Region: ap-southeast-1 (Hong Kong)
# Traffic Dial: 100%

# === Endpoint ===
# Endpoint ID: 4b8417af-9229-47b6-b851-adeaa5c351c0
# Resource Type: EIP
# IP Address: 189.1.245.206
# Custom Domain: api-ap-southeast-1.modelarts-maas.com
# Weight: 100

# === ECS Configuration ===
# Add to /etc/hosts on ECS:
#   <GA_ANYCAST_IP> api-ap-southeast-1.modelarts-maas.com
#
# This routes all MaaS API traffic through GA accelerator:
#   ECS → GA Anycast IP (<GA_ANYCAST_IP>) → Hong Kong MaaS
