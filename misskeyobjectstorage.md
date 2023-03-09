# 環境
うちは複数台のサーバーでMisskeyのアプリケーションを実行しています。

通常１台のサーバーだと思いますのでそれ向けの内容で書きます。

複数台で運用される方はちょっと工夫してみてください。

OS：Fedora 36, Debian bullseye, Ubuntu 22.04

ソフトウェア：以下のバージョンをサポートします、それ以前だと動かない可能性

（特にAreionskeyはわいのフォークじゃないとちょっとバグあり）

Misskey v10系→めいすきー 10.102.586-m544

https://github.com/mei23/misskey/releases/tag/10.102.586-m544

Misskey v11系→Areionskey 1.4.0-atsuchan-b2

https://github.com/atsu1125/misskey-v11/releases/tag/1.4.0-atsuchan-b2

Misskey v12系→Misskey 12.117.1

https://github.com/misskey-dev/misskey/releases/tag/12.117.1


オブジェクトストレージのURLをそのまま公開することはせず、

MisskeyをホストしているNginxでリバースプロキシを行います。

そうしないとリージョンが遠くて単純に不利だし、転送量課金なのでなるべくキャッシュして帯域利用量を減らすべきなのです。

Misskeyの設定でオブジェクトストレージを使用するようにすると、

オブジェクトストレージ移行前にアップロードされたファイルは`https://misskeyのドメイン/files`を読み、

移行後にアップロードされたファイルはhttps://`baseUrl`/`prefix`で設定されたURIを読むようになります。

そのためオブジェクトストレージを将来的に廃止した場合や移転した場合は、その画像を投稿した時点のURLを参照し続けるので、そのURLが消滅した時点で404になってしまいます。

しかしリバースプロキシしておけば、URLを変えずにオブジェクトストレージを変更できますし、最悪廃止した場合でも、そのURLでローカルのファイルを読み出すように設定すれば404になることを回避可能です。

Misskeyはファイルシステムに保存している設定からオブジェクトストレージを利用する設定への移行をサポートしていません。

そのためオブジェクトストレージ移行後に`/files`に保存されたファイルを消すとドライブから参照できなくなります。

すでに`/files`にあるファイルをオブジェクトストレージに上げても見れるようにはなりません。

DB操作してURIを書き換えてもその変更を連合先に反映する手段がないのでよくありません。


# VultrのWebからオブジェクトストレージを作成する
Vultrのアカウントにログインしてオブジェクトストレージを追加する。

今はアメリカのニュージャージー州かシンガポールのどちらかを選択できる。

アメリカとシンガポールって、サーバーのリージョンによってすごい差がありそうですねw
私は両方使ってます。たぶん日本にMisskeyサーバーあるならシンガポールの方が読み込み速度が速いです。

Labelは適当に。
ReadyになったらCreate Bucketsでバケット作成する。

このバケット名は同一リージョン内で他のユーザのものを含めユニークである（重複しない）必要があるので、
オリジナル性の高い名前（インスタンス名）とかにするといいんじゃないかしら。

バケット作成できたらそのタブは開きっぱなしにして次に。

# オブジェクトストレージのポリシーを設定する
Vultrのオブジェクトストレージはデフォルトだと非公開なので公開できるようにする。

以下のコマンドでまずオブジェクトストレージに繋がるようにする。

s3cmdの使い方については https://www.vultr.com/ja/docs/how-to-use-s3cmd-with-vultr-object-storage を見て。

```
sudo (apt|dnf) install s3cmd
s3cmd --configure
```
Access Keyはさっき開きっぱなしにしてたページのAccess Keyを入力

Secret KeyはそのページのSecret Keyを入力

Default RegionはEnter

S3 Endpointは`ewr1.vultrobjects.com`か`sgp1.vultrobjects.com`を入力

DNS-styleは`%(bucket)s.ewr1.vultrobjects.com`か`%(bucket)s.sgp1.vultrobjects.com`を入力

あとはEnter, Enter, Enter, y+Enter, y+Enterで進む

できたら今度`misskey-media_policy`ってテキストファイルを作成
yourbacketnameは各自の設定したバケット名で置き換え

```php:misskey-media_policy
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AddPerm",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::yourbacketname/*"
    }
  ]
}
```

保存して、`s3cmd setpolicy misskey-media_policy s3://yourbacketname`を実行

# オブジェクトストレージ参照用のプロキシを作る

大きく分けて３パターンの設定方法がある

特に後戻りできないのでよく思慮して欲しい

## 一番多い新しいサブドメイン等で配信するケース
例：misskey.io: https://s3.arkjp.net/misskey

misskey.dev: https://s3.arkjp.jp/dev

misskey.m544.net: https://misskey-drive2.m544.net/m544

meisskey.one: https://misskey-drive2.m544.net/one

メリット：オブジェクトストレージ専用のNginxとかのプロキシサーバーを置くことができる、ある程度以上の規模のインスタンスではこれを採用しておくのが自然かと

