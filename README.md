# Huawei Cloud LiteLLM Proxy 部署指南 / Deployment Skill

---

## 概述 / Overview

**中文**：在华为云 ECS（墨西哥2区）上部署 LiteLLM Proxy，通过 GA 全球加速访问香港 MaaS 服务，同时支持 OpenAI 和 Anthropic 兼容接口。

**English**: Deploy LiteLLM Proxy on Huawei Cloud ECS (Mexico 2) with GA acceleration to MaaS Hong Kong, supporting both OpenAI and Anthropic compatible interfaces.

---

## 架构 / Architecture

### 总体架构图 / Overall Architecture Diagram

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
│  │  Security Group: litellm_sg (全放通 / Full open)                   │       │
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
│  │  Acceleration Area: OUTOFCM (中国大陆以外 / Outside mainland China)   │      │
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

### 数据流图 / Data Flow Diagram

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

### LiteLLM 内部路由 / Internal Routing

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

---

## 前置条件 / Prerequisites

- 华为云账号及 AK/SK / Huawei Cloud account with AK/SK
- MaaS API Key（香港区域）/ MaaS API Key (Hong Kong region)
- Terraform >= 1.0，huaweicloud provider >= 1.70.0

---

## 步骤 1：Terraform 基础设施 / Step 1: Terraform Infrastructure

### 1.1 关键配置说明 / Key Configuration Notes

- **区域 / Region**: `la-north-2`（墨西哥2区 / Mexico 2）
- **镜像 / Image**: Ubuntu 24.04（不能用 22.04，见坑 #1 / NOT 22.04, see Pitfall #1）
- **ECS 密码 / ECS Password**: 不能含特殊字符，否则 DATABASE_URL 会解析失败 / Must not contain special chars that break URL encoding
- **不要用 user_data**，见坑 #2 / DO NOT use user_data, see Pitfall #2
- **EIP 带宽 / EIP Bandwidth**: Docker 拉镜像时临时调到 100Mbps，部署后降到 10Mbps / Temporarily 100Mbps during pull, then 10Mbps

### 1.2 main.tf 要点 / Essentials

```hcl
data "huaweicloud_images_image" "ubuntu" {
  name_regex = "^Ubuntu 24.04"   # 必须用 24.04 / MUST use 24.04, not 22.04
  most_recent = true
}

resource "huaweicloud_compute_instance" "litellm_ecs" {
  name              = "litellm-proxy-ecs"
  image_id          = data.huaweicloud_images_image.ubuntu.id
  flavor_id         = "c9.large.2"
  admin_pass        = var.ecs_password
  # 不要设置 user_data - 会导致 admin_pass 失效
  # DO NOT set user_data - it breaks admin_pass via cloud-init
  agency_name       = huaweicloud_identity_agency.litellm_agency.name
}
```

### 1.3 安全组 / Security Group

测试环境全放通，生产环境需收紧 / Full open for testing; restrict in production:

```hcl
# TCP 1-65535 ingress/egress, UDP 1-65535 ingress/egress, ICMP ingress/egress
```

### 1.4 执行 / Apply

```bash
terraform init
terraform apply -auto-approve
```

---

## 步骤 2：SSH 访问 / Step 2: SSH Access

```bash
ssh root@<EIP>   # 密码 / Password: <ECS_PASSWORD>
```

**重要 / IMPORTANT**: 用 `root` 用户，不是 `ubuntu`。华为云 Ubuntu 24.04 默认开启 root 密码登录。/ Use `root` user, NOT `ubuntu`. Ubuntu 24.04 on Huawei Cloud enables root password login by default.

---

## 步骤 3：安装 Docker / Step 3: Docker Installation

```bash
ssh root@<EIP> 'curl -fsSL https://get.docker.com | sh'
```

---

## 步骤 4：上传配置文件 / Step 4: Upload Configuration Files

```bash
scp config.yaml root@<EIP>:/opt/litellm/config/config.yaml
scp docker-compose.yml root@<EIP>:/opt/litellm/docker-compose.yml
```

### 4.1 config.yaml - 模型配置 / Model Configuration

