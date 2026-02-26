# E养宠 服务器部署指南

## 部署架构

```
                    ┌─────────────┐
                    │   用户访问   │
                    │ your-domain │
                    └──────┬──────┘
                           │
                           ▼ 80/443
                    ┌─────────────┐
                    │    Nginx    │
                    │  反向代理    │
                    │  静态文件    │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
       ┌─────────────┐          ┌─────────────┐
       │  前端静态   │          │   后端API   │
       │   /dist     │          │    :9909    │
       └─────────────┘          └──────┬──────┘
                                       │
                                       ▼
                                ┌─────────────┐
                                │ PostgreSQL  │
                                │    :5432    │
                                └─────────────┘
```

## 前提条件

1. **域名已备案**（国内服务器必须）
2. **域名已解析**到服务器 IP
3. **服务器开放端口**：80、443

---

## 部署步骤

### 1. 服务器环境准备

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y  # Ubuntu/Debian
# 或
sudo yum update -y  # CentOS

# 安装 Docker
curl -fsSL https://get.docker.com | sh
sudo systemctl enable docker
sudo systemctl start docker

# 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 验证安装
docker --version
docker-compose --version

# 安装 Git (如果需要)
sudo apt install git -y  # Ubuntu/Debian
# 或
sudo yum install git -y  # CentOS
```

### 2. 上传代码到服务器

**方式一：Git 克隆**
```bash
cd /opt
git clone your-repo-url eyangpet
cd eyangpet
```

**方式二：SCP 上传**
```bash
# 本地执行
scp -r ./eyangpet-project root@your-server-ip:/opt/eyangpet
```

### 3. 配置环境变量

```bash
cd /opt/eyangpet

# 复制环境变量模板
cp .env.example .env

# 编辑配置
vim .env
```

**.env 配置说明：**

```bash
# 数据库密码（设置一个强密码）
DB_PASSWORD=YourStrongPassword123!

# JWT 密钥（至少32字符的随机字符串）
JWT_SECRET=your-32-character-random-string-here

# 你的域名
DOMAIN=api.example.com
EMAIL=admin@example.com
CORS_ORIGINS=https://example.com
```

### 4. 修改 Nginx 配置中的域名

```bash
# 编辑 Nginx 配置，将 your-domain.com 替换为你的域名
vim nginx/conf.d/default.conf
vim nginx/conf.d/default.conf.ssl
```

### 5. 初始化并构建

```bash
# 添加执行权限
chmod +x deploy.sh

# 初始化
./deploy.sh init

# 构建镜像
./deploy.sh build
```

### 6. 启动服务

```bash
./deploy.sh start

# 查看服务状态
docker-compose ps

# 查看日志
./deploy.sh logs
```

### 7. 申请 SSL 证书

```bash
# 确保域名已解析到服务器，且80端口可访问
# 申请证书
./deploy.sh ssl-init

# 启用 HTTPS 配置
cd nginx/conf.d
mv default.conf default.conf.http
mv default.conf.ssl default.conf

# 重启 Nginx
docker-compose restart nginx
```

---

## 常用命令

```bash
# 查看所有容器状态
docker-compose ps

# 查看日志
./deploy.sh logs              # 所有服务
./deploy.sh logs backend      # 只看后端
./deploy.sh logs nginx        # 只看 Nginx

# 重启服务
./deploy.sh restart

# 停止服务
./deploy.sh stop

# 重新构建并启动
./deploy.sh build
./deploy.sh start

# 进入容器
docker exec -it eyangpet-backend sh
docker exec -it eyangpet-db psql -U postgres -d eyangpet

# 证书续期（建议设置定时任务）
./deploy.sh ssl-renew
```

---

## 设置定时任务（证书自动续期）

```bash
# 编辑 crontab
crontab -e

# 添加以下行（每月1号凌晨3点续期证书）
0 3 1 * * cd /opt/eyangpet && ./deploy.sh ssl-renew >> /var/log/certbot-renew.log 2>&1
```

---

## 更新部署

当代码更新后：

```bash
cd /opt/eyangpet

# 拉取最新代码
git pull

# 重新构建前端
cd eyangpet-frontend
npm install
npm run build
cd ..

# 重新构建后端镜像
docker-compose build backend

# 重启服务
./deploy.sh restart
```

---

## 数据库备份

```bash
# 手动备份
docker exec eyangpet-db pg_dump -U postgres eyangpet > backup_$(date +%Y%m%d).sql

# 恢复备份
docker exec -i eyangpet-db psql -U postgres eyangpet < backup_20240101.sql
```

---

## 故障排查

### 1. 服务无法启动

```bash
# 查看详细日志
docker-compose logs -f

# 检查端口占用
netstat -tlnp | grep -E '80|443|9909|5432'
```

### 2. 数据库连接失败

```bash
# 检查数据库容器
docker-compose logs postgres

# 进入数据库容器测试
docker exec -it eyangpet-db psql -U postgres -d eyangpet
```

### 3. SSL 证书问题

```bash
# 查看证书状态
docker compose run --rm certbot certificates

# 测试证书续期（不实际执行）
docker compose run --rm certbot renew --dry-run
```

### 4. Nginx 配置错误

```bash
# 测试配置
docker exec eyangpet-nginx nginx -t

# 重载配置
docker exec eyangpet-nginx nginx -s reload
```

---

## 安全建议

1. **防火墙**：只开放必要端口（80、443、SSH）
2. **SSH**：禁用密码登录，使用密钥认证
3. **数据库**：使用强密码，不要暴露到公网
4. **定期备份**：设置自动备份脚本
5. **监控**：设置服务监控和告警
