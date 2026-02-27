# Let's Encrypt SSL 证书自动续期指南

使用 Docker + Nginx + Certbot 配置免费 HTTPS 证书，包括首次申请和自动续期。

## 目录

- [工作原理](#工作原理)
- [目录结构](#目录结构)
- [Docker Compose 配置](#docker-compose-配置)
- [Nginx 配置](#nginx-配置)
- [首次申请证书](#首次申请证书)
- [启用 HTTPS](#启用-https)
- [配置自动续期](#配置自动续期)
- [常用命令](#常用命令)
- [故障排查](#故障排查)

---

## 工作原理

### Let's Encrypt 验证流程

Let's Encrypt 使用 ACME 协议验证你对域名的所有权：

```
1. Certbot 向 Let's Encrypt 发起证书申请
2. Let's Encrypt 返回一个验证 token
3. Certbot 将 token 放在 /.well-known/acme-challenge/ 目录
4. Let's Encrypt 通过 HTTP 访问该 token
5. 验证成功后颁发证书（有效期 90 天）
```

### 架构示意图

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Certbot   │────▶│    Nginx    │◀────│Let's Encrypt│
│  (申请证书)  │     │ (提供验证文件)│     │  (验证域名)  │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       ▼                   ▼
┌─────────────────────────────────────┐
│            共享 Volume              │
│  ./certbot/www  ← 验证文件          │
│  ./certbot/conf ← 证书存储          │
└─────────────────────────────────────┘
```

---

## 目录结构

```
your-project/
├── docker-compose.yml
├── nginx/
│   └── conf.d/
│       ├── default.conf          # 当前使用的配置
│       ├── default.conf.http     # HTTP 配置（申请证书用）
│       └── default.conf.ssl      # HTTPS 配置（正式使用）
└── certbot/
    ├── www/                      # ACME 验证文件目录
    └── conf/                     # 证书存储目录
        └── live/
            └── your-domain.com/
                ├── fullchain.pem # 完整证书链
                └── privkey.pem   # 私钥
```

---

## Docker Compose 配置

```yaml
# docker-compose.yml
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certbot/www:/var/www/certbot:ro
      - ./certbot/conf:/etc/letsencrypt:ro

  certbot:
    image: certbot/certbot
    container_name: certbot
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
```

**关键点：**
- Nginx 和 Certbot 共享 `certbot/www` 目录（验证文件）
- Nginx 和 Certbot 共享 `certbot/conf` 目录（证书文件）
- Nginx 挂载为只读 `:ro`，Certbot 需要写入权限

---

## Nginx 配置

### HTTP 配置（用于申请证书）

```nginx
# nginx/conf.d/default.conf.http
server {
    listen 80;
    server_name your-domain.com;

    # Let's Encrypt 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 其他请求（可选：返回提示或你的应用）
    location / {
        return 200 'SSL certificate pending...';
        add_header Content-Type text/plain;
    }
}
```

### HTTPS 配置（证书申请成功后使用）

```nginx
# nginx/conf.d/default.conf.ssl
# HTTP -> HTTPS 重定向
server {
    listen 80;
    server_name your-domain.com;

    # Let's Encrypt 验证（续期需要）
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 重定向到 HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS 配置
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # SSL 证书
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    # SSL 安全配置
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # 现代 SSL 配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS（可选，建议启用）
    add_header Strict-Transport-Security "max-age=63072000" always;

    # 你的应用配置
    location / {
        # 代理到后端或返回静态文件
        root /usr/share/nginx/html;
        index index.html;
    }
}
```

---

## 首次申请证书

### 前提条件

1. **域名已解析到服务器 IP**
   ```bash
   nslookup your-domain.com
   # 应返回你服务器的 IP
   ```

2. **80 端口可访问**
   ```bash
   # 检查防火墙
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

### 步骤 1：准备目录

```bash
mkdir -p nginx/conf.d certbot/www certbot/conf
```

### 步骤 2：创建 HTTP 配置

```bash
cat > nginx/conf.d/default.conf << 'EOF'
server {
    listen 80;
    server_name your-domain.com;  # 替换为你的域名

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'SSL certificate pending...';
        add_header Content-Type text/plain;
    }
}
EOF
```

### 步骤 3：启动 Nginx

```bash
docker compose up -d nginx
```

### 步骤 4：验证 HTTP 可访问

```bash
curl http://your-domain.com
# 应返回 "SSL certificate pending..."
```

### 步骤 5：申请证书

```bash
docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email your-email@example.com \
    --agree-tos \
    --no-eff-email \
    -d your-domain.com
```

**参数说明：**
- `--webroot` - 使用 webroot 验证方式
- `--webroot-path` - 验证文件存放路径（对应 Nginx 的 `/var/www/certbot`）
- `--email` - 接收证书过期提醒
- `--agree-tos` - 同意服务条款
- `--no-eff-email` - 不接收 EFF 邮件
- `-d` - 域名（可指定多个）

**成功输出：**
```
Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/your-domain.com/fullchain.pem
Key is saved at: /etc/letsencrypt/live/your-domain.com/privkey.pem
```

### 步骤 6：验证证书

```bash
ls certbot/conf/live/your-domain.com/
# 应该看到: fullchain.pem  privkey.pem  cert.pem  chain.pem
```

---

## 启用 HTTPS

### 步骤 1：创建 HTTPS 配置

```bash
cat > nginx/conf.d/default.conf << 'EOF'
server {
    listen 80;
    server_name your-domain.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
}
EOF
```

### 步骤 2：重启 Nginx

```bash
docker compose restart nginx
```

### 步骤 3：验证 HTTPS

```bash
curl -I https://your-domain.com
# 应返回 HTTP/2 200

# 查看证书有效期
echo | openssl s_client -servername your-domain.com -connect your-domain.com:443 2>/dev/null | openssl x509 -noout -dates
```

---

## 配置自动续期

Let's Encrypt 证书有效期 90 天，建议配置自动续期。

### 方法 1：Crontab（推荐）

```bash
# 编辑 crontab
crontab -e

# 添加以下行（每天凌晨 3 点检查续期）
0 3 * * * cd /path/to/your-project && docker compose run --rm certbot renew --quiet && docker compose exec nginx nginx -s reload
```

**说明：**
- `certbot renew` - 检查所有证书，到期前 30 天内自动续期
- `--quiet` - 静默模式，只在出错时输出
- `nginx -s reload` - 重载配置使新证书生效

### 方法 2：Systemd Timer

```bash
# 创建服务
sudo tee /etc/systemd/system/certbot-renew.service << 'EOF'
[Unit]
Description=Certbot Renewal

[Service]
Type=oneshot
WorkingDirectory=/path/to/your-project
ExecStart=/usr/bin/docker compose run --rm certbot renew --quiet
ExecStartPost=/usr/bin/docker compose exec nginx nginx -s reload
EOF

# 创建定时器
sudo tee /etc/systemd/system/certbot-renew.timer << 'EOF'
[Unit]
Description=Run Certbot Renewal Daily

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

# 启用
sudo systemctl daemon-reload
sudo systemctl enable certbot-renew.timer
sudo systemctl start certbot-renew.timer

# 查看状态
sudo systemctl list-timers | grep certbot
```

### 方法 3：Docker Compose 内置续期

在 `docker-compose.yml` 中让 certbot 容器持续运行并自动续期：

```yaml
certbot:
  image: certbot/certbot
  volumes:
    - ./certbot/www:/var/www/certbot
    - ./certbot/conf:/etc/letsencrypt
  entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
```

然后配置 Nginx 定期重载：

```bash
# crontab
0 */12 * * * docker compose exec nginx nginx -s reload
```

---

## 常用命令

### 查看证书状态

```bash
docker compose run --rm certbot certificates
```

### 手动续期

```bash
docker compose run --rm certbot renew
docker compose exec nginx nginx -s reload
```

### 测试续期（不实际执行）

```bash
docker compose run --rm certbot renew --dry-run
```

### 强制续期

```bash
docker compose run --rm certbot renew --force-renewal
docker compose exec nginx nginx -s reload
```

### 删除证书

```bash
docker compose run --rm certbot delete --cert-name your-domain.com
```

### 申请多域名证书

```bash
docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email your-email@example.com \
    --agree-tos \
    --no-eff-email \
    -d example.com \
    -d www.example.com \
    -d api.example.com
```

---

## 故障排查

### 问题 1：验证失败

**错误：** `Challenge failed for domain`

**检查清单：**
```bash
# 1. 域名是否解析到服务器
nslookup your-domain.com

# 2. 80 端口是否可访问
curl -I http://your-domain.com

# 3. 验证路径是否正确
curl http://your-domain.com/.well-known/acme-challenge/test

# 4. Nginx 是否正确配置
docker compose exec nginx nginx -t
docker compose logs nginx
```

### 问题 2：权限错误

**错误：** `Permission denied`

```bash
# 修复权限
sudo chown -R $USER:$USER certbot/
sudo chmod -R 755 certbot/
```

### 问题 3：Rate Limit

**错误：** `too many certificates already issued`

Let's Encrypt 限制：
- 每个域名每周最多 5 次证书申请
- 等待一周后重试
- 测试时使用 `--staging` 参数

```bash
docker compose run --rm certbot certonly \
    --staging \
    --webroot \
    --webroot-path=/var/www/certbot \
    -d your-domain.com
```

### 问题 4：证书路径不存在

**错误：** `nginx: [emerg] cannot load certificate`

```bash
# 检查证书是否存在
ls -la certbot/conf/live/

# 重新申请
docker compose run --rm certbot certonly ...
```

### 问题 5：续期后 Nginx 未更新

确保续期后重载 Nginx：

```bash
docker compose exec nginx nginx -s reload
```

---

## 最佳实践

1. **始终保留 HTTP 验证路径** - HTTPS 配置中也要包含 `/.well-known/acme-challenge/`，否则续期会失败

2. **使用 cron 或 systemd 自动续期** - 不要依赖手动续期

3. **监控证书到期** - Let's Encrypt 会发送邮件提醒，确保邮箱正确

4. **测试用 staging** - 开发测试时使用 `--staging` 避免触发 rate limit

5. **备份证书目录** - `certbot/conf` 包含私钥，定期备份

---

## 参考资料

- [Let's Encrypt 官方文档](https://letsencrypt.org/docs/)
- [Certbot 官方文档](https://certbot.eff.org/docs/)
- [Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [ACME 协议](https://tools.ietf.org/html/rfc8555)
