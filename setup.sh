#!/usr/bin/env bash
set -e

PROJECT_DIR="/opt/litellm-proxy"
DATA_DIR="${PROJECT_DIR}/data"
DOMAIN="aigw.shutokou.cc"
PORT="4000"
KEY_FILE="${PROJECT_DIR}/.openrouter_key"

# 改由 600 權限檔案讀取金鑰，避免命令列歷史洩漏
if [ -f "${KEY_FILE}" ]; then
    OPENROUTER_KEY="$(tr -d '[:space:]' < "${KEY_FILE}")"
else
    echo "錯誤：找不到金鑰檔案 ${KEY_FILE}！"
    echo "使用方式: 先將 OpenRouter API 金鑰寫入 ${KEY_FILE}（權限 600）"
    exit 1
fi

if [ -z "${OPENROUTER_KEY}" ]; then
    echo "錯誤：金鑰檔案內容為空！"
    exit 1
fi

# 1. 產生高強度隨機管理主密鑰與資料庫密碼
MASTER_KEY="sk-admin-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
DB_PASSWORD="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
#!/usr/bin/env bash
set -e

PROJECT_DIR="/opt/litellm-proxy"
DATA_DIR="${PROJECT_DIR}/data"
DOMAIN="aigw.shutokou.cc"
PORT="4000"
KEY_FILE="${PROJECT_DIR}/.openrouter_key"

# 改由 600 權限檔案讀取金鑰，避免命令列歷史洩漏
if [ -f "${KEY_FILE}" ]; then
    OPENROUTER_KEY="$(tr -d '[:space:]' < "${KEY_FILE}")"
else
    echo "錯誤：找不到金鑰檔案 ${KEY_FILE}！"
    echo "使用方式: 先將 OpenRouter API 金鑰寫入 ${KEY_FILE}（權限 600）"
    exit 1
fi

if [ -z "${OPENROUTER_KEY}" ]; then
    echo "錯誤：金鑰檔案內容為空！"
    exit 1
fi


echo "=== 1. 建立專案目錄與設定權限 ==="
mkdir -p "${DATA_DIR}"
chmod 700 "${PROJECT_DIR}"
chmod 700 "${DATA_DIR}"
chmod 600 "${KEY_FILE}"

echo "=== 2. 建立 LiteLLM 安全透傳設定檔 ==="
cat <<EOF > "${PROJECT_DIR}/config.yaml"
model_list:
  - model_name: "*"
    litellm_params:
      model: openrouter/*
      api_key: "${OPENROUTER_KEY}"

general_settings:
  database_url: "postgresql://litellm:${DB_PASSWORD}@db:5432/litellm"
  master_key: "${MASTER_KEY}"
  pass_through_endpoints:
    - path: "/v1/chat/completions"

litellm_settings:
  drop_params: True
  telemetry: False
  send_spend_to_client: True
EOF

echo "=== 3. 建立 Docker Compose 編排檔 ==="
cat <<EOF > "${PROJECT_DIR}/docker-compose.yml"
version: '3.8'

services:
  db:
    image: postgres:16-alpine
    container_name: litellm-db
    restart: always
    environment:
      - POSTGRES_USER=litellm
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=litellm
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U litellm -d litellm"]
      interval: 5s
      timeout: 5s
      retries: 10

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    restart: always
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "${PORT}:4000"
    volumes:
      - ./config.yaml:/app/config.yaml
    environment:
      - STORE_MODEL_IN_DB=True
      - LITELLM_MASTER_KEY=${MASTER_KEY}
      - TZ=Asia/Taipei
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    healthcheck:
      test: ["CMD-SHELL", "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:4000
        -H "Content-Type: application/json" \
        -d "{
            \"key_alias\": \"${USER}\",
            \"max_budget\": 10.0,
            \"budget_duration\": \"24h\",
            \"rpm_limit\": 30,
            \"duration\": null
        }")

    KEY=$(echo "${RESPONSE}" | grep -o '"key":"[^"]*' | cut -d'"' -f4)

    if [ -n "${KEY}" ]; then
        [ -z "${TEST_KEY}" ] && TEST_KEY="${KEY}"
        cat <<EOF >> "${CREDENTIALS_FILE}"
成員代號: ${USER}
專屬密鑰: ${KEY}
預算限制: 每日 10.0 美元 (達上限即封鎖，重開機不重置，隔日恢復)
頻率上限: 每分鐘 30 次請求 (防迴圈異常)
狀態: 啟用中
------------------------------------------------------------
EOF
        echo "已成功生成 ${USER} 密鑰與額度限制。"
    else
        echo "錯誤：生成 ${USER} 密鑰失敗，回應內容：${RESPONSE}"
        exit 1
    fi
done

chmod 600 "${CREDENTIALS_FILE}"

echo "=== 6. 執行端對端自我驗證測試 ==="
echo "使用測試密鑰發送對話請求驗證模型透傳 (z-ai/glm-5.3-flash)..."

TEST_PASSED=false
for i in {1..5}; do
    API_RESPONSE=$(curl -s -X POST "http://127.0.0.1:${PORT}/v1/chat/completions" \
        -H "Authorization: Bearer ${TEST_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "z-ai/glm-5.3-flash",
            "messages": [{"role": "user", "content": "Ping test, please reply OK"}],
            "max_tokens": 10
        }')

    if echo "${API_RESPONSE}" | grep -q "choices"; then
        echo "端對端自我測試成功！模型已正常回應。"
        TEST_PASSED=true
        break
    else
        echo "測試尚未通過 (嘗試 ${i}/5)，回應內容："
        echo "${API_RESPONSE}"
        sleep 3
    fi
done

if [ "$TEST_PASSED" = false ]; then
    echo "錯誤：模型透傳測試未通過，請檢查 OpenRouter 金鑰或額度！"
    exit 1
fi

echo ""
cat "${CREDENTIALS_FILE}"
echo ""
echo "=== 全部任務已完成，服務已確認完全跑通！ ==="