# LiteLLM Virtual Key 隔离方案

## 概述
将 master key 仅用于管理，创建4个 virtual key 实现业务隔离。

## Step 0: 环境确认

| 项目 | 值 |
|------|-----|
| LiteLLM Version | 1.82.6 |
| Postgres | 启用 |
| Redis | 启用 |
| Proxy URL | http://101.44.24.252:4000 |
| Admin URL | http://101.44.24.252:4001/ui |
| Master Key 来源 | CSMS → .env.secrets → LITELLM_MASTER_KEY |

## Step 1: 模型池与分类

### 全部14个模型
```
deepseek-r1-250528              deepseek-r1-250528-anthropic
DeepSeek-V3                     DeepSeek-V3-anthropic
deepseek-v3.1-terminus          deepseek-v3.1-terminus-anthropic
deepseek-v3.2                   deepseek-v3.2-anthropic
deepseek-v4-flash               deepseek-v4-flash-anthropic
glm-5                           glm-5-anthropic
glm-5.1                         glm-5.1-anthropic
```

### 模型分类

| 类别 | 模型 | 说明 |
|------|------|------|
| **fast** | deepseek-v4-flash, deepseek-v3.2, deepseek-v3.1-terminus | 极快极便宜，日常/意图识别首选 |
| **smart** | DeepSeek-V3, glm-5, glm-5.1 | 旗舰推理，中文强 |
| **coding** | deepseek-r1-250528 | R1深度推理链，复杂代码/数学 |
| **anthropic** | 上述模型 + `-anthropic` 后缀 | Anthropic协议passthrough |

分类依据：
- deepseek-v4-flash: 1M上下文，极低价格，通用+代码+工具调用
- deepseek-v3.2/v3.1-terminus: 128K上下文，性价比高
- DeepSeek-V3: 旗舰推理模型
- deepseek-r1-250528: CoT推理链，适合复杂代码和数学
- glm-5/glm-5.1: 智谱旗舰，中文能力强

## Step 2: Virtual Key 策略

| virtual key | 用途 | allowed models | rpm | tpm | max_budget($) | metadata |
|---|---|---|---|---|---|---|
| key-claude-code-dev | Claude Code | coding + smart + fast (含anthropic) | 60 | 500K | 100 | owner=oli, env=dev, purpose=claude-code |
| key-opencode-dev | OpenCode | coding + smart + fast (含anthropic) | 40 | 300K | 50 | owner=oli, env=dev, purpose=opencode |
| key-agent-demo-coding | Coding Agent Demo | fast + smart | 10 | 100K | 20 | owner=oli, env=demo, purpose=coding-agent |
| key-agent-demo-pqrs | PQRs Demo | fast + smart(限) | 10 | 100K | 10 | owner=oli, env=demo, purpose=pqrs-intent |

### 模型权限明细

**key-claude-code-dev** (8 models):
- deepseek-r1-250528, DeepSeek-V3, deepseek-v4-flash, glm-5.1
- + anthropic variants: deepseek-r1-250528-anthropic, DeepSeek-V3-anthropic, deepseek-v4-flash-anthropic, glm-5.1-anthropic

**key-opencode-dev** (11 models):
- deepseek-r1-250528, DeepSeek-V3, deepseek-v4-flash, deepseek-v3.2, glm-5, glm-5.1
- + anthropic variants: deepseek-r1-250528-anthropic, DeepSeek-V3-anthropic, deepseek-v4-flash-anthropic, glm-5-anthropic, glm-5.1-anthropic

**key-agent-demo-coding** (3 models):
- deepseek-v4-flash, DeepSeek-V3, glm-5

**key-agent-demo-pqrs** (3 models):
- deepseek-v4-flash, deepseek-v3.2, glm-5

## Step 3: 创建命令

