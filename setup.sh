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

echo "=== 1. 建立專案目錄與設定權限 ==="
mkdir -p "${DATA_DIR}"
chmod 700 "${PROJECT_DIR}"
chmod 700 "${DATA_DIR}"
chmod 600 "${KEY_FILE}"

echo "=== 2. 建立 LiteLLM 安全透傳設定檔 ==="
cat <<EOF > "${PROJECT_DIR}/config.yaml"
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

echo "=== 3. 建立 Docker Compose 編排檔 ==="
cat <<EOF > "${PROJECT_DIR}/docker-compose.yml"
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
      test: ["CMD-SHELL", "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:4000/health/liveliness\")' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

echo "=== 4. 啟動容器並等候服務就緒 ==="
cd "${PROJECT_DIR}"
docker compose down || true
docker compose up -d

MAX_RETRIES=90
COUNT=0
until curl -s -f "http://127.0.0.1:${PORT}/health/liveliness" > /dev/null || [ $COUNT -eq $MAX_RETRIES ]; do
    sleep 2
    COUNT=$((COUNT + 1))
done

if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "錯誤：服務未能在時間內就緒，請檢查容器日誌：docker compose logs"
    exit 1
fi
echo "LiteLLM 服務已於本機連接埠 ${PORT} 正常運作。"

echo "=== 5. 生成 5 位成員專屬限額密鑰 ==="
echo "============================================================"
echo "              團隊成員連線與專屬金鑰資訊卡"
echo "============================================================"
echo "服務網域: https://${DOMAIN}/v1"
echo "內網端點: http://$(hostname -I | awk '{print $1}'):${PORT}/v1"
echo "管理密鑰: ${MASTER_KEY}"
echo "建置時間: $(TZ=Asia/Taipei date '+%Y-%m-%d %H:%M:%S')"
echo "------------------------------------------------------------"

TEST_KEY=""
USERS=("Member_1" "Member_2" "Member_3" "Member_4" "Member_5")
MEMBER_MODEL="z-ai/glm-5.3-flash"

for USER in "${USERS[@]}"; do
    RESPONSE=$(curl -s -X POST "http://127.0.0.1:${PORT}/key/generate" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"key_alias\": \"${USER}\",
            \"max_budget\": 10.0,
            \"budget_duration\": \"24h\",
            \"rpm_limit\": 30,
            \"models\": [\"${MEMBER_MODEL}\"],
            \"duration\": null
        }")

    KEY=$(echo "${RESPONSE}" | grep -o '"key":"[^"]*' | cut -d'"' -f4)

    if [ -n "${KEY}" ]; then
        [ -z "${TEST_KEY}" ] && TEST_KEY="${KEY}"
        cat <<EOF
成員代號: ${USER}
專屬密鑰: ${KEY}
允許模型: ${MEMBER_MODEL} (白名單限制)
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

echo "=== 6. 執行端對端自我驗證測試 ==="
echo "使用測試密鑰發送對話請求驗證模型透傳 (${MEMBER_MODEL})..."

TEST_PASSED=false
for i in {1..5}; do
    API_RESPONSE=$(curl -s -X POST "http://127.0.0.1:${PORT}/v1/chat/completions" \
        -H "Authorization: Bearer ${TEST_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${MEMBER_MODEL}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Ping test, please reply OK\"}],
            \"max_tokens\": 10
        }")

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
echo "=== 全部任務已完成，服務已確認完全跑通！ ==="
echo "（資安提醒：成員密鑰僅顯示於本次部署輸出，請立即抄錄分發；可於管理 UI 查詢用量，但密鑰不再落地為明文檔案）"