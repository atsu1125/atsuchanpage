# なぜ
私のインスタンスはVultr Cloud Computeで動いているわけですが、前回の記事でリモートメディアを定期的に削除してディスク使用量を削減しているものの、削除しすぎて掘り返したい画像がなかったので、今回はMastodonのメディアを全てVultr Object Storageに保管することになりました。
https://qiita.com/atsu1125/items/5c7ce7475cd3e74ad456

# 環境
うちは以下２台のサーバーでMastodonのアプリケーションを実行しています。  
データベースはまた別なサーバーにあります。  
通常１台のサーバーだと思いますのでそれ向けの内容で書きます。  
Vultr Cloud Compute Tokyo Region RAM 2GB/SSD55GB Fedora 35 non Docker  
Vultr Cloud Compute Seoul Region RAM 2GB/SSD55GB Fedora 37 non Docker  
そして今回はオブジェクトストレージのURLをそのまま公開することはせず、MastodonをホストしているNginxでリバースプロキシを行います。  
そうしないとリージョンが遠くて単純に不利だし、転送量課金なのでなるべくキャッシュして帯域利用量を減らすべきなのです。  
またオブジェクトストレージを将来的に廃止した場合や移転した場合は、自分のインスタンス上では設定ファイルの書き換えだけでURLを変更できちゃいますが、リモートインスタンスから見ればその画像を投稿した時点のURLを参照し続けるので、そのURLが消滅した時点で404になってしまいます。  
しかしリバースプロキシしておけば、URLを変えずにオブジェクトストレージを変更できますし、最悪廃止した場合でも、そのURLでローカルのファイルを読み出すように設定すれば404になることを回避可能です。  

# VultrのWebからオブジェクトストレージを作成する
Vultrのアカウントにログインしてオブジェクトストレージを追加する。  
今はアメリカのニュージャージー州かシンガポールのどちらかを選択できる。  
アメリカとシンガポールって、サーバーのリージョンによってすごい差がありそうですねw  
私は両方使ってます。たぶん日本にMastodonサーバーあるならシンガポールの方が読み込み速度が速いです。  
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
sudo dnf install s3cmd
s3cmd --configure
```
Access Keyはさっき開きっぱなしにしてたページのAccess Keyを入力  
Secret KeyはそのページのSecret Keyを入力  
Default RegionはEnter  
S3 Endpointは`ewr1.vultrobjects.com`か`sgp1.vultrobjects.com`を入力  
DNS-styleは`%(bucket)s.ewr1.vultrobjects.com`か`%(bucket)s.sgp1.vultrobjects.com`を入力  
あとはEnter, Enter, Enter, y+Enter, y+Enterで進む  

できたら今度`mastodon-media_policy`ってテキストファイルを作成  
yourbacketnameは各自の設定したバケット名で置き換え  

```txt:mastodon-media_policy
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

保存して、`s3cmd setpolicy mastodon-media_policy s3://yourbacketname`を実行  

# オブジェクトストレージ参照用のプロキシを作る

大きく分けて３パターンの設定方法がある  
特に後戻りできないのでよく思慮して欲しい  

## 一番多い新しいサブドメイン等で配信するケース
例：fedibird: https://s3.fedibird.com  
atsuchan.page: https://s3.atsuchan.page  

メリット：オブジェクトストレージ専用のNginxとかのプロキシサーバーを置くことができる、ある程度以上の規模のインスタンスではこれを採用しておくのが自然かと  
デメリット：サブドメインを取得しないといけない、Cloudflareとかはサブドメインのサブドメインに証明書を発行しないので、うまいサブドメインを考えないといけない手間がかかる  


## あんまりみたことないけど（わいだけ？？？）新しいディレクトリを新設して配信するケース
例：Misskeyだけどmk.shc.kanagawa.jp: https://mk.shc.kanagawa.jp/storage  
Pleromaだけどpr.shc.kanagawa.jp: https://pr.shc.kanagawa.jp/storage  

メリット：サブドメインを取得しなくてよい、Cloudflareとかはサブドメインのサブドメインに証明書を発行しないわけだし、オブジェクトストレージに移行した後のURIが新しいものとなるので設定は楽？  
デメリット：オブジェクトストレージへのプロキシをMastodon Webと同じWebサーバーに置かないといけない、つまりアクセス増加した際に専用のオブジェクトストレージプロキシ用のNginxを用意するとかは不可能になる  

