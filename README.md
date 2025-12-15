# Knowledge ETL

Extract-Transform-Load pipeline that converts URLs, images, and documents to **pure text Markdown**.

## Core Concept

```
输入                     处理                      输出
┌─────────┐         ┌───────────┐          ┌─────────────┐
│ URL     │         │           │          │             │
│ 图片    │ ──────▶ │ extractor │ ──────▶  │ 纯文本       │
│ PDF     │         │  (Agent)  │          │ Markdown    │
└─────────┘         └───────────┘          └─────────────┘
                          │
                          ▼
                ┌─────────────────┐
                │ 图片 → 文字描述  │
                │ (不保存文件)     │
                └─────────────────┘
```

**关键特性：所有内容（包括图片）都转换为纯文本，不生成文件。**

## 为什么需要这个？

| 问题 | 解决方案 |
|------|----------|
| 读取大图片时 "prompt too large" | Agent 在独立上下文处理，主对话不超限 |
| 网页图文混合难以提取 | 统一转换为纯文本 Markdown |
| 多图片处理容易超限 | 逐张处理，结果汇总为文本 |

## 安装

```bash
claude plugin install --git https://github.com/arctrany/ai-knowledge-etl.git
```

### 前置条件

配置 Playwright MCP：

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--caps=vision,pdf"]
    }
  }
}
```

## 使用

### 命令

```bash
# 提取网页（文本+图片描述）
/knowledge-etl:extract https://example.com/article

# 分析大图片
/knowledge-etl:extract ./screenshot-4k.png

# 批量图片处理
/knowledge-etl:extract "./docs/*.png"

# PDF 提取
/knowledge-etl:extract ./document.pdf
```

### 命令参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `source` | **必填** - URL/图片/PDF/目录 | `https://docs.example.com` |
| `--engine` | 提取引擎: auto, playwright, jina, trafilatura | `--engine=jina` |
| `--with-images` | 提取并分析图片 (默认关闭) | `--with-images` |
| `--with-depth` | 启用爬取并指定深度(1-3) | `--with-depth=2` |
| `--topic` | 主题正则表达式过滤 | `--topic="API\|接口"` |
| `--max-pages` | 最大爬取页数 (默认20，最大50) | `--max-pages=30` |
| `--pipe` | 输出格式: skill, plugin, prompt, rag, docs, json | `--pipe=skill` |
| `--output-dir` | 输出目录 (默认 .knowledge-etl) | `--output-dir=./docs` |
| `--compact-cph` | 压缩进度输出 | `--compact-cph` |

### 使用示例

```bash
# 单页提取（公开文档，使用 jina 快速提取）
/knowledge-etl:extract https://docs.python.org/3/library/json.html --engine=jina

# 单页提取（内部文档，自动使用 playwright）
/knowledge-etl:extract https://alidocs.dingtalk.com/xxx

# 带图片的页面提取
/knowledge-etl:extract https://docs.example.com/architecture --with-images

# 深度爬取并转换为 Skill
/knowledge-etl:extract https://api.example.com/docs --with-depth=2 --topic="API|接口" --pipe=skill

# 深度爬取生成 RAG 知识库
/knowledge-etl:extract https://docs.example.com --with-depth=3 --max-pages=50 --pipe=rag

# 本地图片分析
/knowledge-etl:extract ./screenshot.png

# 批量图片处理
/knowledge-etl:extract "./docs/*.png"

# PDF 提取
/knowledge-etl:extract ./document.pdf
```

### 输出格式 (--pipe)

| 格式 | 说明 | 输出位置 |
|------|------|----------|
| (不指定) | 纯 Markdown 文本 | `.knowledge-etl/extracted.md` |
| `skill` | Claude Code Skill | `output/skill/SKILL.md` |
| `plugin` | Claude Code Plugin 结构 | `output/plugin/` |
| `prompt` | LLM 系统提示词 | `output/prompt/system-prompt.md` |
| `rag` | RAG 友好的分块 JSON | `output/rag/chunks/*.json` |
| `docs` | 文档结构 | `output/docs/` |
| `json` | 结构化 JSON 知识库 | `output/json/knowledge.json` |

### 引擎选择

| 引擎 | 速度 | 登录 | 图片 | 隐私 | 适用场景 |
|------|------|------|------|------|----------|
| **playwright** | 慢 | ✅ | ✅ | ✅ 本地 | 内部系统、需登录 |
| **jina** | 快 | ❌ | ⚠️ | ❌ 第三方 | 公开文档 |
| **trafilatura** | 中 | ❌ | ❌ | ✅ 本地 | 公开文章 |

> **安全说明**: 内部域名 (如 `alidocs.dingtalk.com`) 会强制使用本地引擎，不会发送到外部 API。详见 `config/security.yaml`。

### 输出示例

```markdown
---
source: https://example.com/docs
title: 系统架构文档
extracted_at: 2025-12-12T21:30:00+08:00
---

# 系统架构文档

## 概述

本文档介绍系统的整体架构设计...

---
**[图片: 整体架构]** 图片展示了系统的三层架构：
1. 表现层：Web 前端和移动 App
2. 业务层：API Gateway + 微服务集群
3. 数据层：MySQL + Redis + ElasticSearch
各层之间通过 REST API 和消息队列通信。
---

## 详细设计

...后续文本内容...
```

## 防止 "Prompt Too Long" 机制

