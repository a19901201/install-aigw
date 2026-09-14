# 任務名稱：LiteLLM 原生透傳閘道一鍵自動化部署與多用戶安全限額配給

**專案背景與架構規範：**

* 原始碼庫：`[https://github.com/BerriAI/litellm](https://github.com/BerriAI/litellm)`
* 預編譯映像檔：`ghcr.io/berriai/litellm:main-latest`
* 服務目的：作為 OpenRouter 專屬的無損透傳閘道，供團隊 5 位成員使用，完整保留模型自訂參數與串流傳輸，並提供個別預算硬限制與頻率防護。
* 外部網域：`[https://aigw.shutokou.cc](https://aigw.shutokou.cc)`
* 網路環境：
* 前端邊界由 Cloudflare 彈性模式與 pfSense 搭配 HAProxy 負責安全憑證終止與流量轉發。
* 本地主機無需反向代理容器，直接將主機實體 **4000** 埠監聽區域網路，供 HAProxy 後端節點轉發。


* 儲存架構：使用掛載目錄之 SQLite 單一檔案資料庫（`/app/data/litellm.db`）進行持久化，免除外部資料庫相依。

**資安加固規格：**

* 管理權限：管理主密鑰隨機生成 32 位元高強度字串，禁止使用預設值。
* 預算硬限制：每位成員強制綁定每日 10 美元額度上限（`max_budget: 10.0`, `budget_duration: 24h`），資料庫持久化確保重開機不會重置額度，隔日自動恢復。
* 呼叫頻率限制：每把密鑰設定每分鐘 30 次請求上限（`rpm_limit: 30`），嚴防死循環刷爆費用。
* 隱私與日誌脫敏：關閉遙測追蹤（`telemetry: False`），啟用敏感資訊脫敏（`drop_params: True`）。
* 目錄權限收斂：專案與資料目錄權限嚴格限縮為 `700`，金鑰資訊檔案權限設為 `600`。
* 自檢機制：部署完成後自動以成員密鑰呼叫 `z-ai/glm-5.3-flash` 模型進行端對端驗證，確認跑通才算完成。

---

### 執行任務指引（請輔助程式儲存為 `/opt/litellm-proxy/setup.sh` 並執行）

```bash
#!/usr/bin/env bash
set -e

PROJECT_DIR="/opt/litellm-proxy"
DATA_DIR="${PROJECT_DIR}/data"
DOMAIN="aigw.shutokou.cc"
PORT="4000"
OPENROUTER_KEY="${1}"

if [ -z "${OPENROUTER_KEY}" ]; then
    echo "錯誤：未提供 OpenRouter API 金鑰！"
    echo "使用方式: sudo bash setup.sh <你的_OPENROUTER_API_KEY>"
    exit 1
fi

# 1. 產生高強度隨機管理主密鑰
MASTER_KEY="sk-admin-$(head -c 16 /dev/urandom | xxd -p)"

echo "=== 1. 建立專案目錄與設定權限 ==="
mkdir -p "${DATA_DIR}"
chmod 700 "${PROJECT_DIR}"
chmod 700 "${DATA_DIR}"

echo "=== 2. 建立 LiteLLM 安全透傳設定檔 ==="
cat <<EOF > "${PROJECT_DIR}/config.yaml"
model_list:
  - model_name: "*"
    litellm_params:
      model: openrouter/*
      api_key: "${OPENROUTER_KEY}"

general_settings:
  database_url: "sqlite:////app/data/litellm.db"
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
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    restart: always
    ports:
      - "${PORT}:4000"
    volumes:
      - ./config.yaml:/app/config.yaml
      - ./data:/app/data
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

MAX_RETRIES=30
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
CREDENTIALS_FILE="${PROJECT_DIR}/client_credentials.txt"
cat <<EOF > "${CREDENTIALS_FILE}"
============================================================
              團隊成員連線與專屬金鑰資訊卡
============================================================
服務網域: https://${DOMAIN}/v1
內網端點: http://$(hostname -I | awk '{print $1}'):${PORT}/v1
管理密鑰: ${MASTER_KEY}
建置時間: $(TZ=Asia/Taipei date '+%Y-%m-%d %H:%M:%S')
------------------------------------------------------------
EOF

TEST_KEY=""
USERS=("Member_1" "Member_2" "Member_3" "Member_4" "Member_5")

for USER in "${USERS[@]}"; do
    RESPONSE=$(curl -s -X POST "http://127.0.0.1:${PORT}/key/generate" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
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

```

---

**成員端設定對照說明（部署完成後直接分發）**

* **提供者模式**：切換為通用相容介面模式。
* **API 基礎網址**：`[https://aigw.shutokou.cc/v1](https://aigw.shutokou.cc/v1)`
* **API 密鑰**：填入各自專屬的權杖（`sk-...`）。
* **模型識別碼**：填入 `z-ai/glm-5.3-flash`（或 OpenRouter 上的任意模型標識）。
* **計費與記憶機制**：
  * **金額計算**：LiteLLM 內建各大模型（包含 OpenRouter）的官方定價表。每次呼叫完成後，系統會自動根據「輸入與輸出 Token 數量」乘以「該模型單價」來計算並扣除本次實際花費。
  * **用量記憶**：所有的扣款紀錄與剩餘額度皆即時寫入本機實體的 SQLite 資料庫（`/app/data/litellm.db`）。因採用 Docker Volume 掛載，即便伺服器重開機，只要資料庫檔案存在，系統就能讀取正確的歷史用量，確保額度不會被洗掉。