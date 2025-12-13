---
name: Plugin Troubleshooting
description: This skill should be used when a Claude Code plugin command is not visible, plugin not loading, or plugin errors occur. Provides systematic diagnostic flow for plugin issues.
version: 1.0.0
---

# Plugin Troubleshooting Guide

When a plugin command is not visible or a plugin fails to load, follow this **systematic diagnostic flow** in order. Do NOT skip steps or jump to conclusions.

## Diagnostic Flow (Follow This Order)

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: Check marketplace.json                                 │
│  Is the plugin registered in the marketplace?                   │
│  Location: .claude-plugin/marketplace.json                      │
├─────────────────────────────────────────────────────────────────┤
│  Step 2: Check installed_plugins.json                           │
│  Is the plugin installed with correct path?                     │
│  Location: ~/.claude/plugins/installed_plugins.json             │
├─────────────────────────────────────────────────────────────────┤
│  Step 3: Check settings.json                                    │
│  Is the plugin enabled?                                         │
│  Location: ~/.claude/settings.json → enabledPlugins             │
├─────────────────────────────────────────────────────────────────┤
│  Step 4: Validate plugin structure                              │
│  Are all files in correct locations?                            │
│  Run: claude plugin validate <plugin-path>                      │
├─────────────────────────────────────────────────────────────────┤
│  Step 5: Check component files                                  │
│  Is the command/agent/skill file correctly formatted?           │
│  Check YAML frontmatter syntax                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Step 1: Check marketplace.json (MOST COMMON ISSUE)

**This is the #1 cause of "command not found" issues.**

```bash
# For ai-rd marketplace:
cat ~/.claude/plugins/marketplaces/ai-rd/.claude-plugin/marketplace.json

# Check if your plugin is listed in the "plugins" array
```

**What to look for:**
```json
{
  "plugins": [
    {
      "name": "your-plugin-name",
      "source": "./platforms/claude/your-plugin-name",
      "description": "..."
    }
  ]
}
```

**If missing:** Add the plugin entry and sync to cache:
```bash
# Edit source marketplace.json
# Then copy to cache:
cp /path/to/repo/.claude-plugin/marketplace.json \
   ~/.claude/plugins/marketplaces/<marketplace>/.claude-plugin/marketplace.json
```

## Step 2: Check installed_plugins.json

```bash
cat ~/.claude/plugins/installed_plugins.json | jq '.plugins["your-plugin@marketplace"]'
```

**What to verify:**
- `installPath` points to correct location
- Path exists and contains `.claude-plugin/plugin.json`

**Common issues:**
- Wrong path (marketplace structure changed)
- Stale entries for renamed/deleted plugins
- Missing plugin entry entirely

## Step 3: Check settings.json

```bash
grep -A 20 "enabledPlugins" ~/.claude/settings.json
```

**What to verify:**
- Plugin is listed in `enabledPlugins`
- Value is `true` (not `false`)

**If missing or false:**
```json
{
  "enabledPlugins": {
    "your-plugin@marketplace": true
  }
}
```

## Step 4: Validate Plugin Structure

```bash
claude plugin validate /path/to/plugin
```

**Expected output:** "Validation passed"

**Common validation failures:**
- Missing `.claude-plugin/plugin.json`
- Invalid JSON syntax
- Missing required fields

## Step 5: Check Component Files

**For commands:**
```bash
# Check command exists
ls /path/to/plugin/commands/

# Check frontmatter format
head -20 /path/to/plugin/commands/your-command.md
```

**Valid command frontmatter:**
```yaml
---
name: "command-name"
description: "What this command does"
---
```

**For hooks (hooks.json):**
```json
// CORRECT - Object keyed by event name:
{
  "PostToolUse": [...],
  "SessionStart": [...]
}

// WRONG - Array format:
{
  "hooks": [...]  // ❌ This causes "Expected object, received array"
}
```

## Quick Diagnostic Commands

```bash
# 1. Check if plugin is in marketplace
grep -r "your-plugin" ~/.claude/plugins/marketplaces/*/.claude-plugin/marketplace.json

# 2. Check if plugin is installed
grep "your-plugin" ~/.claude/plugins/installed_plugins.json

# 3. Check if plugin is enabled
grep "your-plugin" ~/.claude/settings.json

# 4. Validate plugin
claude plugin validate /path/to/plugin

# 5. Check marketplace symlink
ls -la ~/.claude/plugins/marketplaces/
```

## Common Error Messages and Solutions

| Error Message | Cause | Solution |
|---------------|-------|----------|
| "Command not found" | Plugin not in marketplace.json | Add plugin to marketplace.json |
| "Plugin not found in marketplace" | Stale entry in settings.json | Remove from enabledPlugins |
| "Hook load failed: Expected object, received array" | hooks.json uses array format | Convert to object format keyed by event |
| "Validation failed" | Missing or invalid plugin.json | Check .claude-plugin/plugin.json |

## After Making Changes

**Always restart Claude Code** to reload plugins. Changes to:
- marketplace.json
- installed_plugins.json
- settings.json
- Plugin files

All require a restart to take effect.

## Prevention Checklist

When creating a new plugin:

1. [ ] Add plugin to marketplace.json
2. [ ] Verify plugin.json has required `name` field
3. [ ] Check command frontmatter has `name` and `description`
4. [ ] Use object format (not array) for hooks.json
5. [ ] Test with `claude plugin validate`
6. [ ] Restart Claude Code and verify command appears
