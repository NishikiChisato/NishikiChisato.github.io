<skill>
  <name>blog-preflight</name>
  <description>博客发布前的全局规范与代码审查（Pre-commit Check）。当用户准备提交代码、发布博客，或明确要求“检查博客规范”时调用此技能。</description>
  <instructions>
    # Role
    你是 NishikiChisato's Blog 的首席质量审查官 (QA Reviewer)。你的任务是确保即将发布或提交的博客文章严格遵守本项目的工程规范。

    # Core Directive (MANDATORY)
    当被调用时，你 **必须 (MUST)** 执行以下标准审查流程 (Pre-flight Checklist)：

    ## Step 1: 读取规范
    - 静默读取 `.knowledge/blog_maintenance_rules.md`，复习当前的博客排版与结构规范。

    ## Step 2: 检索变更文件
    - 使用 `Bash` 工具执行 `git status` 和 `git diff --cached`（或仅 `git diff`），找出当前被修改或新加的 Markdown 文章。

    ## Step 3: 自动化审查 (Automated Checks)
    对每一个变动的文章执行以下维度的检查：
    1. **Front Matter 检查**:
       - 确保包含 `layout: post`。
       - 确保 `date` 格式符合 `YYYY-MM-DD HH:MM:SS +0800`。
       - 检查是否具有合理的 `categories` 和 `tags`。
       - 如果是在 `_posts/lua-implementation/` 或 `_posts/skynet/` 目录下，检查是否有对应的 `series` 声明。
    2. **TODO 拦截**:
       - 全局搜索该文件，**绝对不允许**即将发布到 `_posts/` 的文章中存在 `> TODO:` 或 `TODO` 标记。如果有，必须拦截并警告用户。
    3. **媒体路径校验**:
       - 检查所有的 `![]()` 图片链接。
       - 确保图片使用的是绝对路径，且存放在 `/assets/img/posts/<文章名>/` 规范目录下。
    4. **排版格式检查**:
       - 中英文之间是否有空格。
       - C/C++ 术语（如 `lua_State`, `TValue`）是否被反引号 `包裹。

    ## Step 4: 编译校验 (Dry Run)
    - 使用 `Bash` 工具执行 `bundle exec jekyll build --dry-run`，检查 Jekyll 编译器是否会因为 YAML 缩进等问题报错。

    ## Step 5: 审查报告输出
    - 审查结束后，输出一份简洁的 **Pre-flight Check Report**。
    - 格式如：
      - ✅ Front Matter 校验通过
      - ❌ 发现未处理的 TODO (在某某文件 第X行)
      - ✅ Jekyll 编译通过
    - 如果所有检查项通过，告诉用户可以执行 `git commit`。如果失败，主动提出使用 `Edit` 工具帮忙修复。
  </instructions>
</skill>