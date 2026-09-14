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
  # z-ai 系列模型固定路由至 OpenRouter 的 Z.AI 官方供應商（原生支援 Function Calling）
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

litellm_settings:
  drop_params: True
  telemetry: False
  send_spend_to_client: True
EOF

chmod 600 "${NEW_CFG}"
cp "${OLD_CFG}" "${OLD_CFG}.bak"
mv "${NEW_CFG}" "${OLD_CFG}"

cd "${PROJECT_DIR}"
docker compose restart litellm

echo "CONFIG_UPDATED"