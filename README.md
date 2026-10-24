# install-aigw
ai中轉站

## 模型清單與管理 UI 下拉選單

管理後台（`/ui`）的 **Virtual Keys → Settings → Models** 下拉選單，選項來源為 `GET /v1/models`，而 `/v1/models` **只回傳具名 `model_name`**，通配路由（如 `z-ai/*`、`*`）不會出現在選單中。

因此：

- **想在 UI 選單看到某個模型**，必須在 `config.yaml` 的 `model_list` 中明確登錄一筆具名 `model_name`。
- **具名登錄不會削弱萬用透傳能力**。`*` 與 `z-ai/*` 通配路由仍保留，未具名的模型仍可透傳，只是不出現在下拉選單。
- **UI 下拉選單無法手動輸入自訂模型名**。這是 LiteLLM 前端 `MultiSelect` 元件的設計：`allowCustomValues` 預設為 `false`，只有少數欄位（例如 pass through routes）開啟該選項。Models 欄位未開啟，因此輸入框僅供搜尋既有選項。若要新增可選模型，請改用 `config.yaml` 登錄後重啟服務。

目前已登錄的具名模型：

- `z-ai/glm-5.3`：固定路由至原廠 Z.AI，保留 `provider.order: ["z-ai"]` 釘選。
- `z-ai/glm-5.3-flash`：走 OpenRouter 最划算路由。
- `baai/bge-m3`：embedding 模型，供 `mem0.shutokou.cc` 使用。

新增或修改具名模型後，執行 `update_config.sh` 重新套用並重啟服務。
