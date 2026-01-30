# AI 架构实践 - 源码仓库

> 大规模 AI 应用的架构设计与工程实践

## 📖 关于

这是一个专注于 AI 架构的技术博客，使用 [Astro](https://astro.build) 构建。内容涵盖:

- **LLM 应用开发**: RAG、Agent、Prompt Engineering
- **分布式训练**: 多机多卡、数据并行、模型并行
- **推理优化**: 量化、剪枝、蒸馏、KV Cache
- **云原生部署**: Kubernetes、GPU 调度、弹性伸缩
- **成本优化**: 资源利用率、Spot 实例、混合部署

## 🚀 快速开始

```bash
# 安装依赖
npm install

# 本地开发
npm run dev

# 构建
npm run build

# 预览构建结果
npm run preview
```

## 📝 写作

所有文章在 `src/content/blog/` 目录:

```bash
# 创建新文章
touch src/content/blog/new-post.md
```

文章格式:

```markdown
---
title: '文章标题'
description: '文章描述'
pubDate: 2026-01-30
tags: ['AI', '云原生']
---

## 正文内容...
```

## 🎯 项目结构

```
├── src/
│   ├── content/
│   │   └── blog/          # 博客文章 (Markdown)
│   ├── layouts/           # 页面布局
│   ├── pages/             # 路由页面
│   └── components/        # 组件
├── public/                # 静态资源
└── astro.config.mjs       # Astro 配置
```

## 🔗 相关链接

- **博客**: [ink-hz.github.io](https://ink-hz.github.io)
- **GitHub**: [@ink-hz](https://github.com/ink-hz)

## 📄 许可证

MIT

---

**专注**: 大规模 AI 应用的架构设计与工程实践