## 一番スマートな既存の配信ディレクトリを置き換えるケース
例：mt.shc.kanagawa.jp: https://mt.shc.kanagawa.jp/system  
なごやどん: https://nagoyadon.jp/system  

メリット：サブドメインを取得しなくてよい、Cloudflareとかはサブドメインのサブドメインに証明書を発行しないわけだし、外から見ればオブジェクトストレージを利用する前後でメディアのURIが変わらない（今まで通りのURIですべての画像にアクセス可能）  
デメリット：オブジェクトストレージへのプロキシをMastodon Webと同じWebサーバーに置かないといけない、つまりアクセス増加した際に専用のオブジェクトストレージプロキシ用のNginxを用意するとかは不可能になる  

## 手順

<details><summary>新しいサブドメイン等で配信するケース</summary>

### ネームサーバーでメディア用プロキシのサブドメインのレコードを作成する
オブジェクトストレージのメディアを参照するためのWebサーバーのアドレスをサブドメインとして登録する。  
私はGoogle Domainsなのだけど、ここでMastodonサーバーと同じアドレスで、s3っていうホスト名のサブドメインのAレコード, AAAAレコードを追加する。s3っていうのはawsで使われる名前ではあるけど、s3互換とか言うし短い名前だからいいんじゃないかしら。  
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
chown -R mastodon: /var/cache/nginx/proxy_cache_images
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
      root /home/mastodon/live/public/system;
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
別に`storage`っていう文字列でなくとも構わない、すでにMastodonにより使われているとこじゃなかったら  
現在は`https://インスタンスのドメイン/system`から配信されていますのでこれを変更します。  

```
mkdir /var/cache/nginx/proxy_cache_images
chown -R mastodon: /var/cache/nginx/proxy_cache_images
```
  
mastodonのNginxファイルに以下追記

まずserverディレクティブの外部に
```nginx:/etc/nginx/sites-available/mastodon.conf
proxy_cache_path /var/cache/nginx/proxy_cache_images levels=1 keys_zone=images:2m max_size=20g inactive=90d;
```

次にserverディレクトリの内部に
```nginx:/etc/nginx/sites-available/mastodon.conf
location /storage/ {
  limit_except GET {
    deny all;
  }

  root /home/mastodon/live/public/system;
  try_files $uri $uri/ @proxy;

  resolver 1.1.1.1 valid=100s;

  rewrite /storage/(.*) /$1 break;

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

MastodonのメディアファイルをOpenStack Swift互換オブジェクトストレージに移行する by @neustrashimy   
https://qiita.com/neustrashimy/items/e86737534104a7db3843#%E3%82%B5%E3%83%BC%E3%83%90%E5%81%B4%E8%A8%AD%E5%AE%9A2-%E9%85%8D%E4%BF%A1%E3%83%87%E3%82%A3%E3%83%AC%E3%82%AF%E3%83%88%E3%83%AA%E7%BD%AE%E3%81%8D%E6%8F%9B%E3%81%88%E3%81%AE%E5%A0%B4%E5%90%88

</details>

これを保存したら `sudo nginx -t` で設定ファイル確認して大丈夫なら `sudo systemctl reload nginx`  

`try_files`では
オブジェクトストレージ設定反映以前の自分のインスタンスのメディアは自分のサーバーから参照していて、オブジェクトストレージの設定反映以降の自分のインスタンスのメディアは、オブジェクトストレージから参照しています。
Mastodonの設定ファイルでオブジェクトストレージを使用するようにすると
自分のインスタンス内では`S3_ALIAS_HOST`で設定されたURIで、オブジェクトストレージ移行前にアップロードされたファイルと移行後にアップロードされたファイルの両方を読もうとするが、
連合先では、オブジェクトストレージ移行前にアップロードされたファイルは`https://Mastodonのドメイン/system`を読み、移行後にアップロードされたファイルは`S3_ALIAS_HOST`で設定されたURIを読むためである。
もちろん工夫次第ではオブジェクトストレージ設定前のURIと設定後のURI両方でアクセスするように設定することもできます。

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

