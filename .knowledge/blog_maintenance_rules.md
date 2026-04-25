# 博客维护通用规范 (Blog Maintenance Guidelines)

## 1. 结构规范
- 所有的博客文章必须存放在 `_posts/` 目录的对应子目录中。
- 所有的数据配置（如书单、关于我）必须在 `_data/` 目录中更新，不要直接修改布局代码。
- 文章命名必须严格遵循 Jekyll 格式：`YYYY-MM-DD-title-in-english.md`，且单词全小写，用连字符连接。

## 2. Front Matter 规范
每篇文章的开头必须包含以下 YAML Front Matter：
```yaml
---
layout: post
title: "你的文章标题 (支持标点，但不要出现未转义的冒号)"
date: YYYY-MM-DD HH:MM:SS +0800
categories:
  - 父分类
  - 子分类
tags:
  - 标签1
  - 标签2
---
```

## 3. 内容与风格规范
- **内容基调**："Where I Grow" - 内容应体现学习过程、思考和总结，避免流水账。
- **排版要求**：
  - 中英文之间必须保留一个空格（例如：学习 Lua 源码）。
  - 使用标准的 Markdown 标题层级（从 `##` 开始，因为 `<h1>` 已经被文章标题占用）。
  - 代码块必须指明语言类型（如 ````c`, ````lua`）。
- **图片处理**：所有的文章配图必须存放在 `assets/img/posts/<文章名>/` 目录中，并在文章中使用相对根目录的路径引用，例如 `![description](/assets/img/posts/egiu-overview/pic1.png)`。

## 4. 工作流与草稿管理
- **草稿目录**：尚未完成的文章存放在 `_drafts/` 目录下。
- **TODO 追踪**：如果草稿中有未完成的内容，使用 `> TODO: [待办事项描述]` 的格式进行标记。
- **发布流程**：在发布前（即将文章从 `_drafts/` 移动到 `_posts/` 时），**必须 (MUST)** 全局搜索并清理该文件中的所有 TODO 标记，确保发布的文章是完整状态。