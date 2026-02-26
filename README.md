# E养宠 部署仓库

E养宠（宠物寄养服务平台）的 Docker 部署配置和自动化脚本。

## 目录

- [系统架构](#系统架构)
- [技术栈](#技术栈)
- [仓库结构](#仓库结构)
- [环境要求](#环境要求)
- [快速部署](#快速部署)
- [deploy.sh 命令详解](#deploysh-命令详解)
- [环境变量配置](#环境变量配置)
- [Nginx 配置](#nginx-配置)
- [SSL 证书管理](#ssl-证书管理)
- [数据库管理](#数据库管理)
- [日常运维](#日常运维)
- [故障排查](#故障排查)
- [安全建议](#安全建议)

---

## 系统架构

```
                         ┌─────────────────┐
                         │    用户访问      │
                         │  your-domain    │
                         └────────┬────────┘
                                  │
                                  ▼ 80/443
                         ┌─────────────────┐
                         │     Nginx       │
                         │   (反向代理)     │
                         │  - SSL 终结     │
                         │  - Gzip 压缩    │
                         │  - 静态文件缓存  │
                         └────────┬────────┘
                                  │
               ┌──────────────────┴──────────────────┐
               │                                     │
               ▼                                     ▼
      ┌─────────────────┐                   ┌─────────────────┐
      │   前端静态文件   │                   │    后端 API     │
      │   Vue 3 SPA     │                   │  Spring Boot    │
      │   /dist         │                   │    :9909        │
      └─────────────────┘                   └────────┬────────┘
                                                     │
                                                     ▼
                                            ┌─────────────────┐
                                            │   PostgreSQL    │
                                            │     :5432       │
                                            │   (数据持久化)   │
                                            └─────────────────┘
```

### 容器组成

| 容器名称 | 镜像 | 端口 | 说明 |
|---------|------|------|------|
| eyangpet-nginx | nginx:alpine | 80, 443 | 反向代理、静态文件服务 |
| eyangpet-backend | 自构建 | 9909 (内部) | Spring Boot 后端 API |
| eyangpet-db | postgres:15-alpine | 5432 (内部) | PostgreSQL 数据库 |
| eyangpet-certbot | certbot/certbot | - | SSL 证书管理 |

### 数据流

1. 用户访问 `https://your-domain.com`
2. Nginx 接收请求，SSL 终结
3. 静态资源请求 → 直接返回 `/dist` 目录文件
4. API 请求 (`/api/*`) → 代理到后端服务 `:9909`
5. 后端服务 → 访问 PostgreSQL 数据库

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 前端 | Vue 3 + Vite + TypeScript + Pinia + Vue Router |
| 后端 | Spring Boot 3 + MyBatis Plus + Flyway |
| 数据库 | PostgreSQL 15 |
| 容器化 | Docker + Docker Compose |
| Web 服务器 | Nginx (反向代理 + 静态文件) |
| SSL | Let's Encrypt (Certbot) |

---

## 仓库结构

本项目采用**三仓库分离**架构：

```
/home/ubuntu/eyangpet/           # 部署根目录
├── eyangpet-deployment/         # 本仓库 - 部署配置
│   ├── deploy.sh                # 一键部署脚本
│   ├── docker-compose.yml       # Docker 编排配置
│   ├── .env.example             # 环境变量模板
│   ├── .env                     # 环境变量（不提交到 Git）
│   ├── nginx/
│   │   └── conf.d/
│   │       ├── default.conf.template      # HTTP 配置模板
│   │       ├── default.conf.ssl.template  # HTTPS 配置模板
│   │       └── default.conf               # 生成的配置（不提交）
│   ├── certbot/                 # SSL 证书（自动生成）
│   │   ├── conf/
│   │   └── www/
│   └── README.md
│
├── eyangpet-backend/            # 后端仓库
│   ├── src/
│   ├── Dockerfile
│   └── pom.xml
│
└── eyangpet-frontend/           # 前端仓库
    ├── src/
    ├── dist/                    # 构建产物
    └── package.json
```

### 相关仓库

- **部署配置**: [eyangpet-deployment](https://github.com/LyneDefense/eyangpet-deployment)
- **后端代码**: [eyangpet-backend](https://github.com/LyneDefense/eyangpet-backend)
- **前端代码**: [eyangpet-frontend](https://github.com/LyneDefense/eyangpet-frontend)

---

## 环境要求

### 服务器要求

- **操作系统**: Ubuntu 20.04+ / CentOS 7+ / Debian 10+
- **内存**: 最低 2GB，推荐 4GB+
- **硬盘**: 最低 20GB
- **CPU**: 1 核+

### 软件要求

- Docker 20.10+
- Docker Compose V2
- Git
- Node.js 18+ (用于构建前端)

### 网络要求

- 域名已备案（国内服务器必须）
- 域名已解析到服务器 IP
- 防火墙开放端口：80、443、22(SSH)

---

## 快速部署

### 第一步：安装 Docker

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker $USER  # 允许当前用户使用 docker

# 重新登录使权限生效
exit
```

**国内服务器配置镜像加速：**

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.mirrors.ustc.edu.cn"
  ]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 第二步：安装 Node.js

```bash
# 使用 NodeSource 安装 Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 验证安装
node --version  # 应该显示 v20.x.x
npm --version
```

### 第三步：克隆部署仓库

```bash
mkdir -p /home/ubuntu/eyangpet
cd /home/ubuntu/eyangpet
git clone https://github.com/LyneDefense/eyangpet-deployment.git .
chmod +x deploy.sh
```

### 第四步：配置环境变量

```bash
cp .env.example .env
vim .env
```

必须配置的变量：

```bash
# Git 仓库地址（SSH 方式）
GIT_BACKEND_URL=git@github.com:LyneDefense/eyangpet-backend.git
GIT_FRONTEND_URL=git@github.com:LyneDefense/eyangpet-frontend.git

# 数据库密码（设置强密码）
DB_PASSWORD=YourStrongPassword123!

# JWT 密钥（至少 32 字符随机字符串）
JWT_SECRET=your-32-character-random-string-here

# 域名配置
DOMAIN=your-domain.com
EMAIL=your-email@example.com
CORS_ORIGINS=https://your-domain.com
```

### 第五步：克隆前后端代码

```bash
./deploy.sh clone
```

### 第六步：构建并启动

```bash
# 初始化（生成 nginx 配置等）
./deploy.sh init

# 构建前端和后端镜像
./deploy.sh build

# 启动所有服务
./deploy.sh start

# 查看状态
./deploy.sh status
```

### 第七步：申请 SSL 证书

```bash
# 申请证书并自动切换到 HTTPS
./deploy.sh ssl-init
```

完成！访问 `https://your-domain.com` 查看网站。

---

## deploy.sh 命令详解

运行 `./deploy.sh` 查看所有可用命令。

### 首次部署

| 命令 | 说明 |
|------|------|
| `init` | 初始化目录结构，生成 nginx 配置 |
| `clone` | 克隆前后端仓库（需先配置 .env） |

### 代码管理

| 命令 | 说明 |
|------|------|
| `pull` | 拉取所有仓库的最新代码 |
| `pull-backend` | 只拉取后端代码 |
| `pull-frontend` | 只拉取前端代码 |
| `update` | **一键更新**（拉取 + 构建 + 重启） |
| `update-backend` | 只更新后端（拉取 + 构建 + 重启后端） |
| `update-frontend` | 只更新前端（拉取 + 构建 + 重载 nginx） |
| `status` | 查看仓库状态、服务状态、资源使用 |

### 服务管理

| 命令 | 说明 |
|------|------|
| `build` | 构建所有 Docker 镜像 |
| `start` | 启动所有服务 |
| `stop` | 停止所有服务 |
| `restart` | 重启所有服务 |
| `logs` | 查看所有服务日志 |
| `logs backend` | 只查看后端日志 |
| `logs nginx` | 只查看 nginx 日志 |
| `logs postgres` | 只查看数据库日志 |

### SSL 证书

| 命令 | 说明 |
|------|------|
| `ssl-init` | 申请 SSL 证书（自动切换到 HTTPS 配置） |
| `ssl-renew` | 手动续期 SSL 证书 |
| `nginx-http` | 生成 HTTP 配置 |
| `nginx-https` | 生成 HTTPS 配置 |

### 数据库

| 命令 | 说明 |
|------|------|
| `db-backup` | 备份数据库到 SQL 文件 |

### 使用示例

```bash
# 日常更新代码
./deploy.sh update

# 只更新后端（前端没改）
./deploy.sh update-backend

# 查看后端日志（最近 100 行，实时跟踪）
./deploy.sh logs backend

# 查看所有服务状态
./deploy.sh status

# 备份数据库
./deploy.sh db-backup
```

---

## 环境变量配置

`.env` 文件包含所有敏感配置，**不要提交到 Git**。

```bash
# ============ Git 仓库配置 ============
# SSH 方式（推荐）
GIT_BACKEND_URL=git@github.com:username/eyangpet-backend.git
GIT_FRONTEND_URL=git@github.com:username/eyangpet-frontend.git

# HTTPS 方式（需要输入密码或 Token）
# GIT_BACKEND_URL=https://github.com/username/eyangpet-backend.git
# GIT_FRONTEND_URL=https://github.com/username/eyangpet-frontend.git

# ============ 数据库配置 ============
DB_NAME=eyangpet
DB_USER=postgres
DB_PASSWORD=your_secure_database_password

# ============ 安全配置 ============
# JWT 密钥（至少 32 字符）
JWT_SECRET=your_jwt_secret_key_at_least_256_bits_long

# ============ 域名配置 ============
DOMAIN=your-domain.com
EMAIL=admin@your-domain.com
CORS_ORIGINS=https://your-domain.com
```

### 环境变量传递链

```
.env → docker-compose.yml → 容器环境变量 → application-prod.yml
```

---

## Nginx 配置

### 配置模板

Nginx 配置使用**模板机制**，避免手动替换域名：

- `default.conf.template` - HTTP 配置模板
- `default.conf.ssl.template` - HTTPS 配置模板
- `default.conf` - 生成的实际配置（不提交到 Git）

### 生成配置

```bash
# 生成 HTTP 配置
./deploy.sh nginx-http

# 生成 HTTPS 配置
./deploy.sh nginx-https

# 重启 nginx 应用配置
docker compose restart nginx
```

域名会自动从 `.env` 文件的 `DOMAIN` 变量读取。

### 性能优化

配置中已包含以下优化：

- **Gzip 压缩**: 压缩 JS/CSS/JSON 等文本资源
- **静态资源缓存**: JS/CSS/图片等缓存 30 天
- **HTTP/2**: HTTPS 配置启用 HTTP/2
- **SSL Session 缓存**: 减少 SSL 握手开销

---

## SSL 证书管理

### 首次申请

```bash
./deploy.sh ssl-init
```

这个命令会：
1. 生成 HTTP 配置
2. 启动 nginx
3. 通过 Let's Encrypt 申请证书
4. 自动切换到 HTTPS 配置
5. 重启 nginx

### 证书续期

Let's Encrypt 证书有效期 90 天，需要定期续期：

```bash
# 手动续期
./deploy.sh ssl-renew
```

### 自动续期（推荐）

设置 crontab 定时任务：

```bash
crontab -e
```

添加以下行（每月 1 号凌晨 3 点执行）：

```
0 3 1 * * cd /home/ubuntu/eyangpet/eyangpet-deployment && ./deploy.sh ssl-renew >> /var/log/certbot-renew.log 2>&1
```

### 查看证书状态

```bash
docker compose run --rm certbot certificates
```

---

## 数据库管理

### 备份

```bash
# 使用 deploy.sh
./deploy.sh db-backup

# 手动备份
docker exec eyangpet-db pg_dump -U postgres eyangpet > backup_$(date +%Y%m%d).sql
```

### 恢复

```bash
docker exec -i eyangpet-db psql -U postgres eyangpet < backup_20240101.sql
```

### 连接数据库

```bash
# 进入 psql
docker exec -it eyangpet-db psql -U postgres -d eyangpet

# 常用 SQL
\dt                    # 查看所有表
\d+ table_name         # 查看表结构
SELECT * FROM users;   # 查询数据
\q                     # 退出
```

### 自动备份（推荐）

```bash
crontab -e
```

添加每日备份任务：

```
0 2 * * * cd /home/ubuntu/eyangpet/eyangpet-deployment && ./deploy.sh db-backup
```

---

## 日常运维

### 查看服务状态

```bash
./deploy.sh status

# 或者直接使用 docker
docker compose ps
docker stats
```

### 查看日志

```bash
# 所有服务
./deploy.sh logs

# 指定服务
./deploy.sh logs backend
./deploy.sh logs nginx
./deploy.sh logs postgres

# 只看最近 50 行
docker compose logs --tail=50 backend
```

### 重启服务

```bash
# 重启所有
./deploy.sh restart

# 只重启某个服务
docker compose restart backend
docker compose restart nginx
```

### 进入容器

```bash
# 进入后端容器
docker exec -it eyangpet-backend sh

# 进入 nginx 容器
docker exec -it eyangpet-nginx sh

# 进入数据库容器
docker exec -it eyangpet-db bash
```

---

## 故障排查

### 服务无法启动

```bash
# 查看详细日志
docker compose logs -f

# 检查端口占用
sudo netstat -tlnp | grep -E '80|443|9909|5432'

# 检查 docker 状态
sudo systemctl status docker
```

### 数据库连接失败

```bash
# 检查数据库容器状态
docker compose logs postgres

# 测试数据库连接
docker exec -it eyangpet-db psql -U postgres -d eyangpet -c "SELECT 1"
```

### 后端启动失败

```bash
# 查看后端日志
docker compose logs backend

# 常见问题：
# - 数据库未就绪：等待 postgres 容器启动
# - 配置错误：检查环境变量
# - 端口冲突：检查 9909 端口
```

### Nginx 配置错误

```bash
# 测试配置语法
docker exec eyangpet-nginx nginx -t

# 重载配置
docker exec eyangpet-nginx nginx -s reload

# 查看 nginx 日志
docker compose logs nginx
```

### SSL 证书问题

```bash
# 查看证书状态
docker compose run --rm certbot certificates

# 测试续期（不实际执行）
docker compose run --rm certbot renew --dry-run

# 检查 certbot 日志
docker compose logs certbot
```

### 前端页面 404

```bash
# 检查 dist 目录是否存在
ls -la ../eyangpet-frontend/dist/

# 检查 nginx 是否正确挂载
docker exec eyangpet-nginx ls -la /usr/share/nginx/html/

# 重新构建前端
cd ../eyangpet-frontend
npm run build
docker compose restart nginx
```

---

## 安全建议

### 1. 服务器安全

```bash
# 配置防火墙（只开放必要端口）
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable

# 禁用 root 远程登录
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### 2. 数据库安全

- 使用强密码（至少 16 字符，包含大小写字母、数字、特殊字符）
- 数据库不暴露到公网（只在 Docker 内网通信）
- 定期备份数据库

### 3. 应用安全

- JWT 密钥使用随机生成的长字符串
- 生产环境关闭 debug 模式
- 定期更新依赖包

### 4. 定期维护

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 清理 Docker 无用资源
docker system prune -a

# 检查磁盘空间
df -h
```

---

## 常见问题

### Q: 国内服务器 Docker 镜像拉取慢？

配置镜像加速器，参考 [快速部署 - 第一步](#第一步安装-docker)。

### Q: 前端构建报错 vue-tsc？

Node.js 22 与 vue-tsc 有兼容性问题，已修复。`npm run build` 现在直接使用 vite 构建。

### Q: 如何查看实时日志？

```bash
./deploy.sh logs  # 实时跟踪所有日志
# 按 Ctrl+C 退出
```

### Q: 如何回滚到之前的版本？

```bash
cd ../eyangpet-backend
git log --oneline  # 查看提交历史
git checkout <commit-hash>  # 切换到指定版本
cd ../eyangpet-deployment
./deploy.sh update-backend  # 重新构建
```

---

## License

MIT
