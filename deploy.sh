#!/bin/bash

# E养宠 部署脚本（支持前后端独立仓库）
# 使用方法: ./deploy.sh [命令]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目路径配置
DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$DEPLOY_DIR/eyangpet-backend"
FRONTEND_DIR="$DEPLOY_DIR/eyangpet-frontend"

# 检查 .env 文件
check_env() {
    if [ ! -f "$DEPLOY_DIR/.env" ]; then
        echo -e "${RED}错误: .env 文件不存在${NC}"
        echo "请复制 .env.example 为 .env 并修改配置"
        echo "  cp .env.example .env"
        exit 1
    fi
    source "$DEPLOY_DIR/.env"
}

# 初始化
init() {
    echo -e "${GREEN}初始化项目...${NC}"

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: Docker 未安装${NC}"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${RED}错误: Docker Compose 未安装${NC}"
        exit 1
    fi

    # 创建目录
    mkdir -p "$DEPLOY_DIR/nginx/conf.d" "$DEPLOY_DIR/nginx/ssl" "$DEPLOY_DIR/certbot/www" "$DEPLOY_DIR/certbot/conf"

    # 复制环境变量示例
    if [ ! -f "$DEPLOY_DIR/.env" ]; then
        if [ -f "$DEPLOY_DIR/.env.example" ]; then
            cp "$DEPLOY_DIR/.env.example" "$DEPLOY_DIR/.env"
            echo -e "${YELLOW}已创建 .env 文件，请修改配置后重新运行${NC}"
        else
            echo -e "${YELLOW}请创建 .env 文件${NC}"
        fi
    fi

    # 检查仓库是否存在
    if [ ! -d "$BACKEND_DIR" ]; then
        echo -e "${YELLOW}后端仓库不存在，请克隆：${NC}"
        echo "  git clone <你的后端仓库地址> $BACKEND_DIR"
    fi

    if [ ! -d "$FRONTEND_DIR" ]; then
        echo -e "${YELLOW}前端仓库不存在，请克隆：${NC}"
        echo "  git clone <你的前端仓库地址> $FRONTEND_DIR"
    fi

    echo -e "${GREEN}初始化完成${NC}"
}

# 拉取单个仓库
pull_repo() {
    local dir=$1
    local name=$2

    if [ ! -d "$dir/.git" ]; then
        echo -e "${RED}$name 不是 Git 仓库${NC}"
        return 1
    fi

    cd "$dir"
    CURRENT_BRANCH=$(git branch --show-current)
    echo -e "${BLUE}[$name]${NC} 分支: $CURRENT_BRANCH"

    # 检查是否有未提交的更改
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        echo -e "${YELLOW}[$name] 有未提交的本地更改${NC}"
        git status --short
    fi

    git pull origin "$CURRENT_BRANCH"
    echo -e "${GREEN}[$name] 拉取完成${NC}"
    echo -e "最新提交: $(git log -1 --oneline)"
    cd "$DEPLOY_DIR"
}

# 拉取所有代码
pull() {
    echo -e "${GREEN}拉取最新代码...${NC}"
    echo ""

    if [ -d "$BACKEND_DIR/.git" ]; then
        pull_repo "$BACKEND_DIR" "后端"
        echo ""
    fi

    if [ -d "$FRONTEND_DIR/.git" ]; then
        pull_repo "$FRONTEND_DIR" "前端"
    fi
}

# 只拉取后端
pull_backend() {
    echo -e "${GREEN}拉取后端代码...${NC}"
    pull_repo "$BACKEND_DIR" "后端"
}

# 只拉取前端
pull_frontend() {
    echo -e "${GREEN}拉取前端代码...${NC}"
    pull_repo "$FRONTEND_DIR" "前端"
}

# 一键更新（拉取 + 构建 + 重启）
update() {
    echo -e "${GREEN}========== 开始更新部署 ==========${NC}"
    echo ""

    # 1. 拉取代码
    pull
    echo ""

    # 2. 构建
    check_env
    build_frontend

    echo -e "${GREEN}重新构建后端镜像...${NC}"
    cd "$DEPLOY_DIR"
    docker compose build backend
    echo ""

    # 3. 重启服务
    echo -e "${GREEN}重启服务...${NC}"
    docker compose up -d
    echo ""

    echo -e "${GREEN}========== 更新完成 ==========${NC}"
    docker compose ps
}

