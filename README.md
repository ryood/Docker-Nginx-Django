# Docker + Nginx(HTTPS) + Django + SQLite

- [HTTPでテスト](#HTTP)
- [HTTPS化](#HTTPS)
- [証明書を自動更新](#RENEW)

<a id="HTTP"></a>
# HTTPでテスト

### サーバー起動
AWS EC2やVPSなどパブリックIPアドレス必須

### DNS設定
AWS Route53などDNSサーバでAレコードでホスト名とIPアドレスを紐づける

### DNS確認
```
dig <ホスト名>
```
または
```
nslookup <ホスト名>
```

### Dockerインストール
[Dockerをインストールする手順](https://github.com/ryood/Docker-Install) 参照　　

一般ユーザーでDockerが起動できることを確認
```
docker --version
docker compose version
```
OSを再起動 (一般ユーザーでDockerが起動しない場合)
```
reboot now
```

## リポジトリをClone
```
git clone https://github.com/ryood/Docker-Nginx-Django.git pnpn
```

## 環境ファイルを作成
```
cd pnpn
vi .env.http
```
```
# SECRET_KEYについては本番環境では推測されない値に変更しておきましょう
SECRET_KEY=SECRET_KEY_FOR_HTTP
# ALLOWED_HOSTS=localhost 127.0.0.1 [::1]
ALLOWED_HOSTS=*
# HTTPでのテストのためTrue
DEBUG=True
```

## コンテナでDjangoのプロジェクトを作成
```
docker compose -f docker-compose-http.yml run app django-admin startproject djangopj .
```

## 所有権変更
```
sudo chown -R $USER:$USER djangopj manage.py
```

## Djangoの設定ファイルを編集
examplesからsettings.pyをコピー
```
cp examples/settings.py djangopj/settings.py
```
または直接編集
```
vi djangopj/settings.py
```
```
from pathlib import Path
# osのモジュールをインポート
import os

# [・・・]

# SECRET_KEYを.envから取得
SECRET_KEY = os.environ.get("SECRET_KEY")

# DEBUGを.envから取得
# envファイルにTrue、Falseと書くとDjangoがString型と認識してしまいます
# os.environ.get("DEBUG") == "True"を満たすとboolean型のTrueになり、
# env内のDEBUGがTrue以外ならFalseになります
DEBUG = os.environ.get("DEBUG") == "True"

# ALLOWED_HOSTSを.envから取得
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS").split(" ")

# [・・・]

# 言語を日本語に設定
LANGUAGE_CODE = "ja"
# タイムゾーンをAsia/Tokyoに設定
TIME_ZONE = "Asia/Tokyo"

# [・・・]

# STATIC_ROOTを設定
# Djangoの管理者画面にHTML、CSS、Javascriptが適用されます
STATIC_ROOT = "/static/"
STATIC_URL = "/static/"
```

## コンテナ起動
```
docker compose -f docker-compose-http.yml up -d
```
## HTTPアクセスでブラウザから確認
```
http://<ip-address>/
```
## スーパーユーザー作成
```
docker ps
docker exec -it <container-id> /bin/bash
python manage.py createsuperuser
```

<a id="HTTPS"></a>
# HTTPS化
## Dockerコンテナが立ち上がっていたらDown
```
docker ps
docker compose -f docker-compose-http.yml down
```

## ドメイン名を設定
「www2.pnpn.mfg.com」を置換
```
vi docker/nginx/nginx.conf
```

## Nginxのみ起動
```
docker compose -f docker-compose-cert.yml up -d nginx
```
## Certbotで認証取得
[!IMPORTANT]
※-d オプションでドメイン名を指定
```
docker compose -f docker-compose-cert.yml run --rm certbot certonly --webroot -w /var/www/html -d www2.pnpn-mfg.com
```

## Nginxを停止
```
docker compose -f docker-compose-cert.yml down
```
## .envファイルを編集
```
# SECRET_KEYについては本番環境では推測されない値に変更しておきましょう
SECRET_KEY=SECRET_KEY_Test
# ALLOWED_HOSTS=localhost 127.0.0.1 [::1]
ALLOWED_HOSTS=*
# テスト環境のためFalse
DEBUG=False
```

## HTTPS対応でコンテナを起動
### 本番用にdocker-compose.ymlにシンボリックを貼る
```
ln -s docker-compose-https.yml docker-compose.yml
```
コンテナを起動
```
docker compose up -d
```
## CSRFエラーの場合
settings.py
[!IMPORTANT]
ホスト名を修正
```
CSRF_TRUSTED_ORIGINS = [
    "https://www2.pnpn-mfg.com",
]
```
```
docker compose down && docker compose up -d
```

<a id="RENEW"></a>
# 証明書を自動更新

## 実行スクリプトを編集
cat renew_ssl_certificate.sh  
[!important] 実行ディレクトリを編集
```
#!/bin/bash
cd /home/ec2-user/pnpn/
docker compose run --rm certbot renew --dry-run
docker compose exec -T nginx nginx -t && \
docker compose exec -T nginx nginx -s reload
```
## 実行権を付与
```
chmod +x renew_ssl_certificate.sh
```
## serviceを編集
```
sudo vi /etc/systemd/system/certbot-renew.service
```
[!important] 実行ディレクトリを編集
```
[Unit]
Description=Renew Let's Encrypt certificates using certbot in Docker

[Service]
Type=oneshot
ExecStart=/home/ec2-user/pnpn/renew_ssl_certificate.sh
```
## timerを編集
```
sudo vi /etc/systemd/system/certbot-renew.timer
```
```
[Unit]
Description=Timer to renew Let's Encrypt certificates on 1st and 15th of each month

[Timer]
# OnCalendar=*-*-* *:00/10:00
OnCalendar=*-*-01 00:00:00
OnCalendar=*-*-15 00:00:00
Persistent=true

[Install]
WantedBy=timers.target
```
## 有効化＆起動
```
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

sudo systemctl enable --now certbot-renew.timer
```
## 確認
```
systemctl list-timers | grep certbot-renew
```
## ログ確認
```
journalctl -u certbot-renew.service --no-pager -n 50
```
## 変更したら
```
sudo systemctl daemon-reload
sudo systemctl enable --now certbot-renew.timer
```
