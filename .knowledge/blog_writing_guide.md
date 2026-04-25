# 博客写作与发布操作指南 (Blog Writing & Publishing Guide)

太久没写博客忘记怎么操作了？没关系，按照以下步骤可以快速找回状态！

## 1. 使用命令行创建新文章/草稿 (Command Line Shortcuts)
你不需要手动去拼凑复杂的日期和文件名！你的 `Gemfile` 里已经安装了 `jekyll-compose` 插件，可以直接用命令生成：

### 创建一篇正式文章 (Post)
在终端运行：
```bash
bundle exec jekyll post "你的文章标题"
```
*这会自动在 `_posts/` 目录下生成一个带好日期前缀的文件（例如：`_posts/2025-08-01-你的文章标题.md`），并且自动填好了 Front Matter。*

### 创建一篇草稿 (Draft)
如果你还没写完，不想马上发布，可以建草稿：
```bash
bundle exec jekyll draft "你的草稿标题"
```
*这会在 `_drafts/` 目录下生成文件，没有日期前缀。*

### 将草稿转为正式文章 (Publish)
草稿写完后准备发布：
```bash
bundle exec jekyll publish _drafts/你的草稿标题.md
```
*这会自动把草稿移到 `_posts/` 目录，并加上当天的日期前缀。*

---

## 2. 完善 Front Matter
生成文件后，打开它，稍微完善一下顶部的信息：
```yaml
---
layout: post
title: "文章的大标题（会显示在网页上）"
date: 2025-08-01 12:00:00 +0800
categories:
  - 父分类 (如 Lua Implementation)
tags:
  - 标签1
  - 标签2
series: "如果是连载文章，这里填系列名称（可选）"
---
```
*(Front Matter 之后空一行，直接开始写 Markdown 正文即可)*

## 2. 处理图片 (Images)
不要把图片随意丢在根目录！
1. 在 `assets/img/posts/` 目录下，以**文章短名**创建一个专属文件夹。
   > 例如：`assets/img/posts/lua-gc-basics/`
2. 把图片存入该文件夹。
3. 在 Markdown 中引用时，使用**绝对路径**（以 `/` 开头）：
   ```markdown
   ![图解GC机制](/assets/img/posts/lua-gc-basics/architecture.png)
   ```

## 3. 本地预览测试 (Local Preview)
写完之后，在终端（Terminal）执行以下命令来启动本地服务器：
```bash
bundle install              # 如果很久没跑了，先安装/更新一下依赖
bundle exec jekyll serve    # 启动本地服务 (可简写为 bundle exec jekyll s)
```
启动成功后，在浏览器打开：`http://localhost:4000` 即可预览效果。

## 4. 提交与发布 (Publish)
因为博客托管在 GitHub Pages 上，所以“发布”就是“提交代码”。
在终端执行以下三连：
```bash
git add .
git commit -m "feat: 发布新文章《文章标题》"
git push
```
稍等 1~2 分钟，刷新您的博客域名 `https://NishikiChisato.github.io`，新文章就上线了！

---

## 💡 终极“懒人”模式 (AI 协助)
如果你连这些步骤都不想记，**直接把一堆文字草稿或截图扔给 AI**，并对我说：
> *"这是一些关于 Lua GC 的乱七八糟的笔记，帮我整理成一篇新博客。"*

我会自动帮你：
1. 梳理逻辑，排版成硬核的文章格式。
2. 自动创建 `_posts/` 下的 `.md` 文件并命名。
3. 自动帮你写好 Front Matter（标题、分类、时间、系列）。
4. 帮你把未完成的部分打上 `> TODO:` 标记放入草稿箱。