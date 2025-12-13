# Knowledge ETL 系统设计文档

> 版本：2.2.0
> 日期：2025-12-13
> 状态：已实现

## 重要架构决策

### MCP 工具隔离性

**发现**: MCP 工具（如 Playwright）不会自动传播到子代理（subagent）。

**影响**:
- 子代理（extractor agent）无法直接使用 `mcp__playwright__*` 工具
- 即使在 agent 配置中声明了这些工具，子代理也无法访问

**解决方案**:
1. **主上下文处理 URL 提取**: 使用 Playwright 获取页面内容并保存到临时文件
2. **子代理处理本地文件**: 读取保存的文件（快照、截图）进行内容处理
3. **分工明确**: 主上下文 = 网络交互，子代理 = 内容处理（隔离上下文防溢出）

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         工具可用性架构                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   主上下文 (Main Context)                                                │
│   ├── 标准工具: Read, Write, Bash, Glob, Grep...                        │
│   ├── MCP 工具: mcp__playwright__*, mcp__deepwiki__*...                │
│   └── 可调用子代理                                                       │
│                                                                          │
│   子代理 (Subagent via Task)                                             │
│   ├── 标准工具: Read, Write, Bash, Glob, Grep...                        │
│   └── ❌ MCP 工具不可用                                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 1. 系统概述

### 1.1 定位

Knowledge ETL 是一个**内容提取与理解**的原子能力层，为 Claude 提供从互联网、文件系统、文档中系统化获取和理解内容的能力。

### 1.2 核心约束

