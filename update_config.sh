#!/usr/bin/env bash
set -e

PROJECT_DIR="/opt/litellm-proxy"
OLD_CFG="${PROJECT_DIR}/config.yaml"
NEW_CFG="${PROJECT_DIR}/config.yaml.new"

# 從現有設定提取金鑰
MASTER_KEY="$(grep -oP '(?<=master_key: ")[^"]+' "${OLD_CFG}")"
DB_PASSWORD="$(grep -oP '(?<=postgresql:\/\/litellm:)[^@]+(?=@db)' "${OLD_CFG}")"
OPENROUTER_KEY="$(tr -d '[:space:]' < "${PROJECT_DIR}/.openrouter_key")"

if [ -z "${MASTER_KEY}" ] || [ -z "${DB_PASSWORD}" ] || [ -z "${OPENROUTER_KEY}" ]; then
    echo "錯誤：無法從現有設定提取金鑰"
    exit 1
fi

cat <<EOF > "${NEW_CFG}"
model_list:
  # 具名模型必須明確列出，否則管理 UI 的 Models 下拉選單不會顯示
  # （/v1/models 僅回傳具名 model_name，通配項 z-ai/* 與 * 會被排除）

  # z-ai 旗艦版：排除原廠 Z.AI 節點，改走第三方節點（保留 require_parameters 以維持工具呼叫）
  - model_name: "z-ai/glm-5.3"
    litellm_params:
      model: "openrouter/z-ai/glm-5.3"
      api_key: "${OPENROUTER_KEY}"
      extra_body:
        provider:
          ignore: ["z-ai"]
          require_parameters: true

  # glm-5.3-flash：排除原廠 Z.AI 節點，走第三方節點（多模態低成本版）
  - model_name: "z-ai/glm-5.3-flash"
    litellm_params:
      model: "openrouter/z-ai/glm-5.3-flash"
      api_key: "${OPENROUTER_KEY}"
      extra_body:
        provider:
          ignore: ["z-ai"]

  # bge-m3 embedding 模型（轉發至 OpenRouter embeddings 端點，供 mem0.shutokou.cc 使用）
  - model_name: "baai/bge-m3"
    litellm_params:
      model: "openai/baai/bge-m3"
      api_base: "https://openrouter.ai/api/v1"
      api_key: "${OPENROUTER_KEY}"
      mode: embedding
      input_cost_per_token: 0.00000001

  # deepseek V4.1 Flash（1017 版）：具名登錄，且排除原廠 DeepSeek 節點
  - model_name: "deepseek/deepseek-v4.1-flash-1017"
    litellm_params:
      model: "openrouter/deepseek/deepseek-v4.1-flash-1017"
      api_key: "${OPENROUTER_KEY}"
      extra_body:
        provider:
          ignore: ["deepseek"]

  # glm-5.2：排除原廠 Z.AI 節點，走第三方節點（保留 require_parameters 維持工具呼叫）
  - model_name: "z-ai/glm-5.2"
    litellm_params:
      model: "openrouter/z-ai/glm-5.2"
      api_key: "${OPENROUTER_KEY}"
      extra_body:
        provider:
          ignore: ["z-ai"]
          require_parameters: true

  # gpt-5.6-luna：具名登錄供管理 UI 顯示（OpenRouter 最優路由）
  - model_name: "openai/gpt-5.6-luna"
    litellm_params:
      model: "openrouter/openai/gpt-5.6-luna"
      api_key: "${OPENROUTER_KEY}"

  # claude-sonnet-4.6：具名登錄供管理 UI 顯示（OpenRouter 最優路由）
  - model_name: "anthropic/claude-sonnet-4.6"
    litellm_params:
      model: "openrouter/anthropic/claude-sonnet-4.6"
      api_key: "${OPENROUTER_KEY}"

  # z-ai/* 通配模型維持固定路由至原廠 Z.AI（原生支援 Function Calling）
  - model_name: "z-ai/*"
    litellm_params:
      model: "openrouter/z-ai/*"
      api_key: "${OPENROUTER_KEY}"
      extra_body:
        provider:
          order: ["z-ai"]
          require_parameters: true

  # 其餘模型維持萬用透傳
  - model_name: "*"
    litellm_params:
      model: "openrouter/*"
      api_key: "${OPENROUTER_KEY}"

general_settings:
  database_url: "postgresql://litellm:${DB_PASSWORD}@db:5432/litellm"
  master_key: "${MASTER_KEY}"
  disable_env_credential_login: true

litellm_settings:
  drop_params: True
  telemetry: False
  send_spend_to_client: True
  # 每日預算重置改依台北時間午夜，而非預設 UTC 午夜
  timezone: "Asia/Taipei"
  budget_reset_time: "00:00"
EOF

chmod 600 "${NEW_CFG}"
cp "${OLD_CFG}" "${OLD_CFG}.bak"
mv "${NEW_CFG}" "${OLD_CFG}"

# PROJECT_DIR 權限為 700 root，須以 root 身分在該目錄下執行 compose
sudo docker compose -f "${PROJECT_DIR}/docker-compose.yml" restart litellm

echo "CONFIG_UPDATED"