# 快速更新后端
update_backend() {
    echo -e "${GREEN}快速更新后端...${NC}"

    pull_backend

    check_env
    cd "$DEPLOY_DIR"
    echo -e "${GREEN}重新构建后端镜像...${NC}"
    docker compose build backend

    echo -e "${GREEN}重启后端服务...${NC}"
    docker compose up -d backend

    echo -e "${GREEN}后端更新完成${NC}"
}

# 快速更新前端
update_frontend() {
    echo -e "${GREEN}快速更新前端...${NC}"

    pull_frontend
    build_frontend

    cd "$DEPLOY_DIR"
    echo -e "${GREEN}重载 Nginx...${NC}"
    docker compose exec nginx nginx -s reload

    echo -e "${GREEN}前端更新完成${NC}"
}

# 构建前端
build_frontend() {
    if [ ! -d "$FRONTEND_DIR" ]; then
        echo -e "${RED}错误: 前端目录不存在 ($FRONTEND_DIR)${NC}"
        exit 1
    fi

    echo -e "${GREEN}构建前端...${NC}"
    cd "$FRONTEND_DIR"
    npm install
    npm run build
    cd "$DEPLOY_DIR"
    echo -e "${GREEN}前端构建完成${NC}"
}

# 构建所有
build() {
    check_env

    if [ ! -d "$BACKEND_DIR" ]; then
        echo -e "${RED}错误: 后端目录不存在 ($BACKEND_DIR)${NC}"
        exit 1
    fi

    build_frontend

    echo -e "${GREEN}构建 Docker 镜像...${NC}"
    cd "$DEPLOY_DIR"
    docker compose build --no-cache
    echo -e "${GREEN}构建完成${NC}"
}

# 启动服务
start() {
    check_env
    cd "$DEPLOY_DIR"
    echo -e "${GREEN}启动服务...${NC}"
    docker compose up -d
    echo -e "${GREEN}服务已启动${NC}"
    echo ""
    docker compose ps
}

# 停止服务
stop() {
    cd "$DEPLOY_DIR"
    echo -e "${YELLOW}停止服务...${NC}"
    docker compose down
    echo -e "${GREEN}服务已停止${NC}"
}

# 重启服务
restart() {
    stop
    start
}

# 查看日志
logs() {
    cd "$DEPLOY_DIR"
    docker compose logs -f --tail=100 "$@"
}

# 查看状态
status() {
    echo -e "${BLUE}========== 后端仓库状态 ==========${NC}"
    if [ -d "$BACKEND_DIR/.git" ]; then
        cd "$BACKEND_DIR"
        echo -e "分支: $(git branch --show-current)"
        echo -e "最新提交: $(git log -1 --oneline)"

        git fetch origin --quiet 2>/dev/null || true
        LOCAL=$(git rev-parse HEAD 2>/dev/null)
        REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
        if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
            BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
            [ "$BEHIND" -gt 0 ] && echo -e "${YELLOW}有 $BEHIND 个新提交可拉取${NC}"
        else
            echo -e "${GREEN}代码已是最新${NC}"
        fi
    else
        echo -e "${YELLOW}后端仓库不存在${NC}"
    fi

    echo ""
    echo -e "${BLUE}========== 前端仓库状态 ==========${NC}"
    if [ -d "$FRONTEND_DIR/.git" ]; then
        cd "$FRONTEND_DIR"
        echo -e "分支: $(git branch --show-current)"
        echo -e "最新提交: $(git log -1 --oneline)"

        git fetch origin --quiet 2>/dev/null || true
        LOCAL=$(git rev-parse HEAD 2>/dev/null)
        REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
        if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
            BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
            [ "$BEHIND" -gt 0 ] && echo -e "${YELLOW}有 $BEHIND 个新提交可拉取${NC}"
        else
            echo -e "${GREEN}代码已是最新${NC}"
        fi
    else
        echo -e "${YELLOW}前端仓库不存在${NC}"
    fi

    cd "$DEPLOY_DIR"
    echo ""
    echo -e "${BLUE}========== 服务状态 ==========${NC}"
    docker compose ps

    echo ""
    echo -e "${BLUE}========== 资源使用 ==========${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "无法获取资源信息"
}