```
┌─────────────────────────────────────────────────────────────────┐
│                     绝对红线                                     │
│                                                                  │
│   ❌ 禁止触发 "Prompt Too Long" 错误                            │
│   ❌ 禁止阻塞用户（遇障碍必须交互）                              │
│   ❌ 禁止丢失关键信息（无声失败）                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 核心能力

| 能力 | 描述 |
|------|------|
| **安全提取** | 任意大小的输入都能安全处理，绝不超限 |
| **障碍应对** | 登录、反爬、权限问题通过用户交互解决 |
| **结构理解** | 保留文档结构，图片转文字描述 |
| **格式输出** | 输出格式化 Markdown 或结构化 JSON |
| **组件生成** | 可选调用 plugin-dev 生成 Skill/Plugin |

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Knowledge ETL Pipeline                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   用户输入                                                               │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  /knowledge-etl:extract <source> [options]                      │   │
│   │                                                                  │   │
│   │  source: URL | 文件路径 | Glob 模式 | 目录路径                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    Layer 1: 输入解析层                           │   │
│   │                    (Input Parser)                                │   │
│   │                                                                  │   │
│   │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │   │
│   │   │   URL    │  │  文件    │  │  Glob    │  │  目录    │       │   │
│   │   │ Detector │  │ Detector │  │ Expander │  │ Scanner  │       │   │
│   │   └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │   │
│   │        └──────────────┴──────────────┴──────────────┘           │   │
│   │                              │                                   │   │
│   │                              ▼                                   │   │
│   │                    ┌──────────────────┐                         │   │
│   │                    │   任务队列生成    │                         │   │
│   │                    │   TaskQueue[]    │                         │   │
│   │                    └──────────────────┘                         │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    Layer 2: 安全控制层                           │   │
│   │                    (Safety Controller)                           │   │
│   │                                                                  │   │
│   │   ┌──────────────────────────────────────────────────────────┐  │   │
│   │   │                    预检模块                               │  │   │
│   │   │                                                          │  │   │
│   │   │  文件大小检查 ──→ 超限? ──→ 压缩/分块策略               │  │   │
│   │   │  累计大小检查 ──→ 超限? ──→ 分批处理策略               │  │   │
│   │   │  文件数量检查 ──→ 过多? ──→ 摘要模式策略               │  │   │
│   │   └──────────────────────────────────────────────────────────┘  │   │
│   │                              │                                   │   │
│   │                              ▼                                   │   │
│   │   ┌──────────────────────────────────────────────────────────┐  │   │
│   │   │                    处理策略分配                           │  │   │
│   │   │                                                          │  │   │
│   │   │  Task + Strategy = ExecutionPlan                        │  │   │
│   │   │                                                          │  │   │
│   │   │  策略类型：                                              │  │   │
│   │   │    - DIRECT: 直接处理（小文件）                          │  │   │
│   │   │    - COMPRESS: 压缩后处理（大图片）                      │  │   │
│   │   │    - CHUNK: 分块处理（长文档/长页面）                    │  │   │
│   │   │    - SUMMARY: 摘要模式（超大内容）                       │  │   │
│   │   │    - SCREENSHOT: 截图模式（动态页面）                    │  │   │
│   │   └──────────────────────────────────────────────────────────┘  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    Layer 3: 提取执行层                           │   │
│   │                    (Extraction Engine)                           │   │
│   │                                                                  │   │
│   │   ┌──────────────────────────────────────────────────────────┐  │   │
│   │   │                    障碍检测与处理                         │  │   │
│   │   │                                                          │  │   │
│   │   │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │  │   │
│   │   │  │ 登录    │  │ 反爬    │  │ 权限    │  │ 超时    │    │  │   │
│   │   │  │ 拦截    │  │ 检测    │  │ 不足    │  │ 失败    │    │  │   │
│   │   │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘    │  │   │
│   │   │       └──────────────┴──────────────┴──────────────┘     │  │   │
│   │   │                          │                               │  │   │
│   │   │                          ▼                               │  │   │
│   │   │              ┌─────────────────────┐                    │  │   │
│   │   │              │    用户交互请求     │                    │  │   │
│   │   │              │  AskUserQuestion   │                    │  │   │
│   │   │              └─────────────────────┘                    │  │   │
│   │   └──────────────────────────────────────────────────────────┘  │   │
│   │                              │                                   │   │
│   │                              ▼                                   │   │
│   │   ┌──────────────────────────────────────────────────────────┐  │   │
│   │   │                    内容提取器                             │  │   │
│   │   │                                                          │  │   │
│   │   │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │  │   │
│   │   │  │   Web   │  │  Image  │  │   PDF   │  │  Text   │    │  │   │
│   │   │  │Extractor│  │Extractor│  │Extractor│  │Extractor│    │  │   │
│   │   │  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │  │   │
│   │   │                                                          │  │   │
│   │   │  每个提取器在独立 Agent 上下文中运行                     │  │   │
│   │   │  提取完成后立即释放上下文                                 │  │   │
│   │   └──────────────────────────────────────────────────────────┘  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    Layer 4: 理解与转换层                         │   │
│   │                    (Understanding Engine)                        │   │
│   │                                                                  │   │
│   │   ┌──────────────────────────────────────────────────────────┐  │   │
│   │   │                    结构化理解                             │  │   │
│   │   │                                                          │  │   │
│   │   │  原始内容 ──→ 结构解析 ──→ 中间表示 (IR)                │  │   │
│   │   │                                                          │  │   │
│   │   │  IR = {                                                  │  │   │
│   │   │    meta: { source, title, type, extractedAt },          │  │   │
│   │   │    structure: [ sections... ],                          │  │   │
│   │   │    content: [ paragraphs, lists, tables... ],           │  │   │
│   │   │    assets: [ { type, description, extractedText }... ]  │  │   │
│   │   │  }                                                       │  │   │
│   │   └──────────────────────────────────────────────────────────┘  │   │
│   │                              │                                   │   │
│   │                              ▼                                   │   │
│   │   ┌──────────────────────────────────────────────────────────┐  │   │
│   │   │                    图片理解                               │  │   │
│   │   │                                                          │  │   │
│   │   │  图片类型识别 ──→ 专用描述策略                           │  │   │
│   │   │                                                          │  │   │
│   │   │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │  │   │
│   │   │  │ 流程图  │  │ 架构图  │  │ 截图    │  │ 图表    │    │  │   │
│   │   │  │         │  │         │  │         │  │         │    │  │   │
│   │   │  │节点+流向│  │层级+组件│  │布局+文字│  │数据+趋势│    │  │   │
│   │   │  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │  │   │
│   │   └──────────────────────────────────────────────────────────┘  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    Layer 5: 输出生成层                           │   │
│   │                    (Output Generator)                            │   │
│   │                                                                  │   │
│   │   IR ──→ 输出格式选择                                           │   │
│   │              │                                                   │   │
│   │              ├──→ Markdown ──→ 格式化文档                       │   │
│   │              │                                                   │   │
│   │              ├──→ JSON ──→ 结构化数据                           │   │
│   │              │                                                   │   │
│   │              └──→ Skill/Plugin ──→ 调用 plugin-dev              │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 数据流图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              数据流                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   输入                处理                  存储              输出       │
│                                                                          │
│   URL ─────┐                                                            │
│            │      ┌─────────────┐      ┌─────────────┐                 │
│   文件 ────┼─────→│  任务队列   │─────→│  临时存储   │                 │
│            │      │  TaskQueue  │      │  /tmp/etl/  │                 │
│   目录 ────┘      └──────┬──────┘      └──────┬──────┘                 │
│                          │                    │                         │
│                          ▼                    │                         │
│                   ┌─────────────┐             │                         │
│                   │  执行计划   │             │                         │
│                   │  ExecPlan   │             │                         │
│                   └──────┬──────┘             │                         │
│                          │                    │                         │
│                          ▼                    │                         │
│            ┌─────────────────────────┐        │                         │
│            │     批次处理循环        │        │                         │
│            │                         │        │                         │
│            │  for batch in batches:  │        │                         │
│            │    ┌─────────────────┐  │        │                         │
│            │    │ Agent Context   │  │        │     ┌─────────────┐    │
│            │    │  (隔离)         │──┼────────┼────→│   摘要文件   │    │
│            │    │                 │  │        │     │  .summary   │    │
│            │    │ 提取 → 理解     │  │        │     └─────────────┘    │
│            │    │      → 摘要     │  │        │                         │
│            │    └─────────────────┘  │        │                         │
│            │           ↓             │        │                         │
│            │    释放上下文 ──────────┘        │                         │
│            │                         │        │                         │
│            └─────────────────────────┘        │                         │
│                          │                    │                         │
│                          ▼                    │                         │
│                   ┌─────────────┐             │                         │
│                   │  汇总阶段   │◀────────────┘                         │
│                   │             │                                       │
│                   │ 读取所有摘要│      ┌─────────────────────────────┐ │
│                   │ 生成最终IR │─────→│        最终输出              │ │
│                   └─────────────┘      │                             │ │
│                                        │  - formatted.md (Markdown)  │ │
│                                        │  - structured.json (JSON)   │ │
│                                        │  - skill.md (Skill)         │ │
│                                        │  - plugin/ (Plugin)         │ │
│                                        └─────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心模块设计

### 3.1 输入解析层 (Input Parser)

#### 3.1.1 职责

- 识别输入类型（URL/文件/Glob/目录）
- 展开 Glob 和目录为文件列表
- 生成标准化的任务队列

#### 3.1.2 输入类型检测

```typescript
interface InputSource {
  raw: string;              // 原始输入
  type: 'url' | 'file' | 'glob' | 'directory';
  resolved: string[];       // 解析后的具体路径/URL 列表
}

