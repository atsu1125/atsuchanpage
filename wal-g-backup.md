MastodonのPostgreSQLのDatabaseをWAL-Gでオブジェクトストレージにバックアップしたい
# 最初に
基本的にのえるさんの記事を参考にさせてもらいました。
https://blog.noellabo.jp/entry/2019/03/05/yMjQeU9JXHxcyHTL
ちょっと気になった点と相違点などを補足させてもらいます。
参考元よりかなり雑なので一度ご覧になってからの方がいいかもしれない…

# 作業環境
ここの作業環境はFedora 34ですが、同時にセットアップしたCentOS Stream 8でも動きました、DBはPostgreSQL13です
ただ後者CentOS Stream 8はwal-gのパッケージがwal-g-pg-ubuntu-18.04-amd64.tar.gzじゃないといけなかった
前者Fedora 34はwal-g-pg-ubuntu-20.04-amd64.tar.gzのパッケージで動いた
バージョンとしてはwal-g v1.0を使わせてもらいました
FedoraなんでUbuntuのビルド済みパッケージ使えないかと思ったけど
そんなことはなかったのでwgetでubuntuのビルド済みパッケージをダウンロードして解凍して/usr/bin/localにwal-g置いた

# 環境変数定義
この子環境変数を定義しないと動かないんですが、envdirを使わないので
/usr/local/bin/wal-g-profileというファイルを作成していちいち読み込むことに
今回の作業環境はGoogle Cloud Storageなので設定値はちゃんと見てもらって
https://cloud.google.com/docs/authentication/production#manually
を参考にjsonファイルをコンピュータにダウンロードしてサーバーの任意のディレクトリに置いて欲しい

```php:wal-g-profile
export WALG_GS_PREFIX="バケットのgsutil URI"
export GOOGLE_APPLICATION_CREDENTIALS="さっきのjsonファイルのディレクトリ指定"
export PGPORT="5432"
export PGHOST="/var/run/postgresql"
```

# フルバックアップはサービス化したい　１日ごとのバックアップ
フルバックアップはサービス化したいんで
/etc/systemd/system/wal-g-full-backup.serviceを作成し、systemctl daemon-reload
ExecStartの最初のコマンドでさっきのwal-g-profileっていうファイルを開くことで環境変数割り当ててる
ちなみにExecStartPostに書いてあるのはBetter Uptimeっていうので死活監視したくてheartbeat用のURLにcurl投げてます
このサービスを実行することでデータベースのバックアップをオブジェクトストレージに転送できます
うちはretain 90で90個分（＝９０日分）保存してるわけだけど１回あたりで結構容量食うから７個分とかでもいいかも

```php:wal-g-full-backup.service
[Unit]
Description = WAL-G Full Backup

[Service]
Type = simple
User = postgres
WorkingDirectory = /usr/local/bin
ExecStart = /usr/bin/bash -c '. /usr/local/bin/wal-g-profile;/usr/local/bin/wal-g backup-push /var/lib/pgsql/13/data;/usr/local/bin/wal-g delete retain 90 --confirm'
ExecStartPost = curl "監視サイトのheartbeat設定ページに書いてあるURL"
```

# cronで毎日実行させたい
上記のバックアップをcronで毎日実行したいんですが最近はcrondが無効化されてることあるらしいので
crondサービスをsystemctlで有効化して開始する
cronが入ってないのならばインストール、すでに有効化済みならOK
そもそもcron使わないでsystemctlのtimerファイル作成でもよし（これが最近のトレンドらしい）
/etc/cron.daily/wal-g-dailyっていうファイルを作成

```php:wal-g-daily
#!/bin/bash
systemctl start wal-g-full-backup
```
あとはこれにchmod +x /etc/cron.daily/wal-g-dailyで実行権限付与する（しないとcronが動かない）

# postgresql.confの設定 毎分のバックアップの設定
postgresql.confの該当箇所のみ書き換える /var/lib/pgsql/13/data/postgresql.conf
これで毎分WALをアーカイブしてオブジェクトストレージに転送できるらしい
archive_commandでさっきのwal-g-profileっていうファイルを開くことで環境変数割り当ててる
設定終わったらsystemctl restart postgresql-13.service

```php:postgresql.conf
archive_mode = on
archive_command = '. /usr/local/bin/wal-g-profile;/usr/local/bin/wal-g wal-push %p'
archive_timeout = 60
wal_level = replica
restore_command = '. /usr/local/bin/wal-g-profile;/usr/local/bin/wal-g wal-fetch "%f" "%p"'
```

あとはsudo tail -f /var/lib/pgsql/13/data/log/postgresql-{任意の曜日}.logで変なエラー出てないか見てやる
