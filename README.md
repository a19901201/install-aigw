# install-aigw
ai中轉站

## 模型清單與管理 UI 下拉選單

管理後台（`/ui`）的 **Virtual Keys → Settings → Models** 下拉選單，選項來源為 `GET /v1/models`，而 `/v1/models` **只回傳具名 `model_name`**，通配路由（如 `z-ai/*`、`*`）不會出現在選單中。

因此：

- **想在 UI 選單看到某個模型**，必須在 `config.yaml` 的 `model_list` 中明確登錄一筆具名 `model_name`。
- **具名登錄不會削弱萬用透傳能力**。`*` 與 `z-ai/*` 通配路由仍保留，未具名的模型仍可透傳，只是不出現在下拉選單。
- **UI 下拉選單無法手動輸入自訂模型名**。這是 LiteLLM 前端 `MultiSelect` 元件的設計：`allowCustomValues` 預設為 `false`，只有少數欄位（例如 pass through routes）開啟該選項。Models 欄位未開啟，因此輸入框僅供搜尋既有選項。若要新增可選模型，請改用 `config.yaml` 登錄後重啟服務。

目前已登錄的具名模型：

- `z-ai/glm-5.3`：**排除**原廠 Z.AI 節點（`provider.ignore: ["z-ai"]`），改走第三方節點，並保留 `require_parameters: true` 以維持 Function Calling。
- `z-ai/glm-5.3-flash`：同上，排除原廠 Z.AI 節點，走第三方節點（原廠節點會擋多模態與工具呼叫參數，且單價較高）。
- `baai/bge-m3`：embedding 模型，供 `mem0.shutokou.cc` 使用。
- `deepseek/deepseek-v4.1-flash-1017`：排除原廠 DeepSeek 節點（`provider.ignore: ["deepseek"]`），2026-11-10 起放行給 JR、Shor、KZ、YU。
- `z-ai/*`（通配）：維持 `provider.order: ["z-ai"]`，鎖定原廠 Z.AI 節點。

新增或修改具名模型後，執行 `update_config.sh` 重新套用並重啟服務。

## 路由控制（OpenRouter provider 指定）

OpenRouter 的 `provider` 區塊只認 **provider slug**（`z-ai`、`deepseek`、`wafer`…），不是模型作者名稱，也不是節點顯示名稱。LiteLLM 需寫在 `litellm_params.extra_body.provider` 才會原樣透傳：

- 只想用原廠：`order: ["z-ai"]` + `require_parameters: true`。
- 只想排除原廠：`ignore: ["z-ai"]`；其他節點由 OpenRouter 依價格與可用性自動挑選。
- `allow_fallbacks` 未設定時預設為 `true`，`ignore` 搭配它才能在被排除節點之外自動換手。

調整路由可直接用腳本改檔（會自動備份成 `config.yaml.bak.<時間戳>`）：

```bash
sudo python3 patch_openrouter_routing.py --dry-run   # 先看差異，內容含遮罩金鑰
sudo python3 patch_openrouter_routing.py             # 實際寫入
docker restart litellm-proxy
```

## 驗證工具

- `check_glm_routing.py`：送出極短請求，再用 generation id 向 OpenRouter 查 `provider_name`，確認實際落點與成本。金鑰一律遮罩輸出。
- `smoke_tool_call.py`：對具名模型各送一筆帶 `tools` 的請求，確認 `finish_reason=tool_calls`，用來驗證 `provider.ignore` 之後 Function Calling 仍正常。