function detectInputType(input: string): InputSource {
  if (input.startsWith('http://') || input.startsWith('https://')) {
    return { raw: input, type: 'url', resolved: [input] };
  }

  if (input.includes('*') || input.includes('?')) {
    return { raw: input, type: 'glob', resolved: globExpand(input) };
  }

  if (isDirectory(input)) {
    return { raw: input, type: 'directory', resolved: scanDirectory(input) };
  }

  return { raw: input, type: 'file', resolved: [input] };
}
```

#### 3.1.3 目录扫描规则

```yaml
# 默认排除规则
exclude:
  directories:
    - node_modules
    - .git
    - .svn
    - __pycache__
    - .cache
    - dist
    - build

  files:
    - "*.lock"
    - "*.log"
    - ".DS_Store"
    - "Thumbs.db"

  patterns:
    - ".*"        # 隐藏文件（可选）

# 支持的文件类型
include:
  documents:
    - "*.md"
    - "*.txt"
    - "*.pdf"
    - "*.doc"
    - "*.docx"

  images:
    - "*.png"
    - "*.jpg"
    - "*.jpeg"
    - "*.gif"
    - "*.webp"
    - "*.svg"

  data:
    - "*.json"
    - "*.yaml"
    - "*.yml"
    - "*.xml"

  code:  # 可选，用于代码文档
    - "*.ts"
    - "*.js"
    - "*.py"
```

#### 3.1.4 任务队列结构

```typescript
interface Task {
  id: string;               // 唯一标识
  source: string;           // 来源路径或 URL
  type: 'url' | 'image' | 'pdf' | 'markdown' | 'text' | 'json';
  size?: number;            // 文件大小（字节）
  priority: number;         // 处理优先级（小文件优先）
  dependencies?: string[];  // 依赖的其他任务（如 md 引用的图片）
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'skipped';
}

interface TaskQueue {
  tasks: Task[];
  totalSize: number;
  estimatedBatches: number;
}
```

---

### 3.2 安全控制层 (Safety Controller)

#### 3.2.1 职责

- 预检所有任务，评估风险
- 分配处理策略
- 控制批次大小
- 确保绝不超限

#### 3.2.2 安全阈值

```typescript
const SAFETY_LIMITS = {
  // === 单文件限制 ===
  image: {
    maxSize: 300 * 1024,        // 300KB（压缩后）
    maxWidth: 800,               // 800px
    maxHeight: 4000,             // 4000px（长图限制）
  },

  pdf: {
    maxPages: 20,                // 最多处理 20 页
    maxSizePerPage: 100 * 1024,  // 每页摘要限 100KB
  },

  text: {
    maxChars: 50000,             // 单文本最大 5 万字符
    chunkSize: 10000,            // 分块大小 1 万字符
  },

  url: {
    maxSnapshotChars: 40000,     // 快照最大 4 万字符
    maxScreenshotSegments: 5,    // 最多 5 个滚动截图
  },

  // === 批次限制 ===
  batch: {
    maxFiles: 5,                 // 单批次最多 5 个文件
    maxTotalSize: 1 * 1024 * 1024, // 单批次最大 1MB
    maxImages: 3,                // 单批次最多 3 张图
  },

  // === 输出限制 ===
  output: {
    summaryMaxChars: 500,        // 单文件摘要上限
    totalMaxChars: 100000,       // 最终输出上限 10 万字符
  },

  // === 会话限制 ===
  session: {
    maxTasks: 100,               // 单次最多处理 100 个任务
    maxTotalSize: 50 * 1024 * 1024, // 单次最大原始大小 50MB
  },
};
```

#### 3.2.3 处理策略

```typescript
type ProcessingStrategy =
  | 'DIRECT'      // 直接处理（小文件，无需预处理）
  | 'COMPRESS'    // 压缩处理（大图片）
  | 'CHUNK'       // 分块处理（长文本/长页面）
  | 'SUMMARY'     // 仅摘要（超大内容）
  | 'SCREENSHOT'  // 截图模式（动态页面/反爬）
  | 'SKIP'        // 跳过（不支持的类型）
  | 'REJECT';     // 拒绝（超出能力范围）

interface ExecutionPlan {
  task: Task;
  strategy: ProcessingStrategy;
  params: {
    compressTo?: number;       // 压缩目标大小
    chunkCount?: number;       // 分块数量
    summaryOnly?: boolean;     // 仅生成摘要
    screenshotSegments?: number; // 截图段数
  };
  estimatedOutputSize: number; // 预估输出大小
}

function assignStrategy(task: Task): ExecutionPlan {
  const { type, size } = task;

  // 图片策略
  if (type === 'image') {
    if (size <= SAFETY_LIMITS.image.maxSize) {
      return { task, strategy: 'DIRECT', params: {}, estimatedOutputSize: 500 };
    }
    return {
      task,
      strategy: 'COMPRESS',
      params: { compressTo: SAFETY_LIMITS.image.maxSize },
      estimatedOutputSize: 500,
    };
  }

  // PDF 策略
  if (type === 'pdf') {
    const pages = estimatePdfPages(task.source);
    if (pages > SAFETY_LIMITS.pdf.maxPages) {
      return {
        task,
        strategy: 'SUMMARY',
        params: { summaryOnly: true },
        estimatedOutputSize: 1000,
      };
    }
    return { task, strategy: 'DIRECT', params: {}, estimatedOutputSize: pages * 500 };
  }

  // 文本策略
  if (type === 'markdown' || type === 'text') {
    if (size > SAFETY_LIMITS.text.maxChars) {
      const chunks = Math.ceil(size / SAFETY_LIMITS.text.chunkSize);
      return {
        task,
        strategy: 'CHUNK',
        params: { chunkCount: chunks },
        estimatedOutputSize: Math.min(size, SAFETY_LIMITS.output.totalMaxChars),
      };
    }
    return { task, strategy: 'DIRECT', params: {}, estimatedOutputSize: size };
  }

  // URL 策略
  if (type === 'url') {
    return {
      task,
      strategy: 'DIRECT',  // 先尝试直接提取，失败后降级
      params: {},
      estimatedOutputSize: 5000,
    };
  }

  return { task, strategy: 'SKIP', params: {}, estimatedOutputSize: 0 };
}
```

#### 3.2.4 批次规划

```typescript
interface Batch {
  id: number;
  plans: ExecutionPlan[];
  totalEstimatedSize: number;
}

