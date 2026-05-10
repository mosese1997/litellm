# Huawei Cloud LiteLLM Proxy Deployment Skill

## Overview
Deploy LiteLLM Proxy on Huawei Cloud ECS (Mexico 2) with GA acceleration to MaaS Hong Kong, supporting both OpenAI and Anthropic compatible interfaces.

## Architecture

### Overall Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Huawei Cloud - la-north-2 (Mexico 2)               │
│                                                                                 │
│  ┌──────────┐     ┌──────────────────────────────────────────────────────┐      │
│  │  Client   │────▶│              EIP (5_bgp, 10Mbps traffic)            │      │
│  │ (User/App)│     │              <ECS_PUBLIC_IP>                         │      │
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
│                     │  │  │  Port: 4001 (admin)        │   │  │               │
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
│                     │  /etc/hosts:                           │               │
│                     │  <GA_ANYCAST_IP> api-...-maas.com       │               │
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
│  │  Ingress: TCP/UDP 1-65535, ICMP  ──▶ 0.0.0.0/0                   │       │
│  │  Egress:  TCP/UDP 1-65535, ICMP  ──▶ 0.0.0.0/0                   │       │
│  └─────────────────────────────────────────────────────────────────────┘       │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐       │
│  │  IAM Agency: litellm_agency  │  KMS: litellm_master_key           │       │
│  │  CSMS Secret: maas_api_key   │  (for DEW service access)          │       │
│  └─────────────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────────┘

                          │ HTTPS (443)
                          │ via /etc/hosts → GA Anycast IP
                          ▼

┌─────────────────────────────────────────────────────────────────────────────────┐
│                    GA (Global Accelerator) - Global Service                      │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────┐      │
│  │  Accelerator: maas_ga                                               │      │
│  │  Anycast IP: <GA_ANYCAST_IP>                                         │      │
│  │  Acceleration Area: OUTOFCM (中国大陆以外)                           │      │
│  └───────────────────────────┬───────────────────────────────────────────┘      │
│                                │                                                │
│  ┌───────────────────────────▼───────────────────────────────────────────┐      │
│  │  Listener: maas-tcp-443                                             │      │
│  │  Protocol: TCP  │  Port: 443                                        │      │
│  └───────────────────────────┬───────────────────────────────────────────┘      │
│                                │                                                │
│  ┌───────────────────────────▼───────────────────────────────────────────┐      │
│  │  Endpoint Group: maas-hk-endpoint-group                             │      │
│  │  Region: ap-southeast-1 (Hong Kong)  │  Traffic: 100%               │      │
│  │                                                                      │      │
│  │  ┌────────────────────────────────────────────────────────────────┐  │      │
│  │  │  Endpoint: EIP 189.1.245.206  │  Weight: 100  │  Status: ✓  │  │      │
│  │  │  (自定义域名: api-ap-southeast-1.modelarts-maas.com)          │  │      │
│  │  └────────────────────────────────────────────────────────────────┘  │      │
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
│  └────────────┬────────────────────┘  └────────────┬────────────────────┘       │
│                 │                                     │                         │
│  ┌──────────────▼─────────────────────────────────────▼──────────────────┐      │
│  │                        Supported Models                              │      │
│  │                                                                      │      │
│  │  DeepSeek Series          │  GLM Series                             │      │
│  │  ─────────────────────────────────────────────────────────────       │      │
│  │  deepseek-v4-flash        │  glm-5                                  │      │
│  │  deepseek-v3.1-terminus   │  glm-5.1                                │      │
│  │  DeepSeek-V3              │                                         │      │
│  │  deepseek-v3.2            │                                         │      │
│  │  deepseek-r1-250528       │                                         │      │
│  └──────────────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow Diagram

```
┌────────┐     HTTP/443      ┌─────────┐    rewrite DNS    ┌────────┐   TCP/443   ┌──────────┐
│        │ ───────────────▶  │         │ ───────────────▶  │        │ ──────────▶ │          │
│ Client │   :4000/:4001    │   ECS   │   /etc/hosts      │   GA   │   tunnel    │  MaaS    │
│        │ ◀───────────────  │ LiteLLM │ ◀───────────────  │Acceler │ ◀────────── │  HK API  │
└────────┘   JSON resp      │  Proxy  │   Anycast IP      │  ator  │   resp     │          │
                             └────┬────┘                   └────────┘            └──────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
                    ▼             ▼             ▼
              ┌──────────┐ ┌──────────┐ ┌──────────┐
              │PostgreSQL│ │  Redis   │ │  Docker  │
              │  :5432   │ │  :6379   │ │  Volumes │
              │  persist │ │  cache   │ │  /opt/... │
              └──────────┘ └──────────┘ └──────────┘
```

### LiteLLM Internal Routing