MaaS 模型名称（来自 API 文档）/ MaaS model names (from API documentation):

| 模型版本 / Model Version | OpenAI `model` 参数 | Anthropic `model` 参数 |
|---|---|---|
| DeepSeek-V4-Flash | `deepseek-v4-flash` | `deepseek-v4-flash` |
| DeepSeek-V3.1 | `deepseek-v3.1-terminus` | `deepseek-v3.1-terminus` |
| DeepSeek-V3 | `DeepSeek-V3` | `DeepSeek-V3` |
| DeepSeek-V3.2 | `deepseek-v3.2` | `deepseek-v3.2` |
| DeepSeek-R1-0528 | `deepseek-r1-250528` | `deepseek-r1-250528` |
| GLM-5 | `glm-5` | `glm-5` |
| GLM-5.1 | `glm-5.1` | `glm-5.1` |

**API 端点 / API Endpoints:**
- OpenAI 兼容 / compatible: `https://api-ap-southeast-1.modelarts-maas.com/openai/v1`
- Anthropic 兼容 / compatible: `https://api-ap-southeast-1.modelarts-maas.com/anthropic`

**认证 / Auth:**
- OpenAI: `Authorization: Bearer <MAAS_API_KEY>`
- Anthropic: `x-api-key: <MAAS_API_KEY>`（litellm 自动处理 / handled automatically by litellm）

### 4.2 config.yaml 模板 / Template

```yaml
model_list:
  # OpenAI 兼容接口 / OpenAI compatible interface
  - model_name: deepseek-v4-flash
    litellm_params:
      model: deepseek-v4-flash
      api_base: https://api-ap-southeast-1.modelarts-maas.com/openai/v1
      api_key: <MAAS_API_KEY>
      custom_llm_provider: openai

  # Anthropic 兼容接口 / Anthropic compatible interface
  - model_name: deepseek-v4-flash-anthropic
    litellm_params:
      model: deepseek-v4-flash
      api_base: https://api-ap-southeast-1.modelarts-maas.com/anthropic
      api_key: <MAAS_API_KEY>
      custom_llm_provider: anthropic

  # ... 对所有模型重复 / repeat for all models

general_settings:
  master_key: <LITELLM_MASTER_KEY>  # 写实际值，不要用 ${VAR} / Write actual value, NOT ${VAR}
  otel: false

# 不要在 environment_variables 里放 DATABASE_URL 或 REDIS_URL
# 不要用 ${VAR} 语法 - litellm 不会在 config.yaml 里替换环境变量
# DO NOT put DATABASE_URL or REDIS_URL in environment_variables section
# DO NOT use ${VAR} syntax - litellm does NOT substitute env vars in config.yaml
```

### 4.3 docker-compose.yml 模板 / Template

```yaml
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: litellm
      POSTGRES_PASSWORD: <DB_PASSWORD>  # 避免特殊字符 (@!#) / Avoid special chars (@!#)
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
    command: ["--config", "/app/config/config.yaml"]  # 不要用 sh -c "..." / NOT sh -c "..."
```

---

## 步骤 5：启动服务 / Step 5: Start Services

```bash
ssh root@<EIP> 'cd /opt/litellm && MAAS_API_KEY=<KEY> docker compose up -d'
```

等待约 30 秒启动，然后验证 / Wait ~30s for startup, then verify:

```bash
curl http://<EIP>:4000/health -H "Authorization: Bearer <MASTER_KEY>"
```

---

## 步骤 6：GA 全球加速配置 / Step 6: GA (Global Accelerator) Setup

### 6.1 通过 API 创建 GA / Create GA via API

Terraform provider 有局限性（不支持 CUSTOM 类型端点组）。GA 是全球服务，使用端点 `https://ga.myhuaweicloud.com`，区域 `la-north-2`。