function planBatches(plans: ExecutionPlan[]): Batch[] {
  const batches: Batch[] = [];
  let currentBatch: Batch = { id: 0, plans: [], totalEstimatedSize: 0 };

  // 按优先级排序（小文件优先）
  const sorted = plans.sort((a, b) => a.estimatedOutputSize - b.estimatedOutputSize);

  for (const plan of sorted) {
    const wouldExceed =
      currentBatch.plans.length >= SAFETY_LIMITS.batch.maxFiles ||
      currentBatch.totalEstimatedSize + plan.estimatedOutputSize > SAFETY_LIMITS.batch.maxTotalSize ||
      countImages(currentBatch) >= SAFETY_LIMITS.batch.maxImages && plan.task.type === 'image';

    if (wouldExceed && currentBatch.plans.length > 0) {
      batches.push(currentBatch);
      currentBatch = { id: batches.length, plans: [], totalEstimatedSize: 0 };
    }

    currentBatch.plans.push(plan);
    currentBatch.totalEstimatedSize += plan.estimatedOutputSize;
  }

  if (currentBatch.plans.length > 0) {
    batches.push(currentBatch);
  }

  return batches;
}
```

---

### 3.3 提取执行层 (Extraction Engine)

#### 3.3.1 职责

- 检测并处理提取障碍
- 执行具体的提取操作
- 在隔离的 Agent 上下文中运行
- 返回标准化的提取结果

#### 3.3.2 障碍检测与处理

```typescript
type Obstacle =
  | 'LOGIN_REQUIRED'    // 需要登录
  | 'CAPTCHA'           // 验证码
  | 'ANTI_SCRAPE'       // 反爬检测
  | 'PERMISSION_DENIED' // 权限不足
  | 'NOT_FOUND'         // 资源不存在
  | 'TIMEOUT'           // 超时
  | 'NETWORK_ERROR'     // 网络错误
  | 'UNSUPPORTED_FORMAT'; // 不支持的格式

interface ObstacleDetection {
  detected: boolean;
  type?: Obstacle;
  message?: string;
  recoverable: boolean;
  suggestedAction?: 'login' | 'screenshot' | 'retry' | 'skip' | 'abort';
}

// 障碍检测规则
const OBSTACLE_PATTERNS = {
  LOGIN_REQUIRED: [
    /登录|login|sign.?in|unauthorized|请先登录/i,
    /401|403/,
  ],
  CAPTCHA: [
    /验证码|captcha|verify|人机验证/i,
  ],
  ANTI_SCRAPE: [
    /cloudflare|checking.+browser|请稍候/i,
    /access.+denied|blocked/i,
  ],
};

function detectObstacle(content: string, statusCode?: number): ObstacleDetection {
  // 检查空内容
  if (!content || content.trim().length < 100) {
    return {
      detected: true,
      type: 'ANTI_SCRAPE',
      message: '页面内容为空或过少，可能被反爬拦截',
      recoverable: true,
      suggestedAction: 'screenshot',
    };
  }

  // 检查登录
  for (const pattern of OBSTACLE_PATTERNS.LOGIN_REQUIRED) {
    if (pattern.test(content)) {
      return {
        detected: true,
        type: 'LOGIN_REQUIRED',
        message: '页面需要登录',
        recoverable: true,
        suggestedAction: 'login',
      };
    }
  }

  // 检查验证码
  for (const pattern of OBSTACLE_PATTERNS.CAPTCHA) {
    if (pattern.test(content)) {
      return {
        detected: true,
        type: 'CAPTCHA',
        message: '需要完成验证码',
        recoverable: true,
        suggestedAction: 'login',
      };
    }
  }

  return { detected: false, recoverable: true };
}
```

#### 3.3.3 用户交互处理

```typescript
interface UserInteraction {
  type: 'question' | 'wait' | 'confirm';
  title: string;
  message: string;
  options?: Array<{
    label: string;
    value: string;
    description?: string;
  }>;
  timeout?: number;  // 等待超时（秒）
}

// 预定义的交互场景
const INTERACTIONS = {
  loginRequired: (url: string): UserInteraction => ({
    type: 'wait',
    title: '需要登录',
    message: `页面 ${url} 需要登录，请在浏览器中完成登录后继续`,
    options: [
      { label: '已完成登录', value: 'continue', description: '继续提取' },
      { label: '跳过此页', value: 'skip', description: '跳过这个页面' },
      { label: '取消提取', value: 'abort', description: '取消整个提取任务' },
    ],
    timeout: 300,  // 5 分钟超时
  }),

  useScreenshot: (url: string): UserInteraction => ({
    type: 'confirm',
    title: '切换到截图模式',
    message: `页面 ${url} 无法直接提取，是否使用截图模式？`,
    options: [
      { label: '使用截图', value: 'screenshot', description: '滚动截图并分析' },
      { label: '跳过此页', value: 'skip', description: '跳过这个页面' },
    ],
  }),

  largeContent: (details: string): UserInteraction => ({
    type: 'confirm',
    title: '内容较大',
    message: details,
    options: [
      { label: '继续处理', value: 'continue', description: '可能需要较长时间' },
      { label: '仅提取摘要', value: 'summary', description: '只生成内容摘要' },
      { label: '取消', value: 'abort', description: '取消此任务' },
    ],
  }),

  manyFiles: (count: number, batches: number): UserInteraction => ({
    type: 'confirm',
    title: '文件数量较多',
    message: `发现 ${count} 个文件，将分 ${batches} 批处理，是否继续？`,
    options: [
      { label: '全部处理', value: 'all', description: `处理全部 ${count} 个文件` },
      { label: '只处理前 20 个', value: 'partial', description: '只处理前 20 个文件' },
      { label: '取消', value: 'abort', description: '取消此任务' },
    ],
  }),
};
```

#### 3.3.4 提取器实现

```typescript
// 提取结果接口
interface ExtractionResult {
  success: boolean;
  source: string;
  type: 'url' | 'image' | 'pdf' | 'text';
  content?: {
    title?: string;
    text: string;           // 提取的文本
    structure?: string[];   // 文档结构（标题列表）
    images?: ImageDescription[];
    tables?: TableData[];
  };
  error?: {
    type: Obstacle | 'UNKNOWN';
    message: string;
  };
  stats: {
    originalSize: number;
    extractedChars: number;
    imagesProcessed: number;
    processingTimeMs: number;
  };
}

