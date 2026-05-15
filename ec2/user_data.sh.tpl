#!/bin/bash
# Bootstrap script for chapagain/nodejs-mysql-crud on Ubuntu 24.04
set -euo pipefail
exec > /var/log/user_data.log 2>&1

export DEBIAN_FRONTEND=noninteractive

# ── Phase 1: Install all packages ────────────────────────────────────────────
echo "==> Updating package index"
apt-get update -y

echo "==> Installing Node.js 20 LTS"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

echo "==> Installing all required packages"
apt-get install -y nodejs git mysql-server nginx certbot python3-certbot-dns-cloudflare

# ── Phase 2: Configure MySQL ──────────────────────────────────────────────────
echo "==> Starting MySQL"
systemctl start mysql
systemctl enable mysql

echo "==> Waiting for MySQL to be ready"
until mysqladmin ping --silent; do
  sleep 2
done

echo "==> Configuring MySQL"
mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${db_password}';
CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${db_password}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ── Phase 3: Obtain SSL certificate ──────────────────────────────────────────
echo "==> Writing Cloudflare credentials for Certbot"
mkdir -p /root/.secrets/certbot
cat > /root/.secrets/certbot/cloudflare.ini <<'CFINI'
dns_cloudflare_api_token = ${cloudflare_api_token}
CFINI
chmod 600 /root/.secrets/certbot/cloudflare.ini

echo "==> Obtaining Let's Encrypt certificate for ${domain_name}"
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60 \
  --non-interactive \
  --agree-tos \
  --email "${certbot_email}" \
  -d "${domain_name}"

# ── Phase 4: Deploy application ───────────────────────────────────────────────
echo "==> Installing PM2 process manager"
npm install -g pm2
PM2=$(which pm2)

echo "==> Cloning nodejs-mysql-crud application"
git clone https://github.com/chapagain/nodejs-mysql-crud.git /home/ubuntu/nodejs-mysql-crud
cd /home/ubuntu/nodejs-mysql-crud

echo "==> Installing application dependencies"
npm install

echo "==> Writing database configuration"
cat > config.js <<'DBCONFIG'
var config = {
  database: {
    host:     'localhost',
    user:     '${db_user}',
    password: '${db_password}',
    port:     3306,
    db:       '${db_name}'
  },
  server: {
    host: '127.0.0.1',
    port: '3000'
  }
};
module.exports = config;
DBCONFIG

echo "==> Creating database schema"
mysql -u "${db_user}" -p"${db_password}" "${db_name}" <<'SQL'
CREATE TABLE IF NOT EXISTS users (
  id int(11) NOT NULL auto_increment,
  name varchar(100) NOT NULL,
  age int(3) NOT NULL,
  email varchar(100) NOT NULL,
  PRIMARY KEY (id)
);
SQL

echo "==> Starting application with PM2"
chown -R ubuntu:ubuntu /home/ubuntu/nodejs-mysql-crud
# Brief pause to ensure MySQL user grants are fully committed before app connects
sleep 5
sudo -u ubuntu env HOME=/home/ubuntu PATH="$PATH" "$PM2" start /home/ubuntu/nodejs-mysql-crud/app.js --name nodejs-crud
sudo -u ubuntu env HOME=/home/ubuntu PATH="$PATH" "$PM2" save --force
"$PM2" startup systemd -u ubuntu --hp /home/ubuntu

# ── Phase 5: Configure Nginx ──────────────────────────────────────────────────
echo "==> Configuring Nginx"
cat > /etc/nginx/sites-available/nodejs-crud <<'NGINXCONF'
server {
    listen 80;
    server_name ${domain_name};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name ${domain_name};

    ssl_certificate     /etc/letsencrypt/live/${domain_name}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain_name}/privkey.pem;

    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_ciphers               ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache         shared:SSL:10m;
    ssl_session_timeout       1d;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade     $http_upgrade;
        proxy_set_header   Connection  'upgrade';
        proxy_set_header   Host        $host;
        proxy_set_header   X-Real-IP   $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/nodejs-crud /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
systemctl enable nginx

# ── Phase 6: Certificate auto-renewal ────────────────────────────────────────
echo "==> Setting up Certbot auto-renewal"
echo "0 0,12 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'" > /etc/cron.d/certbot-renew

echo "==> Bootstrap complete. App live at https://${domain_name}"