GA Terraform provider has limitations (doesn't support CUSTOM endpoint type). GA is a global service. Use endpoint `https://ga.myhuaweicloud.com` with region `la-north-2`.

所需参数 / Required parameters:
- **Accelerator**: area = `OUTOFCM`（中国大陆以外 / outside mainland China）
- **Listener**: protocol = TCP, port = 443
- **Endpoint Group**: region_id = `ap-southeast-1`（香港 / Hong Kong）
- **Endpoint**: resource_type = EIP, 使用 MaaS 端点的 EIP / use MaaS endpoint EIP

### 6.2 配置 ECS /etc/hosts / Configure ECS /etc/hosts

```bash
ssh root@<EIP> 'echo "<GA_ANYCAST_IP> api-ap-southeast-1.modelarts-maas.com" >> /etc/hosts'
```

将所有 MaaS API 流量通过 GA 加速器路由 / This routes all MaaS API traffic through GA accelerator.

### 6.3 验证 GA / Verify GA

```bash
ssh root@<EIP> 'curl -sk https://api-ap-southeast-1.modelarts-maas.com/openai/v1/models \
  -H "Authorization: Bearer <MAAS_API_KEY>"'
```

---

## 步骤 7：EIP 带宽优化 / Step 7: EIP Bandwidth Optimization

```hcl
# Docker 拉镜像时（litellm 镜像约 1.5GB）/ During Docker image pull (~1.5GB):
bandwidth { size = 100 }

# 部署完成后 / After deployment complete:
bandwidth { size = 10 }
```

---

## 踩坑与解决方案 / Pitfalls & Solutions

### 坑 #1：Ubuntu 22.04 SSH 登录失败 / Pitfall #1: Ubuntu 22.04 SSH Login Fails

**问题 / Problem**: 华为云 Ubuntu 22.04 默认禁用 root 密码登录。`admin_pass` 设了密码但 SSH 拒绝连接。/ Ubuntu 22.04 on Huawei Cloud disables root password login by default. `admin_pass` sets the password but SSH rejects it.

**解决 / Solution**: 用 Ubuntu 24.04，默认开启 root 密码登录。/ Use Ubuntu 24.04, which enables root password login by default.

### 坑 #2：user_data 导致 admin_pass 失效 / Pitfall #2: user_data Breaks admin_pass

**问题 / Problem**: 重的 user_data 脚本（apt-get upgrade、Docker 安装）导致 cloud-init 超时或失败，`admin_pass` 不生效。/ Heavy user_data scripts cause cloud-init to timeout or fail, which prevents `admin_pass` from taking effect.

**解决 / Solution**: 不用 `user_data`，只设 `admin_pass`，SSH 确认后再手动安装软件。/ Do NOT use `user_data`. Set `admin_pass` only. Install software manually after SSH access is confirmed.

### 坑 #3：DATABASE_URL 含特殊字符 / Pitfall #3: DATABASE_URL with Special Characters

**问题 / Problem**: ECS 密码可能含 `@` 和 `!`，会破坏 `postgresql://user:pass@host:port/db` 的 URL 解析。/ ECS password may contain `@` and `!` which break URL parsing in `postgresql://user:pass@host:port/db`.

**解决 / Solution**: 用不含特殊字符的简单数据库密码（如 `your_db_password`）。/ Use a simple DB password without special characters (e.g., `your_db_password`).

### 坑 #4：config.yaml 环境变量替换 / Pitfall #4: config.yaml Environment Variable Substitution

**问题 / Problem**: LiteLLM 不会在 config.yaml 里替换 `${VAR}`。Prisma 收到字面 `${DATABASE_URL}` 后报错。/ LiteLLM does NOT substitute `${VAR}` in config.yaml. Prisma receives literal `${DATABASE_URL}` and fails.

**解决 / Solution**: 在 config.yaml 里直接写实际值，不要用 `${MAAS_API_KEY}`、`${DATABASE_URL}` 等。/ Write actual values directly in config.yaml. Do NOT use `${MAAS_API_KEY}`, `${DATABASE_URL}`, etc. in the YAML.

### 坑 #5：docker-compose command 格式 / Pitfall #5: docker-compose command Format

**问题 / Problem**: `command: sh -c "sleep 10 && litellm --config ..."` 导致 "Got unexpected extra argument (sh)"。/ `command: sh -c "sleep 10 && litellm --config ..."` causes "Got unexpected extra argument (sh)".

**解决 / Solution**: 用 `command: ["--config", "/app/config/config.yaml"]`，litellm 镜像 entrypoint 会处理执行。/ Use `command: ["--config", "/app/config/config.yaml"]`. The litellm image entrypoint handles execution.

### 坑 #6：MaaS 模型名称 / Pitfall #6: MaaS Model Names

**问题 / Problem**: 用显示名如 `DeepSeek-V3.1` 或 `DeepSeek-R1-0528` 会导致 "Invalid model" 错误。/ Using display names like `DeepSeek-V3.1` or `DeepSeek-R1-0528` causes "Invalid model" errors.

**解决 / Solution**: 用 MaaS 的精确 API 模型 ID：`deepseek-v3.1-terminus`、`deepseek-r1-250528` 等。查询方法：/ Use exact API model IDs from MaaS: `deepseek-v3.1-terminus`, `deepseek-r1-250528`, etc. Query with:

```bash
curl https://api-ap-southeast-1.modelarts-maas.com/openai/v1/models \
  -H "Authorization: Bearer <MAAS_API_KEY>"
```

### 坑 #7：MaaS Anthropic 速率限制 / Pitfall #7: MaaS Anthropic Rate Limit

**问题 / Problem**: 健康检查显示 Anthropic 模型 "unhealthy"，实际是并发健康检查触发速率限制（1 req/sec）。/ Health check shows Anthropic models as "unhealthy" with rate limit error (1 req/sec).

**解决 / Solution**: 这是误报，实际请求时 Anthropic 模型正常工作。/ This is a false alarm from concurrent health checks. Anthropic models work fine for actual requests.

### 坑 #8：GA Terraform Provider 局限 / Pitfall #8: GA Terraform Provider Limitations

**问题 / Problem**: GA Terraform provider 只支持 `EIP` resource_type，不支持 `CUSTOM`。GA SDK 不含 `la-north-2` 区域。/ GA Terraform provider only supports `EIP` resource_type, not `CUSTOM`. GA SDK doesn't include `la-north-2` region.

**解决 / Solution**: 用 GA Python SDK 配自定义 Region 指向 `https://ga.myhuaweicloud.com` 全球端点。/ Use GA Python SDK with custom Region pointing to `https://ga.myhuaweicloud.com` global endpoint.

---

## 最终部署摘要 / Final Deployment Summary

| 组件 / Component | 值 / Value |
|---|---|
| ECS 区域 / Region | la-north-2 (Mexico 2) |
| ECS 规格 / Spec | c9.large.2 (2vCPU/4GB) |
| ECS 镜像 / Image | Ubuntu 24.04 server 64bit |
| ECS 用户 / User | root |
| ECS 密码 / Password | &lt;ECS_PASSWORD&gt; |
| LiteLLM 端点 / Endpoint | http://&lt;ECS_PUBLIC_IP&gt;:4000 |
| GA Anycast IP | &lt;GA_ANYCAST_IP&gt; |
| MaaS 区域 / Region | ap-southeast-1 (Hong Kong) |
| 健康模型 (OpenAI) / Healthy Models | 7 |
| 健康模型 (Anthropic) / Healthy Models | 7 |
| DB 密码 / Password | &lt;DB_PASSWORD&gt; |
| EIP 带宽 / Bandwidth | 10Mbps (traffic mode) |

---

## 快速验证命令 / Quick Verification Commands

```bash
# SSH 访问 / SSH access
ssh root@<ECS_PUBLIC_IP>

# 检查容器 / Check containers
ssh root@<ECS_PUBLIC_IP> 'docker ps'

# 健康检查 / Health check
curl -s http://<ECS_PUBLIC_IP>:4000/health \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>"

# 测试模型调用 / Test model call
curl -s http://<ECS_PUBLIC_IP>:4000/chat/completions \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v3.2","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'

# 检查 GA 路由 / Check GA routing
ssh root@<ECS_PUBLIC_IP> 'grep modelarts /etc/hosts'

# 查看 LiteLLM 日志 / Check LiteLLM logs
ssh root@<ECS_PUBLIC_IP> 'docker logs litellm_proxy --tail 20'
```
