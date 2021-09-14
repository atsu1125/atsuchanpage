# 最初に：
VPSと自宅鯖をVPNでつなぐっていうのは以前の記事を参照してください  
https://qiita.com/atsu1125/items/16198a5b813ba5e0be80  
おそらくこの方法でなくてもVPS側から自宅鯖へローカルIPでアクセスできればOKです  
環境としてはVPSがCentOS Stream 8でNginxをリバースプロキシとして運用、  
Softether VPNサーバーが動いていてそこと自宅サーバーを常時VPN接続しています、  
自宅鯖は現状docker環境ですので、VPNさえつながればOSなんでもいい  


# VPSから自宅鯖へトラフィックを転送：
VPS側のNginxの設定  
httpディレクティブにリバースプロキシの設定書いてやる  
sites-availableとかのフォルダに設定ファイル書く  
examle.comを各自の公開したいURLに変更してね  
client_max_body_sizeはWebサーバーに一度にアップロードできる最大容量ということになるのですが  
これはあくまでVPSのNginxへのアップロードサイズの指定なので基本かなり多めに確保しておいてよい  
自宅鯖のNextCloudの方でアップロードサイズの制限はできると思うしおすし  

```php:nextcloud.conf
    server {
    server_name examle.com; # managed by Certbot

        location / {
            proxy_pass http://192.168.40.101:8080;
            proxy_set_header X-Real-IP $remote_addr;
            index index.html index.htm;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
            proxy_redirect off;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_cache_bypass $http_upgrade;
        }

    listen [::]:443 ssl; # managed by Certbot
    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/examle.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/examle.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
    client_max_body_size 16G;
}

    server {
    if ($host = examle.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


        listen       80 ;
        listen       [::]:80 ;
    server_name example.com;
    return 404; # managed by Certbot


}

```
VPS側のNginxの設定はこれだけです、簡単でしょ  
あとは各自でSSL証明書をインストールしてあげてね  
Let's encryptで自動更新組むとかCloudflareの自己証明書いれるとかある  
うちはLet's encryptを入れてるけどCloudflareも使ってる  
Cloudflareの方でSSL暗号化をフルにしておけば特に問題なし  

```
sudo nginx -t
sudo systemctl reload nginx
```
でNginxに設定ファイルを読み込ませてやってね  

# 自宅鯖：NextCloudのインストール：
dockerとdocker-composeが使えるようにしておいてください  
そしたらnextcloudのデータを入れるフォルダを作ってやって  
docker-compose.ymlを書きます  
userとpasswordとexample.comは各自で値を変更されるとよろし  
んでこのOVERWRITEPROTOCOLを書かないとNextCloudのUIでページ推移するとアクセスができなくなる  
なんでかというとあくまで私たちがアクセスしてるのはVPS上のNginxなので、先程の設定で常時https化している  
しかしこのNextCloudが動いてるApacheにはproxy_passで設定した通りhttpでアクセスしているよね  
だからApacheさんはページ推移でhttp://のURLを与えてくる  
でも私たちは本来はhttps://でアクセスしてるはず、だからエラーになる  
のでしっかりと設定してね  
あとはDBがPostgreSQL使ってるけど他のものでも設定できれば大丈夫よ  

```docker-compose.yml
version: '3.2'

services:
  db:
    image: postgres
    restart: always
    volumes:
      - ./db:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password

  app:
    image: nextcloud
    restart: always
    ports:
      - 8080:80
    depends_on:
      - db
    volumes:
      - ./nextcloud:/var/www/html
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=user
      - POSTGRES_HOST=db
      - NEXTCLOUD_ADMIN_PASSWORD=password
      - NEXTCLOUD_ADMIN_USER=root
      - NEXTCLOUD_TRUSTED_DOMAINS=examle.com
      - OVERWRITEPROTOCOL=https
```

そしたらそのフォルダで  

```
docker-compose up -d
```
でnextcloudを起動してやる、まだ不十分なとこあるけど、これでとりあえず動くはず  
VPN接続がVPSと自宅鯖でつながっていて、nginxでリバースプロキシの設定ができていれば  
ブラウザでURL入れれば、あとは上で入力したadmin user, admin passを入れればログインできると思う  

そしてもう一つ設定したいこと  
それが最大アップロードサイズの指定で  
隠しファイルになってるからちょっと大変かもだけど  
今dockerでインストールしたNextcloudのディレクトリでnextcloudフォルダに入って  
.htaccessっていうファイルを探してほしい、そしたらこれを開いて  
最後の行にこれを追記して欲しい  

```php:.htaccess
php_value upload_max_filesize 16G
php_value post_max_size 16G
```

ここの16Gってのがアップロードできる最大サイズになるので  
ここをお好みの値にしてもらえればいいと思う  
設定できたら  

```
docker-compose down && docker-compose up -d
```

で再起動してあげると  
設定が反映されたはず、NextCloudのWebUIの管理画面からアップロード可能サイズを確認できると思う  
これで完成だとおもうわよ  

# 留意点：
これ自宅でローカルIPとポート番号指定してアクセスしようとするとOVERWRITEPROTOCOL=httpsのせいでSSLの警告が出ちゃうんよね  
自己証明書だからっていうことなんだけど、httpでアクセスしてもその設定のせいでページ推移の度にhttpsになってしまう  
基本は自宅でも正式なURL指定してhttpsでアクセスするのがよさそうだねえ  
どっちみちアプリからだと正式なURL指定しないとアクセスできないし  