interface ImageDescription {
  index: number;
  label: string;
  category: 'flowchart' | 'architecture' | 'screenshot' | 'chart' | 'photo' | 'other';
  description: string;      // 视觉描述
  extractedText?: string;   // 图中文字
}

// Web 提取器
async function extractWeb(url: string, strategy: ProcessingStrategy): Promise<ExtractionResult> {
  const startTime = Date.now();

  // 1. 导航到页面
  await playwright.navigate(url);
  await playwright.waitFor({ time: 3 });

  // 2. 尝试快照提取
  const snapshot = await playwright.snapshot();

  // 3. 检查障碍
  const obstacle = detectObstacle(snapshot);
  if (obstacle.detected) {
    if (obstacle.suggestedAction === 'login') {
      // 请求用户登录
      const response = await askUser(INTERACTIONS.loginRequired(url));
      if (response === 'skip') return { success: false, /* ... */ };
      if (response === 'abort') throw new Error('User aborted');
      // 用户登录后重试
      return extractWeb(url, strategy);
    }

    if (obstacle.suggestedAction === 'screenshot') {
      // 切换到截图模式
      return extractWebViaScreenshot(url);
    }
  }

  // 4. 检查内容大小
  if (snapshot.length > SAFETY_LIMITS.url.maxSnapshotChars) {
    // 截断并标记
    const truncated = snapshot.substring(0, SAFETY_LIMITS.url.maxSnapshotChars);
    return {
      success: true,
      source: url,
      type: 'url',
      content: {
        text: truncated + '\n\n[内容已截断]',
        // ...
      },
      stats: { /* ... */ },
    };
  }

  // 5. 提取图片描述（限制数量）
  const images = await extractPageImages(url, SAFETY_LIMITS.batch.maxImages);

  // 6. 返回结果
  return {
    success: true,
    source: url,
    type: 'url',
    content: {
      title: extractTitle(snapshot),
      text: snapshot,
      structure: extractHeadings(snapshot),
      images,
    },
    stats: {
      originalSize: snapshot.length,
      extractedChars: snapshot.length,
      imagesProcessed: images.length,
      processingTimeMs: Date.now() - startTime,
    },
  };
}

// 图片提取器
async function extractImage(path: string, strategy: ProcessingStrategy): Promise<ExtractionResult> {
  const startTime = Date.now();
  const originalSize = await getFileSize(path);

  let imagePath = path;

  // 1. 压缩处理（如需要）
  if (strategy === 'COMPRESS' || originalSize > SAFETY_LIMITS.image.maxSize) {
    imagePath = await compressImage(path, {
      maxWidth: SAFETY_LIMITS.image.maxWidth,
      maxSize: SAFETY_LIMITS.image.maxSize,
    });
  }

  // 2. 验证压缩后大小
  const compressedSize = await getFileSize(imagePath);
  if (compressedSize > SAFETY_LIMITS.image.maxSize) {
    // 二次压缩，降低分辨率
    imagePath = await compressImage(path, {
      maxWidth: 640,
      maxSize: 200 * 1024,
    });
  }

  // 3. 读取并分析图片
  const imageContent = await readFile(imagePath);
  const description = await describeImage(imageContent);

  return {
    success: true,
    source: path,
    type: 'image',
    content: {
      text: formatImageDescription(description),
      images: [description],
    },
    stats: {
      originalSize,
      extractedChars: description.description.length,
      imagesProcessed: 1,
      processingTimeMs: Date.now() - startTime,
    },
  };
}
```

---

### 3.4 理解与转换层 (Understanding Engine)

#### 3.4.1 职责

- 将提取结果转换为中间表示 (IR)
- 识别图片类型并应用专用描述策略
- 生成结构化摘要

#### 3.4.2 中间表示 (IR) 结构

```typescript
interface IntermediateRepresentation {
  // 元信息
  meta: {
    source: string;           // 原始来源
    sourceType: 'url' | 'file' | 'directory';
    title: string;
    extractedAt: string;      // ISO 时间戳
    totalFiles?: number;      // 目录模式下的文件数
  };

  // 统计信息
  stats: {
    totalChars: number;
    totalImages: number;
    processingTimeMs: number;
    filesProcessed: number;
    filesSkipped: number;
    errors: number;
  };

  // 文档结构（目录）
  structure: Array<{
    level: number;            // 层级 1-6
    title: string;
    anchor?: string;          // 锚点 ID
  }>;

  // 内容块
  content: ContentBlock[];

  // 资源描述
  assets: AssetDescription[];
}