デメリット：サブドメインを取得しないといけない、Cloudflareとかはサブドメインのサブドメインに証明書を発行しないので、うまいサブドメインを考えないといけない手間がかかる

## あんまりみたことないけど（わいだけ？？？）新しいディレクトリを新設して配信するケース
例：mk.shc.kanagawa.jp: https://mk.shc.kanagawa.jp/storage

Pleromaだけどpr.shc.kanagawa.jp: https://pr.shc.kanagawa.jp/storage

メリット：サブドメインを取得しなくてよい、Cloudflareとかはサブドメインのサブドメインに証明書を発行しないわけだし、オブジェクトストレージに移行した後のURIが新しいものとなるので設定は楽？

デメリット：オブジェクトストレージへのプロキシをmisskey Webと同じWebサーバーに置かないといけない、つまりアクセス増加した際に専用のオブジェクトストレージプロキシ用のNginxを用意するとかは不可能になる

## 一番スマートな既存の配信ディレクトリを置き換えるケース
ちょっと設定がうまくいった試しがないので、情報提供募集中です。

## 手順

<details><summary>新しいサブドメイン等で配信するケース</summary>

### ネームサーバーでメディア用プロキシのサブドメインのレコードを作成する
オブジェクトストレージのメディアを参照するためのWebサーバーのアドレスをサブドメインとして登録する。
  
私はGoogle Domainsなのだけど、ここでmisskeyサーバーと同じアドレスで、s3っていうホスト名のサブドメインのAレコード, AAAAレコードを追加する。s3っていうのはawsで使われる名前ではあるけど、s3互換とか言うし短い名前だからいいんじゃないかしら。

ちなみに全然違うドメインにホストしても構わないからね。
  
misskey.ioだってs3.arkjp.netでメディア用プロキシをホストしてたりするし

### メディア用プロキシのNginx設定ファイルを作成する
そしたらそのメディア用のプロキシのためのNginxの設定ファイルを書いてくよ
  
私は/etc/nginx/conf.d/s3.yourdomain.confに設定ファイル書いてるけど
  
各自の運用に合わせて作成してみて
  
yourdomainを各自のドメイン名で置き換えるのと
  
proxy_pass の後のURLはyourbacketnameがバケット名なのでさっき作成したバケット名に置き換える。


```
mkdir /var/cache/nginx/proxy_cache_images
chown -R nginx: /var/cache/nginx/proxy_cache_images
```
  
```nginx:s3.yourdomain.conf
server {
  listen 80;
  listen [::]:80;
  server_name s3.yourdomain;
  location /.well-known/acme-challenge/ { allow all; }
  location / { return 301 https://$host$request_uri; }
}

proxy_cache_path /var/cache/nginx/proxy_cache_images levels=1 keys_zone=images:2m max_size=20g inactive=90d;
  
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name s3.yourdomain;
    ssl_session_cache shared:ssl_session_cache:10m;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!MEDIUM:!LOW:!aNULL:!NULL:!SHA;

    location / {
      try_files $uri $uri/ @proxy;
    }

    location @proxy {
      proxy_ignore_headers set-cookie;
      proxy_hide_header set-cookie;
      proxy_set_header cookie "";
      proxy_hide_header etag;
      resolver 1.1.1.1 valid=100s;
      proxy_pass https://yourbacketname.ewr1.vultrobjects.com$request_uri; #シンガポールならewr1ではなくsgp1
      expires max;
  proxy_buffering on;
  proxy_hide_header Set-Cookie;
  proxy_ignore_headers Set-Cookie;
  proxy_set_header cookie "";
  proxy_cache images;
  proxy_cache_valid 200 302 90d;
  proxy_cache_valid any 5m;
  proxy_ignore_headers Cache-Control Expires;
  proxy_cache_lock on;
  add_header X-Cache $upstream_cache_status;
    }
}

```

### メディア用プロキシのサブドメインのSSL証明書を取得する
先ほどs3っていうホスト名のサブドメイン作ったのでSSL証明書が必要ですね。
  
今回はcertbotのnginxプラグインで一発で取得しちゃいます。
  
yourdomainは各自のドメインにしてね。
  
`sudo certbot --nginx -d s3.yourdomain`
  
それで成功したならば、`sudo nginx -t`で確認して`sudo systemctl reload nginx`で反映

</details>

<details><summary>新しくディレクトリを新設して配信するケース</summary>

今回は`https://インスタンスのドメイン/storage`っていうディレクトリから配信するようにします。
  
別に`storage`っていう文字列でなくとも構わない、すでにmisskeyにより使われているとこじゃなかったら
  
現在は`https://インスタンスのドメイン/files`から配信されていますのでこれを変更します。

```
mkdir /var/cache/nginx/proxy_cache_images
chown -R nginx: /var/cache/nginx/proxy_cache_images
```

misskeyのNginxファイルに以下追記

まずserverディレクティブの外部に
```nginx:/etc/nginx/sites-available/misskey.conf
proxy_cache_path /var/cache/nginx/proxy_cache_images levels=1 keys_zone=images:2m max_size=20g inactive=90d;
```

