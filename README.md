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