type ContentBlock =
  | { type: 'heading'; level: number; text: string }
  | { type: 'paragraph'; text: string }
  | { type: 'list'; ordered: boolean; items: string[] }
  | { type: 'table'; headers: string[]; rows: string[][] }
  | { type: 'code'; language?: string; code: string }
  | { type: 'image_ref'; assetIndex: number }
  | { type: 'file_summary'; path: string; summary: string };

interface AssetDescription {
  type: 'image' | 'diagram' | 'screenshot' | 'chart';
  source: string;
  category: ImageCategory;
  description: string;
  extractedText?: string;
  structure?: any;  // 图表特有结构（如流程图节点）
}

type ImageCategory =
  | 'flowchart'     // 流程图
  | 'architecture'  // 架构图
  | 'screenshot'    // 界面截图
  | 'chart'         // 数据图表
  | 'table_image'   // 表格图片
  | 'photo'         // 照片
  | 'diagram'       // 其他图示
  | 'decorative';   // 装饰图（跳过）
```

#### 3.4.3 图片理解策略

```typescript
// 图片类型识别提示词
const IMAGE_CATEGORY_PROMPT = `
分析这张图片，判断其类型并按对应格式描述：

类型识别规则：
- flowchart: 包含箭头连接的节点、流程步骤
- architecture: 分层结构、模块组件、系统架构
- screenshot: UI界面、应用截图、网页截图
- chart: 柱状图、折线图、饼图等数据可视化
- table_image: 表格形式的数据
- photo: 自然照片、人物照片
- diagram: 其他示意图
- decorative: 图标、logo、装饰元素（简单标注即可）
`;

// 各类型专用描述模板
const DESCRIPTION_TEMPLATES = {
  flowchart: `
---
**[图片: {title}]**
类型: 流程图
节点:
{nodes}
流向: {flow_description}
关键路径: {critical_path}
---`,

  architecture: `
---
**[图片: {title}]**
类型: 架构图
层级:
{layers}
组件关系: {relationships}
---`,

  screenshot: `
---
**[图片: {title}]**
类型: 界面截图
布局: {layout}
主要元素: {elements}
提取文字: {extracted_text}
---`,

  chart: `
---
**[图片: {title}]**
类型: 数据图表
图表类型: {chart_type}
数据概要: {data_summary}
趋势/结论: {insights}
---`,

  table_image: `
---
**[图片: {title}]**
类型: 表格

| {headers} |
|{separators}|
{rows}
---`,

  photo: `
---
**[图片: {title}]**
描述: {description}
---`,

  decorative: `[图标: {brief}]`,
};

// 图片理解函数
async function understandImage(
  imageContent: Buffer,
  context?: string  // 上下文信息（如所在章节）
): Promise<AssetDescription> {

  // 1. 类型识别
  const category = await classifyImage(imageContent, IMAGE_CATEGORY_PROMPT);

  // 2. 跳过装饰图
  if (category === 'decorative') {
    return {
      type: 'image',
      source: '',
      category: 'decorative',
      description: '[装饰性图片，已跳过]',
    };
  }

  // 3. 根据类型应用专用分析
  const analysis = await analyzeImageByCategory(imageContent, category, context);

  // 4. 格式化描述
  const description = formatDescription(DESCRIPTION_TEMPLATES[category], analysis);

  return {
    type: 'image',
    source: '',
    category,
    description,
    extractedText: analysis.extractedText,
    structure: analysis.structure,
  };
}
```

#### 3.4.4 摘要生成

```typescript
interface Summary {
  file: string;
  type: string;
  title: string;
  summary: string;           // ≤200 字
  keyPoints: string[];       // 3-5 个要点
  structure: string[];       // 章节列表
  imageCount: number;
  hasCode: boolean;
  hasTables: boolean;
}

const SUMMARY_PROMPT = `
为以下内容生成结构化摘要，严格遵守字数限制：

要求：
1. summary: 核心内容概述，不超过 200 字
2. keyPoints: 3-5 个关键要点，每个不超过 50 字
3. structure: 列出主要章节标题

内容：
{content}

输出 JSON 格式。
`;

