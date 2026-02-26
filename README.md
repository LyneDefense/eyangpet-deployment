# E养宠 部署仓库 - eyangpet-deployment

专门用于部署 E养宠 项目的配置和脚本。

## 仓库结构

```
eyangpet-deployment/
├── deploy.sh            # 一键部署脚本
├── docker-compose.yml   # Docker 编排配置
├── .env.example         # 环境变量模板
├── nginx/
│   └── conf.d/
│       ├── default.conf      # Nginx 配置 (HTTP)
│       └── default.conf.ssl  # Nginx 配置 (HTTPS)
├── DEPLOYMENT.md        # 详细部署文档
└── README.md            # 本文件
```

## 相关仓库

- **后端**: [eyangpet-backend](https://github.com/你的用户名/eyangpet-backend)
- **前端**: [eyangpet-frontend](https://github.com/你的用户名/eyangpet-frontend)

## 快速开始

### 1. 服务器环境准备

```bash
# 安装 Docker
curl -fsSL https://get.docker.com | sh
sudo systemctl enable docker && sudo systemctl start docker
```

### 2. 克隆部署仓库

```bash
mkdir -p /home/ubuntu/eyangpet
cd /home/ubuntu/eyangpet
git clone https://github.com/你的用户名/eyangpet-deployment.git .
```

### 3. 配置环境变量

```bash
cp .env.example .env
vim .env  # 修改配置
```

需要配置：
- `GIT_BACKEND_URL` - 后端仓库地址
- `GIT_FRONTEND_URL` - 前端仓库地址
- `DB_PASSWORD` - 数据库密码
- `JWT_SECRET` - JWT 密钥
- `DOMAIN` - 你的域名
- `EMAIL` - 申请证书用的邮箱

### 4. 修改 Nginx 配置中的域名

```bash
# 把 your-domain.com 替换为你的实际域名
sed -i "s/your-domain.com/你的域名/g" nginx/conf.d/default.conf
sed -i "s/your-domain.com/你的域名/g" nginx/conf.d/default.conf.ssl
```

### 5. 克隆前后端代码

```bash
./deploy.sh clone
```

### 6. 构建并启动

```bash
./deploy.sh build
./deploy.sh start
```

### 7. 申请 SSL 证书

```bash
./deploy.sh ssl-init

# 启用 HTTPS
mv nginx/conf.d/default.conf nginx/conf.d/default.conf.http
mv nginx/conf.d/default.conf.ssl nginx/conf.d/default.conf
docker compose restart nginx
```

## 常用命令

```bash
./deploy.sh              # 查看所有命令

# 代码更新
./deploy.sh update          # 一键更新（拉取 + 构建 + 重启）
./deploy.sh update-backend  # 只更新后端
./deploy.sh update-frontend # 只更新前端
./deploy.sh status          # 查看状态

# 服务管理
./deploy.sh start           # 启动
./deploy.sh stop            # 停止
./deploy.sh restart         # 重启
./deploy.sh logs            # 查看日志
./deploy.sh logs backend    # 只看后端日志

# 数据库
./deploy.sh db-backup       # 备份数据库
```

## 服务器目录结构

部署后的目录结构：

```
/home/ubuntu/eyangpet/
├── deploy.sh
├── docker-compose.yml
├── .env                     # 环境变量（不上传到 Git）
├── nginx/
├── certbot/                 # SSL 证书（自动生成）
├── eyangpet-backend/        # 后端仓库
└── eyangpet-frontend/       # 前端仓库
```

## 详细文档

查看 [DEPLOYMENT.md](./DEPLOYMENT.md) 获取更详细的部署说明。
