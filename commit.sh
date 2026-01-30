#!/bin/bash

# Git 一键提交脚本
# 用法: ./commit.sh "你的提交信息"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否提供了提交信息
if [ -z "$1" ]; then
    echo -e "${RED}错误: 请提供提交信息${NC}"
    echo "用法: ./commit.sh \"你的提交信息\""
    exit 1
fi

COMMIT_MSG="$1"

# 显示当前状态
echo -e "${YELLOW}=== 当前 Git 状态 ===${NC}"
git status

# 添加所有更改
echo -e "\n${YELLOW}=== 添加所有更改 ===${NC}"
git add .

# 显示将要提交的内容
echo -e "\n${YELLOW}=== 将要提交的更改 ===${NC}"
git status --short

# 提交
echo -e "\n${YELLOW}=== 提交更改 ===${NC}"
git commit -m "$COMMIT_MSG

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# 检查提交是否成功
if [ $? -ne 0 ]; then
    echo -e "${RED}提交失败！${NC}"
    exit 1
fi

# 推送到远程
echo -e "\n${YELLOW}=== 推送到远程仓库 ===${NC}"
git push

# 检查推送是否成功
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ 成功提交并推送！${NC}"
    echo -e "提交信息: ${GREEN}$COMMIT_MSG${NC}"
else
    echo -e "\n${RED}推送失败！请检查网络或远程仓库配置${NC}"
    exit 1
fi
