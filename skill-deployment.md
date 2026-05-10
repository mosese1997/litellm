# Huawei Cloud LiteLLM Proxy Deployment Skill

## Overview
Deploy LiteLLM Proxy on Huawei Cloud ECS (Mexico 2) with GA acceleration to MaaS Hong Kong, supporting both OpenAI and Anthropic compatible interfaces. Zero AK/SK on ECS — secrets fetched from CSMS via ECS metadata temporary credentials.

## Architecture

### Overall Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Huawei Cloud - la-north-2 (Mexico 2)               │
│                                                                                 │
│  ┌──────────┐     ┌──────────────────────────────────────────────────────┐      │
│  │  Client   │────▶│              EIP (5_bgp, 100Mbps)                   │      │
│  │ (User/App)│     │              <EIP>                         │      │
│  └──────────┘     └────────────────────┬───────────────────────────────┘      │
│                                          │                                      │
│                     ┌────────────────────▼────────────────────┐               │
│                     │        ECS: litellm-proxy-ecs           │               │
│                     │        c9.large.2 (2vCPU / 4GB)        │               │
│                     │        Ubuntu 24.04 server 64bit       │               │
│                     │        root / <ECS_PASSWORD>            │               │
│                     ├────────────────────────────────────────┤               │
│                     │                                        │               │
│                     │  ┌──────────────────────────────────┐  │               │
│                     │  │     Docker Compose Services       │  │               │
│                     │  │                                    │  │               │
│                     │  │  ┌────────────────────────────┐   │  │               │
│                     │  │  │  litellm_proxy             │   │  │               │
│                     │  │  │  Port: 4000 (proxy)        │   │  │               │
│                     │  │  │  Port: 4001 (admin UI)     │   │  │               │
│                     │  │  │  Image: litellm:main-latest│   │  │               │
│                     │  │  └─────────────┬──────────────┘   │  │               │
│                     │  │                 │                   │  │               │
│                     │  │       ┌─────────┴─────────┐       │  │               │
│                     │  │       │                   │       │  │               │
│                     │  │  ┌────▼─────┐      ┌─────▼────┐  │  │               │
│                     │  │  │ postgres  │      │  redis   │  │  │               │
│                     │  │  │ :5432     │      │  :6379   │  │  │               │
│                     │  │  │ 15-alpine │      │ 7-alpine │  │  │               │
│                     │  │  └───────────┘      └──────────┘  │  │               │
│                     │  │                                    │  │               │
│                     │  └──────────────────────────────────┘  │               │
│                     │                                        │               │
│                     │  ┌──────────────────────────────────┐  │               │
│                     │  │  Nginx :8443 (Anthropic path     │  │               │
│                     │  │  rewrite: /v1/messages →         │  │               │
│                     │  │  /anthropic/v1/messages)         │  │               │
│                     │  └──────────────────────────────────┘  │               │
│                     │                                        │               │
│                     │  /etc/hosts:                           │               │
│                     │  <GA_ANYCAST_IP> api-...-maas.com       │               │
│                     │                                        │               │
│                     │  Zero AK/SK on disk:                  │               │
│                     │  fetch_secrets.py → metadata → CSMS   │               │
│                     │  → .env.secrets (chmod 600)           │               │
│                     │                                        │               │
│                     └────────────────────┬───────────────────┘               │
│                                          │                                      │
│                     ┌────────────────────▼────────────────────┐               │
│                     │      VPC: vpc-default                  │               │
│                     │      Subnet: subnet-default            │               │
│                     │      192.168.0.0/24                    │               │
│                     └────────────────────────────────────────┘               │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐       │
│  │  Security Group: litellm_sg (全放通)                               │       │
│  └─────────────────────────────────────────────────────────────────────┘       │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐       │
│  │  IAM Agency: ecs-litellm-agency  │  KMS: litellm_master_key       │       │
│  │  CSMS: litellm-maas-api-key      │  CSMS: litellm-master-key      │       │
│  └─────────────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────────┘

                          │ HTTPS (443)
                          │ via /etc/hosts → GA Anycast IP
                          ▼