```
                    ┌─────────────────────────────┐
                    │     LiteLLM Proxy :4000      │
                    │                              │
  Request ─────────▶│  model_name routing         │
  (with API key)    │                              │
                    │  ┌───────────────────────┐  │
                    │  │ OpenAI Compatible      │  │
                    │  │ api_base: .../openai/v1│  │──────▶ MaaS OpenAI Endpoint
                    │  │ custom_llm_provider:   │  │       Auth: Bearer
                    │  │   openai               │  │
                    │  └───────────────────────┘  │
                    │                              │
                    │  ┌───────────────────────┐  │
                    │  │ Anthropic Compatible   │  │
                    │  │ api_base: .../anthropic│  │──────▶ MaaS Anthropic Endpoint
                    │  │ custom_llm_provider:   │  │       Auth: x-api-key
                    │  │   anthropic            │  │
                    │  └───────────────────────┘  │
                    │                              │
                    │  ┌───────────────────────┐  │
                    │  │ DB: PostgreSQL+Redis   │  │
                    │  │ - API key management   │  │
                    │  │ - usage tracking       │  │
                    │  │ - model config cache   │  │
                    │  └───────────────────────┘  │
                    └─────────────────────────────┘
```

## Prerequisites
- Huawei Cloud account with AK/SK
- MaaS API Key (Hong Kong region)
- Terraform >= 1.0 with huaweicloud provider >= 1.70.0

## Step 1: Terraform Infrastructure

### 1.1 Key Configuration Notes
- **Region**: `la-north-2` (Mexico 2)
- **Image**: Ubuntu 24.04 (NOT 22.04 - see Pitfall #1)
- **ECS Password**: Must not contain special chars that break URL encoding in DATABASE_URL
- **DO NOT use user_data** - see Pitfall #2
- **EIP Bandwidth**: Temporarily increase to 100Mbps during Docker image pull, then reduce to 10Mbps

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
  agency_name       = huaweicloud_identity_agency.litellm_agency.name
}
```

### 1.3 Security Group
Full open for testing; restrict in production:
```hcl
# TCP 1-65535 ingress/egress, UDP 1-65535 ingress/egress, ICMP ingress/egress
```

### 1.4 Apply
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

## Step 4: Upload Configuration Files

```bash
scp config.yaml root@<EIP>:/opt/litellm/config/config.yaml
scp docker-compose.yml root@<EIP>:/opt/litellm/docker-compose.yml
```

### 4.1 config.yaml - Model Configuration

MaaS model names (from API documentation):
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

**Auth:**
- OpenAI: `Authorization: Bearer <MAAS_API_KEY>`
- Anthropic: `x-api-key: <MAAS_API_KEY>` (handled automatically by litellm)

### 4.2 config.yaml Template
```yaml
model_list:
  # OpenAI compatible interface
  - model_name: deepseek-v4-flash
    litellm_params:
      model: deepseek-v4-flash
      api_base: https://api-ap-southeast-1.modelarts-maas.com/openai/v1
      api_key: <MAAS_API_KEY>
      custom_llm_provider: openai

  # Anthropic compatible interface
  - model_name: deepseek-v4-flash-anthropic
    litellm_params:
      model: deepseek-v4-flash
      api_base: https://api-ap-southeast-1.modelarts-maas.com/anthropic
      api_key: <MAAS_API_KEY>
      custom_llm_provider: anthropic

  # ... repeat for all models

general_settings:
  master_key: <LITELLM_MASTER_KEY>  # Write actual value, NOT ${VAR}
  otel: false

# DO NOT put DATABASE_URL or REDIS_URL in environment_variables section
# DO NOT use ${VAR} syntax - litellm does NOT substitute env vars in config.yaml
```

### 4.3 docker-compose.yml Template
```yaml
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: litellm
      POSTGRES_PASSWORD: <DB_PASSWORD>  # Avoid special chars (@!#) in DB password
      POSTGRES_DB: litellm

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass <DB_PASSWORD>

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    depends_on:
      - postgres
      - redis
    environment:
      - DATABASE_URL=postgresql://litellm:<DB_PASSWORD>@postgres:5432/litellm
      - REDIS_URL=redis://:<DB_PASSWORD>@redis:6379
      - LITELLM_MASTER_KEY=<LITELLM_MASTER_KEY>
      - MAAS_API_KEY=<MAAS_API_KEY>
    command: ["--config", "/app/config/config.yaml"]  # NOT sh -c "..."
```

## Step 5: Start Services

```bash
ssh root@<EIP> 'cd /opt/litellm && MAAS_API_KEY=<KEY> docker compose up -d'
```

Wait ~30s for startup, then verify:
```bash
curl http://<EIP>:4000/health -H "Authorization: Bearer <MASTER_KEY>"
```

## Step 6: GA (Global Accelerator) Setup

### 6.1 Create GA via API (Terraform provider has limitations)
GA is a global service. Use endpoint `https://ga.myhuaweicloud.com` with region `la-north-2`.

Required parameters:
- **Accelerator**: area = `OUTOFCM` (outside mainland China)
- **Listener**: protocol = TCP, port = 443
- **Endpoint Group**: region_id = `ap-southeast-1` (Hong Kong)
- **Endpoint**: resource_type = EIP, use MaaS endpoint EIP