async function generateSummary(result: ExtractionResult): Promise<Summary> {
  // 如果内容较短，直接保留
  if (result.content.text.length <= SAFETY_LIMITS.output.summaryMaxChars) {
    return {
      file: result.source,
      type: result.type,
      title: result.content.title || basename(result.source),
      summary: result.content.text,
      keyPoints: [],
      structure: result.content.structure || [],
      imageCount: result.content.images?.length || 0,
      hasCode: /```/.test(result.content.text),
      hasTables: /\|.*\|/.test(result.content.text),
    };
  }

  // 使用 AI 生成摘要
  const response = await generateWithAI(SUMMARY_PROMPT, {
    content: result.content.text.substring(0, 10000),  // 限制输入
  });

  return {
    file: result.source,
    type: result.type,
    ...JSON.parse(response),
    imageCount: result.content.images?.length || 0,
    hasCode: /```/.test(result.content.text),
    hasTables: /\|.*\|/.test(result.content.text),
  };
}
```

---

### 3.5 输出生成层 (Output Generator)

#### 3.5.1 职责

- 将 IR 转换为最终输出格式
- 支持 Markdown、JSON 格式
- 可选调用 plugin-dev 生成 Skill/Plugin

#### 3.5.2 Markdown 输出

```typescript
function generateMarkdown(ir: IntermediateRepresentation): string {
  const lines: string[] = [];

  // 1. 元信息头
  lines.push('---');
  lines.push(`source: ${ir.meta.source}`);
  lines.push(`title: ${ir.meta.title}`);
  lines.push(`extracted_at: ${ir.meta.extractedAt}`);
  if (ir.meta.totalFiles) {
    lines.push(`total_files: ${ir.meta.totalFiles}`);
  }
  lines.push('stats:');
  lines.push(`  chars: ${ir.stats.totalChars}`);
  lines.push(`  images: ${ir.stats.totalImages}`);
  lines.push(`  files_processed: ${ir.stats.filesProcessed}`);
  if (ir.stats.errors > 0) {
    lines.push(`  errors: ${ir.stats.errors}`);
  }
  lines.push('---');
  lines.push('');

  // 2. 标题
  lines.push(`# ${ir.meta.title}`);
  lines.push('');

  // 3. 目录（如果有多个章节）
  if (ir.structure.length > 3) {
    lines.push('## 目录');
    lines.push('');
    for (const item of ir.structure) {
      const indent = '  '.repeat(item.level - 1);
      lines.push(`${indent}- ${item.title}`);
    }
    lines.push('');
  }

  // 4. 内容
  for (const block of ir.content) {
    lines.push(renderContentBlock(block, ir.assets));
    lines.push('');
  }

  return lines.join('\n');
}

function renderContentBlock(block: ContentBlock, assets: AssetDescription[]): string {
  switch (block.type) {
    case 'heading':
      return '#'.repeat(block.level) + ' ' + block.text;

    case 'paragraph':
      return block.text;

    case 'list':
      return block.items
        .map((item, i) => block.ordered ? `${i + 1}. ${item}` : `- ${item}`)
        .join('\n');

    case 'table':
      const header = '| ' + block.headers.join(' | ') + ' |';
      const separator = '|' + block.headers.map(() => '---').join('|') + '|';
      const rows = block.rows.map(row => '| ' + row.join(' | ') + ' |').join('\n');
      return [header, separator, rows].join('\n');

    case 'code':
      return '```' + (block.language || '') + '\n' + block.code + '\n```';

    case 'image_ref':
      return assets[block.assetIndex]?.description || '[图片]';

    case 'file_summary':
      return `### ${block.path}\n\n${block.summary}`;

    default:
      return '';
  }
}
```

#### 3.5.3 JSON 输出

```typescript
function generateJSON(ir: IntermediateRepresentation): string {
  return JSON.stringify({
    meta: ir.meta,
    stats: ir.stats,
    structure: ir.structure,
    content: ir.content.map(block => {
      if (block.type === 'image_ref') {
        return {
          type: 'image',
          ...ir.assets[block.assetIndex],
        };
      }
      return block;
    }),
  }, null, 2);
}
```

#### 3.5.4 Skill/Plugin 生成

```typescript
async function generateSkill(ir: IntermediateRepresentation): Promise<void> {
  // 调用 plugin-dev 的 skill-development skill
  await invokeSkill('plugin-dev:skill-development', {
    context: `
基于以下提取的内容，创建一个 Claude Code Skill：

来源：${ir.meta.source}
标题：${ir.meta.title}

内容摘要：
${ir.content.slice(0, 5).map(b =>
  b.type === 'paragraph' ? b.text.substring(0, 200) : ''
).join('\n')}

结构：
${ir.structure.map(s => '  '.repeat(s.level) + s.title).join('\n')}

请根据内容特点，设计合适的 Skill 结构。
`,
  });
}

async function generatePlugin(ir: IntermediateRepresentation): Promise<void> {
  // 调用 plugin-dev 的 plugin-structure skill
  await invokeSkill('plugin-dev:plugin-structure', {
    context: `
基于以下提取的内容，创建一个 Claude Code Plugin：

来源：${ir.meta.source}
标题：${ir.meta.title}
文件数：${ir.meta.totalFiles || 1}

内容结构：
${ir.structure.map(s => '  '.repeat(s.level) + s.title).join('\n')}

请设计合适的 Plugin 结构，包含必要的 commands、skills、agents。
`,
  });
}
```

---

## 4. 用户交互流程

### 4.1 标准流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           用户交互流程图                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   用户: /knowledge-etl:extract <source>                                 │
│                    │                                                     │
│                    ▼                                                     │
│   ┌────────────────────────────────────────┐                            │
│   │           输入解析                      │                            │
│   │                                        │                            │
│   │   - 识别类型                           │                            │
│   │   - 展开文件列表                       │                            │
│   │   - 计算总大小                         │                            │
│   └────────────────┬───────────────────────┘                            │
│                    │                                                     │
│                    ▼                                                     │
│   ┌────────────────────────────────────────┐                            │
│   │         预检 & 用户确认                 │                            │
│   │                                        │                            │
│   │   文件数 > 20?  ──是──→ 询问用户       │──→ 用户选择               │
│   │   总大小 > 10MB? ──是──→ 询问用户      │    - 全部处理             │
│   │                                        │    - 部分处理             │
│   └────────────────┬───────────────────────┘    - 取消                 │
│                    │                                                     │
│                    ▼                                                     │
│   ┌────────────────────────────────────────┐                            │
│   │           显示处理计划                  │                            │
│   │                                        │                            │
│   │   「发现 N 个文件，将分 M 批处理       │                            │
│   │     预计输出 X 字符的文档」            │                            │
│   └────────────────┬───────────────────────┘                            │
│                    │                                                     │
│                    ▼                                                     │
│   ┌────────────────────────────────────────┐                            │
│   │         批次处理循环                    │                            │
│   │                                        │                            │
│   │   for batch in batches:                │                            │
│   │     │                                  │                            │
│   │     ├─→ 处理文件/URL                   │                            │
│   │     │     │                            │                            │
│   │     │     ├─→ 遇到障碍?                │                            │
│   │     │     │     │                      │                            │
│   │     │     │     ├─→ 登录需求 ──→ 等待用户登录                      │
│   │     │     │     ├─→ 反爬检测 ──→ 询问是否截图                      │
│   │     │     │     └─→ 超时失败 ──→ 询问是否重试                      │
│   │     │     │                            │                            │
│   │     │     └─→ 提取成功 ──→ 生成摘要   │                            │
│   │     │                                  │                            │
│   │     └─→ 显示批次进度                   │                            │
│   │         「已完成 3/10 批次」           │                            │
│   └────────────────┬───────────────────────┘                            │
│                    │                                                     │
│                    ▼                                                     │
│   ┌────────────────────────────────────────┐                            │
│   │           汇总 & 输出选择               │                            │
│   │                                        │                            │
│   │   「提取完成！共处理 N 个文件          │                            │
│   │     请选择输出格式：                   │                            │
│   │                                        │                            │
│   │     [原始文档] [生成 Skill] [生成 Plugin]」                         │
│   └────────────────┬───────────────────────┘                            │
│                    │                                                     │
│                    ▼                                                     │
│   ┌────────────────────────────────────────┐                            │
│   │           生成最终输出                  │                            │
│   │                                        │                            │
│   │   用户选择 ──→ 生成对应格式            │                            │
│   └────────────────────────────────────────┘                            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 交互消息模板

```typescript
const MESSAGES = {
  // 开始提取
  start: (source: string, type: string) =>
    `正在分析 ${type} 来源: ${source}`,

  // 预检结果
  precheck: (stats: { files: number; size: string; batches: number }) =>
    `发现 ${stats.files} 个文件（约 ${stats.size}），将分 ${stats.batches} 批处理`,

  // 批次进度
  batchProgress: (current: number, total: number, file: string) =>
    `[${current}/${total}] 正在处理: ${file}`,

  // 障碍提示
  obstacle: {
    login: (url: string) =>
      `页面需要登录: ${url}\n请在弹出的浏览器中完成登录`,

    antiScrape: (url: string) =>
      `页面无法直接提取: ${url}\n建议使用截图模式`,

    timeout: (url: string) =>
      `请求超时: ${url}`,
  },

  // 完成提示
  complete: (stats: { files: number; chars: number; time: number }) =>
    `提取完成！\n` +
    `- 处理文件: ${stats.files} 个\n` +
    `- 提取内容: ${stats.chars} 字符\n` +
    `- 用时: ${stats.time} 秒`,

  // 错误提示
  error: (message: string) =>
    `提取失败: ${message}`,
};
```

---

## 5. 文件结构

```
platforms/claude/knowledge-etl/
├── adskill.yaml                    # 插件配置
├── .mcp.json                       # MCP 服务配置（Playwright）
├── DESIGN.md                       # 本设计文档
├── README.md                       # 用户文档
│
├── commands/
│   └── extract.md                  # 主命令
│
├── agents/
│   ├── extractor.md                # 提取执行 Agent（隔离上下文）
│   └── summarizer.md               # 摘要生成 Agent（可选）
│
├── skills/
│   ├── extract/
│   │   └── SKILL.md                # 提取技能说明
│   └── plugin-troubleshooting/
│       └── SKILL.md                # 问题排查技能
│
├── scripts/
│   ├── compress-image.sh           # 图片压缩脚本
│   └── compress-image.mjs          # 压缩实现
│
└── .claude-plugin/
    └── plugin.json                 # 插件清单
```

---

## 6. 配置项

```yaml
# knowledge-etl.config.yaml（未来支持）

# 安全限制
limits:
  image:
    max_size: 300KB
    max_width: 800
  pdf:
    max_pages: 20
  text:
    max_chars: 50000
  batch:
    max_files: 5
    max_size: 1MB

# 目录扫描
scanner:
  exclude:
    - node_modules
    - .git
    - "*.lock"
  include:
    - "*.md"
    - "*.pdf"
    - "*.png"
    - "*.jpg"

# 输出配置
output:
  default_format: markdown
  summary_max_chars: 500
  include_stats: true

# 缓存配置（未来支持）
cache:
  enabled: false
  ttl: 3600
  directory: .knowledge-etl-cache
```

---

## 7. 实现路线图

### Phase 1: 核心能力（当前）

- [x] 基础提取 Agent
- [x] 图片压缩脚本
- [ ] 安全控制层完善
- [ ] 用户交互流程
- [ ] 批次处理机制

### Phase 2: 增强功能

- [ ] 目录扫描与多文件处理
- [ ] 图片类型识别与专用描述
- [ ] JSON 输出格式
- [ ] 障碍检测与降级

### Phase 3: 集成与扩展

- [ ] Skill/Plugin 生成集成
- [ ] 缓存机制
- [ ] 增量处理
- [ ] 自定义提取器扩展

---

## 8. 附录

### 8.1 错误码定义

| 错误码 | 含义 | 处理方式 |
|--------|------|----------|
| E001 | 输入源不存在 | 提示用户检查路径 |
| E002 | 无访问权限 | 提示用户检查权限 |
| E003 | 网络超时 | 询问是否重试 |
| E004 | 需要登录 | 等待用户登录 |
| E005 | 反爬拦截 | 切换截图模式 |
| E006 | 文件过大 | 压缩或摘要模式 |
| E007 | 不支持的格式 | 跳过并记录 |
| E008 | 处理超限 | 分批或摘要模式 |

### 8.2 性能基准

| 场景 | 预期时间 | 输出大小 |
|------|----------|----------|
| 单个网页（无图） | 5-10s | 2-10KB |
| 单个网页（5张图） | 15-30s | 5-15KB |
| 单张大图片 | 5-10s | 0.5-1KB |
| 10 页 PDF | 20-40s | 10-20KB |
| 20 个文件目录 | 2-5min | 20-50KB |

### 8.3 术语表

| 术语 | 定义 |
|------|------|
| IR | Intermediate Representation，中间表示 |
| ETL | Extract-Transform-Load，提取-转换-加载 |
| 障碍 | 阻止正常提取的因素（登录、反爬等） |
| 摘要模式 | 只生成内容摘要，不保留全文 |
| 批次 | 一组同时处理的任务 |