```bash
# 设置环境
source /opt/litellm/.env.secrets
BASE="http://localhost:4000"
AUTH="Authorization: Bearer $LITELLM_MASTER_KEY"

# 1. key-claude-code-dev
curl -s -X POST "$BASE/key/generate" -H "$AUTH" -H "Content-Type: application/json" -d '{
  "key_alias": "key-claude-code-dev",
  "models": ["deepseek-r1-250528", "DeepSeek-V3", "deepseek-v4-flash", "glm-5.1",
             "deepseek-r1-250528-anthropic", "DeepSeek-V3-anthropic",
             "deepseek-v4-flash-anthropic", "glm-5.1-anthropic"],
  "rpm_limit": 60, "tpm_limit": 500000, "max_budget": 100,
  "metadata": {"owner": "oli", "environment": "dev", "purpose": "claude-code"}
}'

# 2. key-opencode-dev
curl -s -X POST "$BASE/key/generate" -H "$AUTH" -H "Content-Type: application/json" -d '{
  "key_alias": "key-opencode-dev",
  "models": ["deepseek-r1-250528", "DeepSeek-V3", "deepseek-v4-flash", "deepseek-v3.2", "glm-5", "glm-5.1",
             "deepseek-r1-250528-anthropic", "DeepSeek-V3-anthropic",
             "deepseek-v4-flash-anthropic", "glm-5-anthropic", "glm-5.1-anthropic"],
  "rpm_limit": 40, "tpm_limit": 300000, "max_budget": 50,
  "metadata": {"owner": "oli", "environment": "dev", "purpose": "opencode"}
}'

# 3. key-agent-demo-coding
curl -s -X POST "$BASE/key/generate" -H "$AUTH" -H "Content-Type: application/json" -d '{
  "key_alias": "key-agent-demo-coding",
  "models": ["deepseek-v4-flash", "DeepSeek-V3", "glm-5"],
  "rpm_limit": 10, "tpm_limit": 100000, "max_budget": 20,
  "metadata": {"owner": "oli", "environment": "demo", "purpose": "coding-agent"}
}'

# 4. key-agent-demo-pqrs
curl -s -X POST "$BASE/key/generate" -H "$AUTH" -H "Content-Type: application/json" -d '{
  "key_alias": "key-agent-demo-pqrs",
  "models": ["deepseek-v4-flash", "deepseek-v3.2", "glm-5"],
  "rpm_limit": 10, "tpm_limit": 100000, "max_budget": 10,
  "metadata": {"owner": "oli", "environment": "demo", "purpose": "pqrs-intent"}
}'
```

## Step 4: Key 存储

保存到 `/opt/litellm/keys.env` (chmod 600):

```env
LITELLM_BASE_URL=http://<EIP>:4000
LITELLM_ADMIN_URL=http://<EIP>:4001
CLAUDE_CODE_LITELLM_KEY=<key-claude-code-dev>
OPENCODE_LITELLM_KEY=<key-opencode-dev>
AGENT_DEMO_CODING_KEY=<key-agent-demo-coding>
AGENT_DEMO_PQRS_KEY=<key-agent-demo-pqrs>
```

**安全要求**:
- keys.env 不提交 Git
- .gitignore 包含 `*.env` 和 `keys.env`
- chmod 600 权限

## Step 5: 验证结果

### 5.1 模型权限验证

| Key | 期望模型数 | 实际模型数 | 状态 |
|-----|-----------|-----------|------|
| key-claude-code-dev | 8 | 8 | ✅ |
| key-opencode-dev | 11 | 11 | ✅ |
| key-agent-demo-coding | 3 | 3 | ✅ |
| key-agent-demo-pqrs | 3 | 3 | ✅ |

### 5.2 调用验证

| Key | 测试模型 | 结果 |
|-----|---------|------|
| key-claude-code-dev | deepseek-r1-250528 | ✅ 成功 |
| key-opencode-dev | glm-5 | ✅ 成功 |
| key-agent-demo-coding | deepseek-v4-flash | ✅ 成功 |
| key-agent-demo-pqrs | deepseek-v3.2 | ✅ 成功 |

### 5.3 越权验证

| Key | 尝试模型 | 期望 | 实际 |
|-----|---------|------|------|
| key-agent-demo-pqrs | deepseek-r1-250528 | 拒绝 | ✅ 401 |
| key-agent-demo-coding | glm-5.1 | 拒绝 | ✅ 401 |

## 安全原则

1. **master key 仅管理用**: 只用于 `/key/generate`, `/key/list`, `/key/delete` 等管理API
2. **最小权限**: 每个key只能访问其业务所需模型
3. **预算限制**: 每个key有 max_budget 防止超支
4. **速率限制**: rpm_limit + tpm_limit 防止滥用
5. **dev/demo 隔离**: 开发key和demo key完全分离
6. **key 可撤销**: 通过 `/key/delete` 随时 revoke，再 `/key/generate` 重新生成

## 常见错误排查

| 错误 | 原因 | 解决 |
|------|------|------|
| 401 key not allowed to access model | key的models列表不含该模型 | 检查key的allowed models，或用`/key/update`添加 |
| 429 Rate limit exceeded | 超过rpm_limit/tpm_limit | 调整limit或减少请求频率 |
| Budget exceeded | 累计消费超过max_budget | 用`/key/update`提高预算或重置spend |
| Key not found | key已删除或未创建 | 重新`/key/generate` |
