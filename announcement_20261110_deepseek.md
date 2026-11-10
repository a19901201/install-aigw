# 公告：新增 DeepSeek V4.1 Flash 1017 模型

日期：2026-11-10
閘道：aigw.shutokou.cc

閘道已新增模型 `deepseek/deepseek-v4.1-flash-1017`（DeepSeek V4.1 Flash 1017 版，經 OpenRouter 路由），並已放行給 JR、Shor、KZ、YU。

## 各金鑰可用模型

- JR、KZ、YU：`z-ai/glm-5.3-flash`、`deepseek/deepseek-v4.1-flash-1017`
- Shor：`z-ai/glm-5.3`、`z-ai/glm-5.3-flash`、`deepseek/deepseek-v4.1-flash-1017`
- 額度與限速維持不變：每日（24 小時週期）JR/KZ/YU 10 美元、Shor 50 美元，每分鐘 30 次請求。

## 使用場景建議：glm 與 deepseek 怎麼選

兩款模型皆為 Flash 等級：回應速度快、單價低，日常使用都很省額度。差別在擅長的任務類型：

- 日常問答、中文寫作、社群貼文、客服回覆：用 `glm-5.3-flash`。中文表達自然、回應快，是預設首選。
- 需要深度長文、嚴謹的段落結構：Shor 可用 `glm-5.3`（僅 Shor 有權限）。
- 圖片辨識、截圖理解：一律用 `glm-5.3-flash`。`glm-5.3` 為純文字模型，DeepSeek 亦不支援視覺輸入。
- 程式碼撰寫、除錯、重構、技術文件：用 `deepseek/deepseek-v4.1-flash-1017`。程式相關任務表現強，適合貼上整段程式碼要求修改或解釋。
- 數學計算、邏輯推理、資料分析：用 `deepseek`。推理鏈較穩定，多步驟推導不易中途出錯。
- 長文件閱讀與問答（整份文件貼入後提問）：用 `deepseek`，長上下文處理較佳。
- 高頻輕量任務（摘要、分類、格式轉換、簡短翻譯）：用 `glm-5.3-flash`，延遲最低、最省額度。

簡單原則：中文日常任務先找 glm，程式與推理任務找 deepseek；不確定時先用 `glm-5.3-flash` 試，效果不理想再換 `deepseek` 重試。

## 注意事項

- 白名單外的模型仍會被拒（401）。若需開放其他模型，請向管理員申請。
- 模型名稱請完整使用，例如 `deepseek/deepseek-v4.1-flash-1017`，僅寫 `deepseek` 無法路由。