```nginx:/etc/nginx/sites-available/misskey.conf
location /storage/ {
  limit_except GET {
    deny all;
  }

  try_files $uri $uri/ @proxy;

  resolver 1.1.1.1 valid=100s;

  proxy_pass https://バケット名.ewr1.vultrobjects.com/; #シンガポールならewr1ではなくsgp1

  proxy_buffering on;
  proxy_redirect off;
  proxy_http_version 1.1;
  proxy_set_header Host バケット名.ewr1.vultrobjects.com; #シンガポールならewr1ではなくsgp1
  tcp_nodelay on;


  expires max;
  proxy_hide_header etag;
  proxy_hide_header Set-Cookie;
  proxy_ignore_headers Set-Cookie;
  proxy_set_header cookie "";
  proxy_cache images;
  proxy_cache_valid 200 302 90d;
  proxy_cache_valid any 5m;
  proxy_ignore_headers Cache-Control Expires;
  proxy_cache_lock on;
  add_header X-Cache $upstream_cache_status;

  
}
```

</details>

<details><summary>配信ディレクトリ置き換えるケース</summary>

ちょっといろいろと気をつけないといけないことが多いので、以下の記事が詳しい。
  
今回はSwift使わないのでそこを読み替えること。
  
Misskeyではどうしたらうまくいくんだろう…
  
Misskeyの`/files`がMastodonの`/system`と取り扱いが違う感じする

MastodonのメディアファイルをOpenStack Swift互換オブジェクトストレージに移行する by @neustrashimy 
https://qiita.com/neustrashimy/items/e86737534104a7db3843#%E3%82%B5%E3%83%BC%E3%83%90%E5%81%B4%E8%A8%AD%E5%AE%9A2-%E9%85%8D%E4%BF%A1%E3%83%87%E3%82%A3%E3%83%AC%E3%82%AF%E3%83%88%E3%83%AA%E7%BD%AE%E3%81%8D%E6%8F%9B%E3%81%88%E3%81%AE%E5%A0%B4%E5%90%88

</details>

これを保存したら `sudo nginx -t` で設定ファイル確認して大丈夫なら `sudo systemctl reload nginx`

# Nginxのsystemd serviceファイルの編集

Nginxでオブジェクトストレージをプロキシするようにしたのですが、どうやらサーバーを再起動した後にNginxの起動に失敗するようになってしまうケースがあるようです（私がそうだった）  
原因としてはNginxが`network-online.target`のあと`multi-user.target`で起動するのですが、その際にリンクアップしているもののまだインターネットにつながってないことがあるため、Nginxの起動時に`nginx -t`を実行してupstreamに接続できないっていうエラーを出してしまうからです。  
対策として  
```
systemctl edit --full nginx.service
```
でNginxのサービスファイルを開いたら、`[Service]`の中に
```systemd:/etc/systemd/system/nginx.service
Restart=always
RestartSec=5
```
と追記します。  
できたら`systemctl status nginx`でエラーが出ていないことを確認してください。  
この設定ではNginxのプロセスが何らかの原因で落ちてしまった時に5秒待って再起動するようにしています。  
これでインターネットにつながるまで待つことができるので何回目かの再起動にて正常に起動できます。  


# misskeyの設定ファイルの編集
misskey v10は設定ファイルを以下の要領で編集、misskey v11以降は設定画面より編集

以下の設定値を反映

yourbacketname, youraccesskey, yoursecretkeyは各自の値で置き換え

prefixはオブジェクトストレージのプロキシの配信ディレクトリを`/storage`とする場合のみ`storage`にする、他の方々は`misskey`とか`dev`とか`m544`とかに設定している…何もつけないことができないので、なんかは設定する、どうしてもつけたくない場合はNginxの設定を工夫すると可能

yourdomainは新しいサブドメイン等から配信する際はそのドメイン名にし、
ディレクトリ新設して配信する場合はインスタンスのドメイン名とする

ここで設定する`baseUrl`が連合先にも反映されるため、十分に確認してから本番環境へ展開すること

```shell:.config/default.yml
#drive: #コメントアウト
#  storage: 'fs' #コメントアウト

drive:
  storage: 'minio'
  bucket: yourbacketname
  prefix: storage
  baseUrl: https://yourdomain
  config:
    endPoint: sgp1.vultrobjects.com #ニュージャージーならewr1
    useSSL: true
    accessKey: youraccesskey
    secretKey: yoursecretkey
    setPublicRead: false
    s3ForcePathStyle: true
```

問題なければ、sudoユーザーに戻り`sudo systemctl restart misskey`で再起動し設定ファイルを反映

もしエラーが出るなら`sudo journalctl -u misskey -f`などで内容を確認

またブラウザからmisskey開いてみて、試しに画像をドライブに投稿してみて、その画像が見えるようになれば、大丈夫

もし出てこないなら何か間違っているので、手順を見直し、投稿した画像のサムネを右クリックして`新しいタブで画像を開く`で表示されるURLを確認、これが`https://s3.yourdomain/storage`または`https://yourdomain/storage`になっているかどうかを見てやる。
