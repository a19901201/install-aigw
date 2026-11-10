#!/usr/bin/env python3
# 修改 litellm 的 config.yaml：讓三個具名模型明確排除原廠節點
#   z-ai/glm-5.3                  -> provider.ignore: ["z-ai"]（移除 order: ["z-ai"]）
#   z-ai/glm-5.3-flash            -> provider.ignore: ["z-ai"]
#   deepseek/deepseek-v4.1-flash-1017 -> provider.ignore: ["deepseek"]
# 先用 --dry-run 預覽差異，正式寫入時自動備份成 config.yaml.bak.<timestamp>。
# OpenRouter 官方文件：provider.order / provider.ignore / provider.only 都吃 provider slug
# （z-ai、deepseek），見 https://openrouter.ai/docs/features/provider-routing
import re
import shutil
import sys
import time

CONFIG = "/opt/litellm-proxy/config.yaml"

# 註解更新（註解行位於 model_name 之前，必須在全檔層級替換）
COMMENTS = [
    (
        "  # z-ai 旗艦版：固定路由至原廠 Z.AI（原生支援 Function Calling）",
        "  # z-ai 旗艦版：排除原廠 Z.AI 節點，改走第三方節點（保留 require_parameters 以維持工具呼叫）",
    ),
    (
        "  # glm-5.3-flash 開放 OpenRouter 最划算路由（第三方節點較便宜，多模態低成本版）",
        "  # glm-5.3-flash：排除原廠 Z.AI 節點，走第三方節點（多模態低成本版）",
    ),
    (
        "  # z-ai 系列其餘模型固定路由至原廠 Z.AI（原生支援 Function Calling）",
        "  # z-ai/* 通配模型維持固定路由至原廠 Z.AI（原生支援 Function Calling）",
    ),
    (
        "  # deepseek V4.1 Flash（1017 版）：具名登錄，使管理 UI 模型下拉選單可選",
        "  # deepseek V4.1 Flash（1017 版）：具名登錄，且排除原廠 DeepSeek 節點",
    ),
]

# 每個目標：model_name、要移除的 provider 設定行、要插入的 provider 區塊
TARGETS = [
    {
        "model": "z-ai/glm-5.3",
        "drop_lines": ['          order: ["z-ai"]'],
        "new_provider": ['          ignore: ["z-ai"]'],
    },
    {
        "model": "z-ai/glm-5.3-flash",
        "drop_lines": [],
        "new_provider": ['          ignore: ["z-ai"]'],
    },
    {
        "model": "deepseek/deepseek-v4.1-flash-1017",
        "drop_lines": [],
        "new_provider": ['          ignore: ["deepseek"]'],
    },
]


def block_bounds(lines, model):
    """回傳 (起始行, 結束行[不含])；找不到回傳 (None, None)。"""
    start = None
    needle = '- model_name: "%s"' % model
    for idx, line in enumerate(lines):
        if line.strip() == needle:
            start = idx
            break
    if start is None:
        return None, None
    end = len(lines)
    for idx in range(start + 1, len(lines)):
        stripped = lines[idx]
        if stripped.startswith("  - model_name:") or stripped.startswith("general_settings:"):
            end = idx
            break
    return start, end


def patch(lines, target, dry_run):
    start, end = block_bounds(lines, target["model"])
    if start is None:
        print("SKIP（找不到模型區塊）:", target["model"])
        return lines, False

    block = lines[start:end]
    changed = False

    # 1) 移除舊的 order 行
    for drop in target["drop_lines"]:
        if drop in block:
            pos = start + block.index(drop)
            if dry_run:
                print("  - 移除: %s" % drop.strip())
            del lines[pos]
            changed = True
            block = lines[start:end]

    # 3) 已有 provider.ignore 就不重複插入
    if any("ignore:" in l for l in block):
        print("  已存在 ignore 設定，略過:", target["model"])
        return lines, changed

    # 4) 既有 provider: 區塊（保留 require_parameters 等設定）直接補 ignore
    provider_pos = None
    for idx in range(start, end):
        if lines[idx].strip() == "provider:":
            provider_pos = idx
            break
    if provider_pos is not None:
        for line in target["new_provider"]:
            if dry_run:
                print("  + 插入(provider 內): %s" % line.strip())
            lines.insert(provider_pos + 1, line)
            provider_pos += 1
        return lines, True

    # 5) 沒有 provider 區塊：接在 api_key 行之後插入完整 extra_body
    insert_at = None
    for idx in range(start, end):
        if lines[idx].strip().startswith("api_key:"):
            insert_at = idx + 1
    if insert_at is None:
        print("SKIP（找不到 api_key 行）:", target["model"])
        return lines, changed

    new_lines = ["      extra_body:", "        provider:"] + target["new_provider"]
    if dry_run:
        for line in new_lines:
            print("  + 插入: %s" % line.strip())
    for offset, line in enumerate(new_lines):
        lines.insert(insert_at + offset, line)
    return lines, True


def apply_comments(lines, dry_run):
    """全檔層級替換過時註解（註解行位於 model_name 之上，不在 model 區塊內）。"""
    changed = False
    for old, new in COMMENTS:
        if old not in lines:
            print("  ! 註解未命中（略過）: %s" % old.strip())
            continue
        pos = lines.index(old)
        if dry_run:
            print("  ~ 註解: %s" % new.strip())
        lines[pos] = new
        changed = True
    return lines, changed


def relocate_wildcard_comment(lines, dry_run):
    """把 z-ai/* 的說明註解移到通配模型區塊正上方（原檔誤放在 deepseek 區塊上方）。"""
    comment = "  # z-ai/* 通配模型維持固定路由至原廠 Z.AI（原生支援 Function Calling）"
    if comment not in lines:
        print("  ! 通配註解未命中（略過）")
        return lines, False
    idx = lines.index(comment)
    target = None
    for i, line in enumerate(lines):
        if line.strip() == '- model_name: "z-ai/*"':
            target = i
            break
    if target is None:
        print("  ! 找不到 z-ai/* 區塊（略過）")
        return lines, False
    if target == idx + 1:
        print("  = 通配註解位置已正確")
        return lines, False
    if dry_run:
        print("  > 移動註解至 z-ai/* 區塊上方")
    del lines[idx]
    if target > idx:
        target -= 1
    lines.insert(target, comment)
    return lines, True


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    with open(CONFIG, "r", encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    print("模式:", "DRY-RUN（不寫檔）" if dry_run else "寫入")
    print("\n=== 註解 ===")
    lines, comment_changed = apply_comments(lines, dry_run)
    lines, moved = relocate_wildcard_comment(lines, dry_run)

    changed_any = comment_changed or moved
    for target in TARGETS:
        print("\n=== %s ===" % target["model"])
        lines, changed = patch(lines, target, dry_run)
        changed_any = changed_any or changed

    if not changed_any:
        print("\n沒有任何變更。")
        return 0

    if dry_run:
        print("\n--- 變更後內容預覽（api_key 已遮罩）---")
        for line in lines:
            print(re.sub(r'(api_key:\s*")[^"]+', r"\1***MASKED***", line))
        return 0

    backup = "%s.bak.%s" % (CONFIG, time.strftime("%Y%m%d%H%M%S"))
    shutil.copy2(CONFIG, backup)
    with open(CONFIG, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n已備份:", backup)
    print("已寫入:", CONFIG)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