# Mastodonの設定ファイルの編集
いつも通りmastodonユーザーに入ったら`.env.production`を開いて編集  
以下の設定値を反映  
yourbacketname, youraccesskey, yoursecretkey, yourdomainは各自の値で置き換え  
ここで設定する`S3_ALIAS_HOST`が連合先にも反映されるため、十分に確認してから本番環境へ展開すること  

```shell:.env.production
S3_ENABLED=true
S3_BUCKET=yourbacketname
AWS_ACCESS_KEY_ID=youraccesskey
AWS_SECRET_ACCESS_KEY=yoursecretkey
S3_ENDPOINT=https://ewr1.vultrobjects.com #シンガポールならewr1ではなくsgp1
#新しいサブドメインから配信する場合
S3_ALIAS_HOST=s3.yourdomain
#新しいディレクトリから配信する場合
S3_ALIAS_HOST=yourdomain/storage
```
問題なければ、sudoユーザーに戻り`sudo systemctl restart mastodon-{web,sidekiq,streaming}`で再起動し設定ファイルを反映  
もしエラーが出るなら`sudo journalctl -u mastodon-web -f`などで内容を確認  
またブラウザからMastodon開いてみて、おそらくこの時点では画像が何も出てこないけど、試しに画像をアップロードして、DMの公開範囲で投稿してみるとその画像だけ見えるようになれば、大丈夫  
もし出てこないなら何か間違っているので、手順を見直し、投稿した画像のサムネを右クリックして`新しいタブで画像を開く`で表示されるURLを確認、これが`https://s3.yourdomain/media_attachments`または`https://yourdomain/storage/media_attachments`になっているかどうかを見てやる。  

# 既存のメディアキャッシュファイルをオブジェクトストレージに移動
今のままだと見えない画像だらけなのでオブジェクトストレージに移動したい  

ここでのよくある間違いとして自分のインスタンスのメディアは移動してはいけません。  
なんでかというと自分のインスタンスでは既存の画像を含めてオブジェクトストレージのURLに切り替わりますが、連合先では投稿済みのメディアのURLは切り替えません。  
ほとんどのMastodonインスタンスはローカルに画像をキャッシュしているとはいえ、Pleroma,Misskeyインスタンスの場合はキャッシュしていないことが多いです。つまりこの切り替え以前のメディアは一生オブジェクトストレージではなく`https://Mastodonのドメイン/system`にアクセスして逐一取得します。  
そのためローカルのメディアファイルを消すと404出てしまいます。気をつけましょう。  

警告はさておき、オブジェクトストレージにコピーしますので、Mastodonユーザーでログインしてください。
ここではaws-cliを使用します。  

```
pip3 install aws-cli
```
これでインストールできますが多分`aws configure`しても失敗します。見つからないって言われます。  
なのでパスを通すのです。  
.bash_profileを編集しましょう  

```bash:.bash-profile
export PATH="/home/mastodon/.local/bin:${PATH}"
```
を追加してください。  
環境によっては違うところにあるかもしれないのでその場合はpip3を駆使して探しましょう。  
パス通ったら  
`aws configure`で先ほどのようにアクセスキー・シークレットキーを入力してEnterで確定します。  
できたら以下のコマンドで転送開始です。yourbacketnameは適宜置き換えです。  
これ大体ですね、環境によって何時間かかります。やってみないとわからないです。  

```
aws s3 sync /home/mastodon/live/public/system/cache s3://yourbacketname/cache --endpoint-url=https://ewr1.vultrobjects.com
```
転送が終われば多分普段通りにMastodon使えるようになってるはずです。  
あとはローカルのキャッシュを消します。  

```
mv /home/mastodon/live/public/system/cache{,.old}
```
はい、このコマンドでは消えませんが、消したような扱いにはなります。  
これでMastodon開いて正しく画像が表示されてる確認してください。  
十分確認して大丈夫なら  

```
rm -r /home/mastodon/live/public/system/cache.old
```
これである程度開放されたはずです。  

繰り返しますがここでのよくある間違いとしてローカルのメディアの削除はしてはいけません。cacheは外部から持ってきたもの（他のインスタンスのメディアファイル）ですが、それ以外は自分のインスタンスにしかないものなので、削除しちゃうとリモートインスタンスから見たときは404エラーになります。  
mastodonのpublic/systemを削除するコマンドとか打たないように。  
Pleroma, Misskey鯖缶から怒られが発生しますよ。  