┌─────────────────────────────────────────────────────────────────────────────────┐
│                    GA (Global Accelerator) - Global Service                      │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────┐      │
│  │  Accelerator: litellm-maas-ga                                        │      │
│  │  Anycast IP: <GA_ANYCAST_IP>                                          │      │
│  │  Acceleration Area: OUTOFCM (中国大陆以外)                            │      │
│  └───────────────────────────┬───────────────────────────────────────────┘      │
│                                │                                                │
│  ┌───────────────────────────▼───────────────────────────────────────────┐      │
│  │  Listener: maas-tcp-443                                             │      │
│  │  Protocol: TCP  │  Port: 443                                        │      │
│  └───────────────────────────┬───────────────────────────────────────────┘      │
│                                │                                                │
│  ┌───────────────────────────▼───────────────────────────────────────────┐      │
│  │  Endpoint Group                                                      │      │
│  │  Region: ap-southeast-1 (Hong Kong)  │  Traffic: 100%               │      │
│  └───────────────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────────┘

                          │ Accelerated Tunnel
                          ▼

┌─────────────────────────────────────────────────────────────────────────────────┐
│               MaaS (Model as a Service) - ap-southeast-1 (Hong Kong)            │
│                                                                                 │
│  Domain: api-ap-southeast-1.modelarts-maas.com                                 │
│                                                                                 │
│  ┌─────────────────────────────────┐  ┌─────────────────────────────────┐       │
│  │  OpenAI Compatible Interface    │  │  Anthropic Compatible Interface│       │
│  │  /openai/v1/chat/completions   │  │  /anthropic/v1/messages       │       │
│  │  Auth: Bearer <API_KEY>        │  │  Auth: x-api-key <API_KEY>    │       │
│  └─────────────────────────────────┘  └─────────────────────────────────┘       │
│                                                                                 │
│  Models: deepseek-v4-flash, deepseek-v3.1-terminus, DeepSeek-V3,               │
│          deepseek-v3.2, deepseek-r1-250528, glm-5, glm-5.1                     │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Secret Management Flow (Zero AK/SK on ECS)

```
┌──────────┐    GET /openstack/latest/securitykey    ┌──────────────┐
│  ECS     │ ──────────────────────────────────────▶  │  Metadata    │
│  Agent   │ ◀──────────────────────────────────────  │  Service     │
│          │    Temp AK/SK/SecurityToken (1hr TTL)    └──────────────┘
│          │
│          │    ShowSecretVersionRequest(temp creds)
│          │ ──────────────────────────────────────▶  ┌──────────────┐
│          │ ◀──────────────────────────────────────  │  CSMS        │
│          │    MAAS_API_KEY, LITELLM_MASTER_KEY      │  (DEW)       │
│          │                                           └──────────────┘
│          │
│          │    Write /opt/litellm/.env.secrets (chmod 600)
│          │    docker compose --env-file .env.secrets up -d
└──────────┘
```

### Anthropic Passthrough Flow

```
Client (Anthropic SDK)
  │  POST /anthropic/v1/messages  (x-api-key, anthropic-version)
  ▼
LiteLLM Proxy :4000
  │  ANTHROPIC_API_BASE=http://host.docker.internal:8443
  │  LiteLLM v1.82.6 strips path from ANTHROPIC_API_BASE
  │  → sends to http://host.docker.internal:8443/v1/messages
  ▼
Nginx :8443
  │  proxy_pass https://api-ap-southeast-1.modelarts-maas.com/anthropic/
  │  → rewrites to /anthropic/v1/messages
  ▼
MaaS Anthropic API (via GA → /etc/hosts → <GA_ANYCAST_IP>)
```

## Prerequisites
- Huawei Cloud account with AK/SK (for Terraform control only, NOT on ECS)
- MaaS API Key (Hong Kong region)
- Terraform >= 1.0 with huaweicloud provider >= 1.70.0

## Step 1: Terraform Infrastructure