# 申请 SSL 证书
ssl_init() {
    check_env

    if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
        echo -e "${RED}错误: 请在 .env 中设置 DOMAIN 和 EMAIL${NC}"
        exit 1
    fi

    echo -e "${GREEN}申请 SSL 证书...${NC}"
    echo "域名: $DOMAIN"
    echo "邮箱: $EMAIL"

    cd "$DEPLOY_DIR"
    docker compose up -d nginx
    sleep 5

    docker compose run --rm certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN"

    echo -e "${GREEN}证书申请成功！${NC}"
    echo ""
    echo "请执行以下步骤启用 HTTPS:"
    echo "1. mv nginx/conf.d/default.conf nginx/conf.d/default.conf.http"
    echo "2. mv nginx/conf.d/default.conf.ssl nginx/conf.d/default.conf"
    echo "3. docker compose restart nginx"
}

# 续期证书
ssl_renew() {
    cd "$DEPLOY_DIR"
    echo -e "${GREEN}续期 SSL 证书...${NC}"
    docker compose run --rm certbot renew
    docker compose exec nginx nginx -s reload
    echo -e "${GREEN}证书续期完成${NC}"
}

# 数据库备份
db_backup() {
    cd "$DEPLOY_DIR"
    BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).sql"
    echo -e "${GREEN}备份数据库到 $BACKUP_FILE ...${NC}"
    docker exec eyangpet-db pg_dump -U postgres eyangpet > "$BACKUP_FILE"
    echo -e "${GREEN}备份完成: $BACKUP_FILE${NC}"
}

# 克隆仓库（首次部署用）
clone() {
    echo -e "${GREEN}克隆仓库...${NC}"

    if [ -z "$GIT_BACKEND_URL" ] || [ -z "$GIT_FRONTEND_URL" ]; then
        echo -e "${YELLOW}请在 .env 中设置 GIT_BACKEND_URL 和 GIT_FRONTEND_URL${NC}"
        echo ""
        echo "或者手动克隆："
        echo "  git clone <后端仓库地址> $BACKEND_DIR"
        echo "  git clone <前端仓库地址> $FRONTEND_DIR"
        exit 1
    fi

    if [ ! -d "$BACKEND_DIR" ]; then
        echo -e "${GREEN}克隆后端仓库...${NC}"
        git clone "$GIT_BACKEND_URL" "$BACKEND_DIR"
    else
        echo -e "${YELLOW}后端仓库已存在，跳过${NC}"
    fi

    if [ ! -d "$FRONTEND_DIR" ]; then
        echo -e "${GREEN}克隆前端仓库...${NC}"
        git clone "$GIT_FRONTEND_URL" "$FRONTEND_DIR"
    else
        echo -e "${YELLOW}前端仓库已存在，跳过${NC}"
    fi

    echo -e "${GREEN}克隆完成${NC}"
}

# 主函数
case "$1" in
    init)
        init
        ;;
    clone)
        clone
        ;;
    pull)
        pull
        ;;
    pull-backend)
        pull_backend
        ;;
    pull-frontend)
        pull_frontend
        ;;
    update)
        update
        ;;
    update-backend)
        update_backend
        ;;
    update-frontend)
        update_frontend
        ;;
    build)
        build
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    logs)
        shift
        logs "$@"
        ;;
    status)
        status
        ;;
    ssl-init)
        ssl_init
        ;;
    ssl-renew)
        ssl_renew
        ;;
    db-backup)
        db_backup
        ;;
    *)
        echo "E养宠 部署脚本"
        echo ""
        echo "使用方法: ./deploy.sh [命令]"
        echo ""
        echo "首次部署:"
        echo "  init            初始化目录结构"
        echo "  clone           克隆前后端仓库（需配置 .env）"
        echo ""
        echo "代码管理:"
        echo "  pull            拉取所有仓库的最新代码"
        echo "  pull-backend    只拉取后端"
        echo "  pull-frontend   只拉取前端"
        echo "  update          一键更新（拉取 + 构建 + 重启）"
        echo "  update-backend  只更新后端"
        echo "  update-frontend 只更新前端"
        echo "  status          查看仓库和服务状态"
        echo ""
        echo "服务管理:"
        echo "  build           构建 Docker 镜像"
        echo "  start           启动所有服务"
        echo "  stop            停止所有服务"
        echo "  restart         重启所有服务"
        echo "  logs [服务名]   查看日志"
        echo ""
        echo "SSL 证书:"
        echo "  ssl-init        申请 SSL 证书"
        echo "  ssl-renew       续期 SSL 证书"
        echo ""
        echo "数据库:"
        echo "  db-backup       备份数据库"
        ;;
esac