### 6.2 Configure ECS /etc/hosts
```bash
ssh root@<EIP> 'echo "<GA_ANYCAST_IP> api-ap-southeast-1.modelarts-maas.com" >> /etc/hosts'
```

This routes all MaaS API traffic through GA accelerator.

### 6.3 Verify GA
```bash
ssh root@<EIP> 'curl -sk https://api-ap-southeast-1.modelarts-maas.com/openai/v1/models \
  -H "Authorization: Bearer <MAAS_API_KEY>"'
```

## Step 7: EIP Bandwidth Optimization

```hcl
# During Docker image pull (litellm image ~1.5GB):
bandwidth { size = 100 }

# After deployment complete:
bandwidth { size = 10 }
```

## Pitfalls & Solutions

### Pitfall #1: Ubuntu 22.04 SSH Login Fails
**Problem**: Ubuntu 22.04 on Huawei Cloud disables root password login by default. `admin_pass` sets the password but SSH rejects it.
**Solution**: Use Ubuntu 24.04, which enables root password login by default.

### Pitfall #2: user_data Breaks admin_pass
**Problem**: Heavy user_data scripts (apt-get upgrade, Docker install) cause cloud-init to timeout or fail, which prevents `admin_pass` from taking effect.
**Solution**: Do NOT use `user_data`. Set `admin_pass` only. Install software manually after SSH access is confirmed.

### Pitfall #3: DATABASE_URL with Special Characters
**Problem**: ECS password may contain `@` and `!` which break URL parsing in `postgresql://user:pass@host:port/db`.
**Solution**: Use a simple DB password without special characters (e.g., `your_db_password`).

### Pitfall #4: config.yaml Environment Variable Substitution
**Problem**: LiteLLM does NOT substitute `${VAR}` in config.yaml. Prisma receives literal `${DATABASE_URL}` and fails.
**Solution**: Write actual values directly in config.yaml. Do NOT use `${MAAS_API_KEY}`, `${DATABASE_URL}`, etc. in the YAML.

### Pitfall #5: docker-compose command Format
**Problem**: `command: sh -c "sleep 10 && litellm --config ..."` causes "Got unexpected extra argument (sh)".
**Solution**: Use `command: ["--config", "/app/config/config.yaml"]`. The litellm image entrypoint handles execution.

### Pitfall #6: MaaS Model Names
**Problem**: Using display names like `DeepSeek-V3.1` or `DeepSeek-R1-0528` causes "Invalid model" errors.
**Solution**: Use exact API model IDs from MaaS: `deepseek-v3.1-terminus`, `deepseek-r1-250528`, etc. Query with:
```bash
curl https://api-ap-southeast-1.modelarts-maas.com/openai/v1/models \
  -H "Authorization: Bearer <MAAS_API_KEY>"
```

### Pitfall #7: MaaS Anthropic Rate Limit
**Problem**: Health check shows Anthropic models as "unhealthy" with rate limit error (1 req/sec).
**Solution**: This is a false alarm from concurrent health checks. Anthropic models work fine for actual requests.

### Pitfall #8: GA Terraform Provider Limitations
**Problem**: GA Terraform provider only supports `EIP` resource_type, not `CUSTOM`. GA SDK doesn't include `la-north-2` region.
**Solution**: Use GA Python SDK with custom Region pointing to `https://ga.myhuaweicloud.com` global endpoint.

## Final Deployment Summary

| Component | Value |
|---|---|
| ECS Region | la-north-2 (Mexico 2) |
| ECS Spec | c9.large.2 (2vCPU/4GB) |
| ECS Image | Ubuntu 24.04 server 64bit |
| ECS User | root |
| ECS Password | &lt;ECS_PASSWORD&gt; |
| LiteLLM Endpoint | http://<ECS_PUBLIC_IP>:4000 |
| GA Anycast IP | <GA_ANYCAST_IP> |
| MaaS Region | ap-southeast-1 (Hong Kong) |
| Healthy Models (OpenAI) | 7 |
| Healthy Models (Anthropic) | 7 |
| DB Password | &lt;DB_PASSWORD&gt; |
| EIP Bandwidth | 10Mbps (traffic mode) |

## Quick Verification Commands

```bash
# SSH access
ssh root@<ECS_PUBLIC_IP>

# Check containers
ssh root@<ECS_PUBLIC_IP> 'docker ps'

# Health check
curl -s http://<ECS_PUBLIC_IP>:4000/health \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>"

# Test model call
curl -s http://<ECS_PUBLIC_IP>:4000/chat/completions \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v3.2","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'

# Check GA routing
ssh root@<ECS_PUBLIC_IP> 'grep modelarts /etc/hosts'

# Check LiteLLM logs
ssh root@<ECS_PUBLIC_IP> 'docker logs litellm_proxy --tail 20'
```