### 分层防护架构

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🛡️ 四层防护：确保任意规模内容都不会导致上下文溢出                         ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  Layer 1: 配置层 (config/limits.yaml)                                    ║
║  ├── transform.max_input_chars: 30000 (直接读取上限)                     ║
║  ├── transform.use_index_only_threshold: 10 (>10页只读索引)              ║
║  └── transform.summary_per_page_chars: 500 (每页摘要限制)                ║
║                                                                           ║
║  Layer 2: 提取层 (extractor)                                             ║
║  ├── 每页同时生成 .summary 文件 (500字符)                                ║
║  └── 输出: pages/001.md + pages/001.summary                              ║
║                                                                           ║
║  Layer 3: 汇总层 (crawler-summarizer)                                    ║
║  ├── 优先读取 .summary 文件                                              ║
║  ├── 无摘要时只读 frontmatter (前20行)                                   ║
║  └── 只对 top 3 高相关页读取完整内容                                     ║
║                                                                           ║
║  Layer 4: 转换层 (output-transformer)                                    ║
║  ├── 强制预检：统计页数和内容大小                                        ║
║  └── 三级策略：                                                          ║
║      • 页数 ≤5 且 <30K → direct (直接读取)                               ║
║      • 页数 6-10 或 >30K → summarize_first (先摘要)                      ║
║      • 页数 >10 → index_only (只读索引)                                  ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

### Transform 策略路由

| 条件 | 策略 | 上下文影响 |
|------|------|-----------|
| 页数 ≤5 且 内容 <30K | `direct` - 直接读取 REPORT.md | ~30K chars |
| 页数 6-10 或 内容 >30K | `summarize_first` - 先生成摘要再转换 | ~15K chars |
| 页数 >10 | `index_only` - 只读 INDEX.md | ~5K chars |

## 工作原理

### 独立上下文解决 "prompt too large"

```
主对话                           Extractor Agent
  │                                    │
  │ "提取这个网页"                      │
  │ ─────────────────────────────────▶ │
  │                                    │ ┌─────────────────┐
  │                                    │ │ 导航到 URL       │
  │                                    │ │ 提取文本        │
  │                                    │ │ 读取图片(压缩后) │
  │                                    │ │ 转换为文字描述   │
  │                                    │ └─────────────────┘
  │                                    │
  │ "纯文本 Markdown 结果"             │
  │ ◀───────────────────────────────── │
  │                                    │
主对话永远不会接收图片数据！
```

### URL 提取流程

```
1. 导航到 URL
2. Snapshot 提取文本
3. 检测：需要登录？反爬？
   ├─ 需要登录 → 提示用户
   ├─ 反爬保护 → 截图 fallback
   └─ 正常内容 → 继续
4. 提取所有文本
5. 对每张图片：
   ├─ 压缩（如需要）
   ├─ 读取分析
   └─ 转换为文字描述
6. 组合：文本 + 图片描述
7. 返回纯 Markdown
```

### 图片 → 文字描述

图片不会被保存，而是转换为详细的文字描述：

```markdown
---
**[图片: 流程图]** 图片展示了用户注册流程：
1. 用户填写邮箱和密码
2. 系统发送验证邮件
3. 用户点击验证链接
4. 注册完成，跳转到首页
箭头显示：每一步之间有"成功/失败"两个分支
---
```

## 组件结构

```
knowledge-etl/
├── agents/
│   ├── extractor.md           # 内容提取 (本地文件)
│   ├── crawler-summarizer.md  # 爬取汇总
│   └── output-transformer.md  # 格式转换
├── commands/
│   └── extract.md             # 入口命令 (MCP 可用)
├── skills/
│   └── extract/SKILL.md       # 自动触发技能
├── config/
│   └── limits.yaml            # 集中配置
└── scripts/
    └── compress-image.*       # 图片压缩
```

## Agent 职责边界

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    MCP 工具传播规则                                        ║
╠═══════════════════════════════════════════════════════════════════════════╣
║  MCP 工具 (Playwright) 只在主上下文 (命令) 可用                            ║
║  Subagent 无法访问 MCP → 只能处理本地文件                                  ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

| 组件 | 上下文 | MCP | 职责 |
|------|--------|-----|------|
| `extract.md` | 主 | ✅ | URL 捕获，爬虫循环控制 |
| `extractor` | 隔离 | ❌ | 处理本地快照/图片/PDF |
| `crawler-summarizer` | 隔离 | ❌ | 生成 INDEX.md/REPORT.md |
| `output-transformer` | 隔离 | ❌ | 转换为 skill/prompt/rag |

**数据流**：
```
主上下文              隔离上下文
    │                     │
    │ Playwright 捕获 URL  │
    ├──────────────────▶  │
    │ 本地快照文件         │ extractor 处理
    │ ◀──────────────────┤ 输出 pages/*.md
    │                     │
```

## 错误处理

| 问题 | 处理方式 |
|------|----------|
| 需要登录 | 提示用户登录后重试 |
| 反爬保护 | 自动切换到截图模式 |
| 图片过大 | 压缩后再分析 |
| prompt too large | 分段处理 |

## 版本历史

- **2.1.0**: 简化架构，图片转文字描述，不保存文件
- **2.0.0**: 升级为 Knowledge ETL，统一提取入口
- **1.0.0**: 初始 web-knowledge-extractor

## License

MIT
