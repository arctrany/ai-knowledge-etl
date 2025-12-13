# Common Regex Patterns for Relevance Scoring

## Technology Domains

### API Development
```regex
API|REST|GraphQL|endpoint|接口|端点|认证|authentication|OAuth|JWT|token
```

### Frontend Development
```regex
React|Vue|Angular|component|组件|UI|UX|CSS|样式|responsive|响应式
```

### Backend Development
```regex
database|数据库|SQL|NoSQL|server|服务器|microservice|微服务|cache|缓存
```

### DevOps
```regex
Docker|Kubernetes|CI/CD|deploy|部署|container|容器|pipeline|monitoring|监控
```

### Security
```regex
security|安全|authentication|授权|encryption|加密|vulnerability|漏洞|OWASP
```

## Documentation Types

### Getting Started
```regex
getting.?started|quick.?start|入门|快速开始|tutorial|教程|guide|指南
```

### Reference
```regex
reference|参考|API.?docs|specification|规范|schema|模式
```

### Examples
```regex
example|示例|sample|demo|演示|cookbook|recipes
```

## Multi-language Support

### Chinese + English
```regex
API|接口|authentication|认证|configuration|配置|deployment|部署
```

### Common Abbreviations
```regex
API|SDK|CLI|UI|UX|DB|SQL|HTTP|REST|JSON|YAML|XML
```

## Usage Tips

1. **Combine patterns with OR**: `pattern1|pattern2|pattern3`
2. **Case insensitive**: Always use `-i` flag with grep
3. **Word boundaries**: Use `\b` for exact matches: `\bAPI\b`
4. **Flexible spacing**: Use `.?` for optional characters: `getting.?started`
