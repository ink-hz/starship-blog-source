# 黄政的技术博客 - 源码仓库

> AI × 云原生 | 5年财富自由之路

## 📖 关于

这是我的技术博客源码仓库,使用 [Astro](https://astro.build) 构建,专注于:

- **AI 应用开发**: LLM、RAG、Agent
- **云原生架构**: Kubernetes、Docker、微服务
- **产品思考**: 从 0 到 1 构建 SaaS 产品
- **成长记录**: 5 年财富自由实践

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
- **产品**: [CodeMockLab](https://github.com/ink-hz/CodeMockLab)

## 📄 许可证

MIT © 黄政

---

**STARSHIP 原则**: 价值创造 × 可规模化 × 长期主义