### 1.1 Key Configuration Notes
- **Region**: `la-north-2` (Mexico 2)
- **Image**: Ubuntu 24.04 (NOT 22.04 - see Pitfall #1)
- **ECS Password**: Must not contain special chars that break URL encoding in DATABASE_URL
- **DO NOT use user_data** - see Pitfall #2
- **EIP Bandwidth**: Temporarily increase to 100Mbps during Docker image pull
- **IAM Agency**: Required for ECS metadata temporary credentials to read CSMS

### 1.2 main.tf Essentials
```hcl
data "huaweicloud_images_image" "ubuntu" {
  name_regex = "^Ubuntu 24.04"   # MUST use 24.04, not 22.04
  most_recent = true
}

resource "huaweicloud_compute_instance" "litellm_ecs" {
  name              = "litellm-proxy-ecs"
  image_id          = data.huaweicloud_images_image.ubuntu.id
  flavor_id         = "c9.large.2"
  admin_pass        = var.ecs_password
  # DO NOT set user_data - it breaks admin_pass via cloud-init
  agency_name       = huaweicloud_identity_agency.ecs_litellm_agency.name
}

resource "huaweicloud_identity_agency" "ecs_litellm_agency" {
  name                  = "ecs-litellm-agency"
  delegated_service_name = "op_svc_ecs"
  project_role {
    project = "la-north-2"
    roles   = ["KMS Administrator"]  # KMS Admin covers DEW (KMS + CSMS)
  }
}

resource "huaweicloud_kms_key" "litellm_key" {
  key_alias = "litellm_master_key"
}

resource "huaweicloud_csms_secret" "maas_api_key" {
  name        = "litellm-maas-api-key"
  secret_text = var.maas_api_key
  kms_key_id  = huaweicloud_kms_key.litellm_key.id
}

resource "huaweicloud_csms_secret" "master_key" {
  name        = "litellm-master-key"
  secret_text = var.litellm_master_key
  kms_key_id  = huaweicloud_kms_key.litellm_key.id
}
```

### 1.3 Apply
```bash
terraform init
terraform apply -auto-approve
```

## Step 2: SSH Access

```bash
ssh root@<EIP>   # Password: <ECS_PASSWORD>
```

**IMPORTANT**: Use `root` user, NOT `ubuntu`. Ubuntu 24.04 on Huawei Cloud enables root password login by default.

## Step 3: Docker Installation

```bash
ssh root@<EIP> 'curl -fsSL https://get.docker.com | sh'
```

## Step 4: Zero AK/SK Secret Fetching

### 4.1 fetch_secrets.py
Deploy to `/opt/litellm/fetch_secrets.py` on ECS. This script:
1. Reads temporary credentials from ECS metadata endpoint `http://169.254.169.254/openstack/latest/securitykey`
2. Uses temp AK/SK/securitytoken to call CSMS `ShowSecretVersionRequest`
3. Writes secrets to `/opt/litellm/.env.secrets` (chmod 600)

```python
import json, requests
from huaweicloudsdkcore.auth.credentials import BasicCredentials
from huaweicloudsdkcsms.v1 import CsmsClient, ShowSecretVersionRequest
from huaweicloudsdkcsms.v1.region.csms_region import CsmsRegion

# Step 1: Get temp credentials from metadata
meta = requests.get("http://169.254.169.254/openstack/latest/securitykey").json()
cred = meta["credential"]

# Step 2: Read CSMS secrets using temp credentials
creds = BasicCredentials(cred["access"], cred["secret"], project_id="<PROJECT_ID>")
creds.security_token = cred["securitytoken"]
client = CsmsClient.new_builder().with_credentials(creds).with_region(CsmsRegion.value_of("la-north-2")).build()

secrets = {}
for name in ["litellm-maas-api-key", "litellm-master-key"]:
    resp = client.show_secret_version(ShowSecretVersionRequest(secret_name=name))
    secrets[name] = resp.version.secret_string

# Step 3: Write .env.secrets
with open("/opt/litellm/.env.secrets", "w") as f:
    f.write(f"MAAS_API_KEY={secrets['litellm-maas-api-key']}\n")
    f.write(f"LITELLM_MASTER_KEY={secrets['litellm-master-key']}\n")
import os; os.chmod("/opt/litellm/.env.secrets", 0o600)
```

### 4.2 Install Huawei Cloud SDK on ECS
```bash
pip3 install huaweicloudsdkcore huaweicloudsdkcsms
```

## Step 5: Upload Configuration Files

### 5.1 config.yaml - Model Configuration

MaaS model names:
| Model Version | OpenAI `model` param | Anthropic `model` param |
|---|---|---|
| DeepSeek-V4-Flash | `deepseek-v4-flash` | `deepseek-v4-flash` |
| DeepSeek-V3.1 | `deepseek-v3.1-terminus` | `deepseek-v3.1-terminus` |
| DeepSeek-V3 | `DeepSeek-V3` | `DeepSeek-V3` |
| DeepSeek-V3.2 | `deepseek-v3.2` | `deepseek-v3.2` |
| DeepSeek-R1-0528 | `deepseek-r1-250528` | `deepseek-r1-250528` |
| GLM-5 | `glm-5` | `glm-5` |
| GLM-5.1 | `glm-5.1` | `glm-5.1` |

**API Endpoints:**
- OpenAI compatible: `https://api-ap-southeast-1.modelarts-maas.com/openai/v1`
- Anthropic compatible: `https://api-ap-southeast-1.modelarts-maas.com/anthropic`

### 5.2 config.yaml Template
```yaml
model_list:
  - model_name: deepseek-v4-flash
    litellm_params:
      model: deepseek-v4-flash
      api_base: https://api-ap-southeast-1.modelarts-maas.com/openai/v1
      api_key: os.environ/MAAS_API_KEY
      custom_llm_provider: openai

  - model_name: deepseek-v4-flash-anthropic
    litellm_params:
      model: deepseek-v4-flash
      api_base: https://api-ap-southeast-1.modelarts-maas.com/anthropic
      api_key: os.environ/MAAS_API_KEY
      custom_llm_provider: anthropic

  # ... repeat for all 7 models (OpenAI + Anthropic variants)

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  otel: false
```

**IMPORTANT**: Use `os.environ/VAR_NAME` syntax for secrets in config.yaml. LiteLLM does NOT substitute `${VAR}`.

### 5.3 docker-compose.yml
```yaml
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: litellm
      POSTGRES_PASSWORD: litellm123
      POSTGRES_DB: litellm

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass litellm123

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    env_file:
      - .env.secrets
    depends_on:
      - postgres
      - redis
    environment:
      - DATABASE_URL=postgresql://litellm:litellm123@postgres:5432/litellm
      - REDIS_URL=redis://:litellm123@redis:6379
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - MAAS_API_KEY=${MAAS_API_KEY}
      - PORT=4000
      - ADMIN_PORT=4001
      - ANTHROPIC_API_BASE=http://host.docker.internal:8443
      - ANTHROPIC_API_KEY=${MAAS_API_KEY}
    extra_hosts:
      - "host.docker.internal:host-gateway"
    command: ["--config", "/app/config/config.yaml"]
```

**NOTE**: `ANTHROPIC_API_BASE` points to local nginx (port 8443) because LiteLLM v1.82.6 strips the path from ANTHROPIC_API_BASE. Nginx rewrites the path to add `/anthropic` prefix.

## Step 6: Nginx Anthropic Path Proxy

LiteLLM's `/anthropic/v1/messages` passthrough endpoint uses `ANTHROPIC_API_BASE` env var, but v1.82.6 ignores the path component. Nginx rewrites the path:

```nginx
server {
    listen 8443;
    location / {
        proxy_pass https://api-ap-southeast-1.modelarts-maas.com/anthropic/;
        proxy_ssl_server_name on;
        proxy_set_header Host api-ap-southeast-1.modelarts-maas.com;
    }
}
```

Flow: LiteLLM → `localhost:8443/v1/messages` → nginx → `api-ap-southeast-1.modelarts-maas.com/anthropic/v1/messages`

## Step 7: Start Services

```bash
# Fetch secrets from CSMS
python3 /opt/litellm/fetch_secrets.py

# Start docker with secrets
cd /opt/litellm && docker compose --env-file .env.secrets up -d
```

Wait ~30s for startup, then verify:
```bash
source /opt/litellm/.env.secrets
curl http://localhost:4000/health -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

## Step 8: GA (Global Accelerator) Setup

### 8.1 Create GA via API
GA is a global service. Use endpoint `https://ga.myhuaweicloud.com`.

Required parameters:
- **Accelerator**: area = `OUTOFCM` (outside mainland China)
- **Listener**: protocol = TCP, port = 443
- **Endpoint Group**: region_id = `ap-southeast-1` (Hong Kong)
- **Endpoint**: resource_type = EIP, use MaaS endpoint EIP

### 8.2 Configure ECS /etc/hosts
```bash
echo "<GA_ANYCAST_IP> api-ap-southeast-1.modelarts-maas.com" >> /etc/hosts
```

This routes all MaaS API traffic through GA accelerator.

## Step 9: systemd Service (Optional)

```ini
[Unit]
Description=LiteLLM Proxy
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/litellm
ExecStartPre=/usr/bin/python3 /opt/litellm/fetch_secrets.py
ExecStart=/usr/bin/docker compose --env-file /opt/litellm/.env.secrets up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
```

## Pitfalls & Solutions

### Pitfall #1: Ubuntu 22.04 SSH Login Fails
**Problem**: Ubuntu 22.04 on Huawei Cloud disables root password login by default.
**Solution**: Use Ubuntu 24.04, which enables root password login by default.

### Pitfall #2: user_data Breaks admin_pass
**Problem**: Heavy user_data scripts cause cloud-init to timeout, preventing `admin_pass` from taking effect.
**Solution**: Do NOT use `user_data`. Set `admin_pass` only. Install software manually after SSH.

### Pitfall #3: DATABASE_URL with Special Characters
**Problem**: Password with `@!#` breaks URL parsing in `postgresql://user:pass@host:port/db`.
**Solution**: Use a simple DB password without special characters (e.g., `litellm123`).

### Pitfall #4: config.yaml Environment Variable Substitution
**Problem**: LiteLLM does NOT substitute `${VAR}` in config.yaml.
**Solution**: Use `os.environ/VAR_NAME` syntax. LiteLLM resolves this at runtime.

### Pitfall #5: docker-compose command Format
**Problem**: `command: sh -c "sleep 10 && litellm --config ..."` causes "Got unexpected extra argument".
**Solution**: Use `command: ["--config", "/app/config/config.yaml"]`.

### Pitfall #6: MaaS Model Names
**Problem**: Using display names like `DeepSeek-V3.1` causes "Invalid model" errors.
**Solution**: Use exact API model IDs: `deepseek-v3.1-terminus`, `deepseek-r1-250528`, etc.

### Pitfall #7: MaaS Anthropic Rate Limit
**Problem**: Health check shows Anthropic models as "unhealthy" (1 req/sec rate limit).
**Solution**: False alarm from concurrent health checks. Actual requests work fine.

### Pitfall #8: GA Terraform Provider Limitations
**Problem**: GA Terraform provider only supports `EIP` resource_type, not `CUSTOM`.
**Solution**: Use GA Python SDK with global endpoint `https://ga.myhuaweicloud.com`.

### Pitfall #9: LiteLLM ANTHROPIC_API_BASE Path Stripping
**Problem**: LiteLLM v1.82.6 ignores the path component of `ANTHROPIC_API_BASE`. Setting it to `https://domain/anthropic` still sends requests to `https://domain/v1/messages`.
**Solution**: Use local nginx reverse proxy to rewrite the path. Set `ANTHROPIC_API_BASE=http://host.docker.internal:8443` and configure nginx to proxy to `https://domain/anthropic/`.

### Pitfall #10: docker compose env_file vs --env-file
**Problem**: `env_file` in docker-compose.yml injects vars into the container, but does NOT make them available for `${VAR}` interpolation in the YAML itself.
**Solution**: Use `docker compose --env-file .env.secrets up -d` to pass vars for YAML interpolation. Also keep `env_file` in the service for container env injection.

### Pitfall #11: ECS Metadata Endpoint
**Problem**: `/openstack/latest/security_token.json` returns 404 in la-north-2.
**Solution**: Use `/openstack/latest/securitykey` instead. Response format: `{"credential": {"access": "...", "secret": "...", "securitytoken": "..."}}`.

## Final Deployment Summary

| Component | Value |
|---|---|
| ECS Region | la-north-2 (Mexico 2) |
| ECS Spec | c9.large.2 (2vCPU/4GB) |
| ECS Image | Ubuntu 24.04 server 64bit |
| ECS User | root |
| LiteLLM Proxy | http://<EIP>:4000 |
| LiteLLM Admin UI | http://<EIP>:4001/ui |
| GA Anycast IP | <GA_ANYCAST_IP> |
| MaaS Region | ap-southeast-1 (Hong Kong) |
| Healthy Models (OpenAI) | 7 |
| Healthy Models (Anthropic passthrough) | 7 |
| CSMS Secrets | litellm-maas-api-key, litellm-master-key |
| IAM Agency | ecs-litellm-agency (KMS Administrator) |
| AK/SK on ECS | None (metadata temp credentials) |

## Quick Verification Commands

```bash
# SSH access
ssh root@<EIP>

# Check containers
ssh root@<EIP> 'docker ps'

# Health check
source /opt/litellm/.env.secrets
curl -s http://<EIP>:4000/health \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# OpenAI model call
curl -s http://<EIP>:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v3.2","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'

# Anthropic passthrough call
curl -s http://<EIP>:4000/anthropic/v1/messages \
  -H "x-api-key: $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"glm-5","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'

# Check GA routing
ssh root@<EIP> 'grep modelarts /etc/hosts'

# Verify no AK/SK on ECS
ssh root@<EIP> 'grep -rn "HPUAW\|xI48RE" /opt/litellm/ --include="*.py" --include="*.yaml" --include="*.yml"'

# Check LiteLLM logs
ssh root@<EIP> 'docker logs litellm_proxy --tail 20'
```
