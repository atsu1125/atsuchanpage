### はじめに
mongoDBをオブジェクトストレージにバックアップしたい  
でもPostgreSQLみたいに便利なバックアップツールがない  
https://qiita.com/atsu1125/items/676d24c0473ad94b3f2b  
PostgreSQLならポイントインリカバリに使えるようなバックアップが構築可能なのに…  
と思ったら最近WAL-GもmongoDBにベータ対応したらしい  
https://wal-g.readthedocs.io/MongoDB/  
ここは自作スクリプトでバックアップするかベータ版WAL-Gでバックアップするか選んでください。      

<details><summary>自作スクリプトでバックアップ（非推奨）</summary>

`mongodump`の実行時にはサーバーのスペックがかなり持っていかれるので、  
現状は１日１回の頻度でセカンダリのデータベースから実行することにしている。  
https://qiita.com/atsu1125/items/df0ca4d47b835f22dbd3  
で書いたようにレプリケーションを組み合わせるとよさそう。  

### シェルスクリプト作成

`/usr/local/bin/mongodbbackup.sh`
として作成する。

```bash:/usr/local/bin/mongodbbackup.sh
# バックアップファイルを残しておく日数
PERIOD='+21'
# 日付
DATE=`date '+%Y%m%d-%H%M%S'`
# 作業ディレクトリ（中身は空のもの）
WORKDIR='/tmp/mongo/'
# バックアップ先ディレクトリ
SAVEPATH='/usr/local/dbbackup/misskey/'
#先頭文字
PREFIX='misskeymongo-'
#データーベース
DBNAME='misskey'
HOST='localhost'
PORT="27017"
USERNAME="misskey"
PASSWORD="パスワード"
#ヘルスチェック
HEARTBEAT="ハートビート用のURI(https://)"
#オブジェクトストレージ
ENDPOINT="エンドポイント(https://sgp1.vultrobjects.com)"
BACKET="バケット名（s3://)"

#作業ディレクトリに中身残ってたら先に削除
rm -rf $WORKDIR
mkdir -p $WORKDIR

#バックアップ実行
output=$(mongodump -d $DBNAME -h $HOST:$PORT -u $USERNAME -p $PASSWORD --readPreference 'secondary')
result=$?
if [ $result = 0 ]; then
    echo "mongodump success"
    /usr/bin/curl $HEARTBEAT
else
echo "mongodump failed"
exit 1
fi

#圧縮ファイルにまとめる
mkdir -p $SAVEPATH$PREFIX$DATE
mv dump $SAVEPATH$PREFIX$DATE
tar -zcvf $SAVEPATH$PREFIX$DATE.tgz $SAVEPATH$PREFIX$DATE
rm -rf $SAVEPATH$PREFIX$DATE

#s3に転送
aws s3 sync --endpoint-url=$ENDPOINT $SAVEPATH $BACKET --delete

#保存期間が過ぎたファイルの削除
find $SAVEPATH -type f -daystart -mtime $PERIOD -exec rm {} \;
```

### systemdにインストールして自動化
`systemctl edit --full --force mongodump.service`
で
```systemd:mongodump.service
[Unit]
Description=mongoDB Backup

[Service]
User=root
Type=oneshot
ExecStart=/bin/bash -c /usr/local/bin/mongodbbackup.sh
TimeoutSec=7200
```
を作成  
oneshotにすることでのちのcron.dailyでの実行時に処理が被らないようになる。  
TimeoutSecを設定しないとmongodumpに時間かかってタイムアウトすることがある。  

次にFedoraの場合crondが動いていることを確認、Ubuntuの場合anacronが動いてることを確認する。  
そしたら`/etc/cron.daily/mongodbbackup`を作成
```bash:/etc/cron.daily/mongodbbackup
systemctl start mongodump.service
```
これでいい感じの時間にmongodumpが実行される。  
</details>

<details><summary>ベータ版のWAL-Gでバックアップ（どちらかといえば推奨）</summary>

# WAL-Gのインストール

これは普通にビルド済みの実行ファイルを入れます。  

```
wget https://github.com/wal-g/wal-g/releases/download/v2.0.1/wal-g-mongo-ubuntu-20.04-amd64
chmod +x wal-g-mongo-ubuntu-20.04-amd64
mv wal-g-mongo-ubuntu-20.04-amd64 /usr/local/bin/wal-g-mongo
```

# 環境変数定義
次に`/usr/local/bin/wal-g-mongo.sh`を作成します。  
ラッパーってやつです。このスクリプトで環境変数を操作します。  
設定値は各自で読み替えてもらってください。  
S3互換のストレージ使ってますが、GSでもいけます。  
https://qiita.com/atsu1125/items/676d24c0473ad94b3f2b#%E7%92%B0%E5%A2%83%E5%A4%89%E6%95%B0%E5%AE%9A%E7%BE%A9  
を参考に。  

```bash:/usr/local/bin/wal-g-mongo.sh
#!/bin/bash
export AWS_ACCESS_KEY_ID="アクセスキー"
export AWS_SECRET_ACCESS_KEY="シークレット"
export AWS_ENDPOINT="https://エンドポイント"
export WALG_S3_PREFIX="s3://バケット名/"
export MONGODB_URI="mongodb://ユーザー名:パスワード@localhost:27017/?authSource=認証データベース名&socketTimeoutMS=60000&connectTimeoutMS=10000"
export WALG_STREAM_CREATE_COMMAND='mongodump --archive --oplog -h localhost:27017 -u ユーザー名 -p パスワード --authenticationDatabase 認証データベース名'
export WALG_STREAM_RESTORE_COMMAND='mongorestore --archive --oplogReplay -h localhost:27017 -u ユーザー名 -p パスワード --authenticationDatabase 認証データベース名'
export OPLOG_ARCHIVE_TIMEOUT_INTERVAL="30s"
export OPLOG_ARCHIVE_AFTER_SIZE="20971520"
export OPLOG_PITR_DISCOVERY_INTERVAL="168h"
export OPLOG_PUSH_WAIT_FOR_BECOME_PRIMARY="true"
export WALG_COMPRESSION_METHOD="brotli"

exec /usr/local/bin/wal-g-mongo "$@"
```

# フルバックアップの設定
フルバックアップはサービス化したいんで
```bash
systemctl edit --full --force wal-g-mongo-dump.service
```
で

```systemd:wal-g-mongo-dump.service
[Unit]
Description = Push mongodump

[Service]
Type = oneshot
User = root
WorkingDirectory = /usr/local/bin
ExecStart = /usr/bin/bash -c '/usr/local/bin/wal-g-mongo.sh backup-push'
ExecStartPost = /usr/bin/bash -c '/usr/local/bin/wal-g-mongo.sh delete --retain-count 7 --confirm'
ExecStartPost = /usr/bin/bash -c '/usr/local/bin/wal-g-mongo.sh oplog-purge --confirm'
```

を入力します。  
手動でこのサービスを実行することでもデータベースのバックアップをオブジェクトストレージに転送できます。  
retain 7で直近７個分のバックアップ保存してます。  
これを定期実行させたいので  

```bash
systemctl edit --full --force wal-g-mongo-dump.timer
```

で

```systemd:wal-g-mongo-dump.timer
[Unit]
Description=Push mongodump Timer

[Timer]
OnCalendar=daily
Persistent=false
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
```
を入力します。  
毎日だいたい０時に3600秒以内の遅延で実行されます。  

```bash
systemctl enable --now wal-g-mongo-dump.timer
```
でこのタイマーを開始できます。  

実行ログなどに関しては
```bash
systemctl status wal-g-mongo-dump
journalctl -xeu wal-g-mongo-dump
systemctl list-timers
```
であたりで確認します。  

# oplogのアーカイブの設定

oplogをアーカイブしてポイントインリカバリに使えるようにしたいわけです。  
mongoDBにおける`oplog push`はサービスとして実行するのがよさそうです。  

```bash
systemctl edit --full --force wal-g-mongo-oplog.service
```
で

```systemd:wal-g-mongo-oplog.service
[Unit]
Description = Push mongo oplog
Requires = mongod.service

[Service]
Type = simple
User = root
WorkingDirectory = /usr/local/bin
ExecStart = /usr/bin/bash -c '/usr/local/bin/wal-g-mongo.sh oplog-push'
Restart = always

[Install]
WantedBy=multi-user.target
```
を入力してください。  

これはmongoDBが起動した後にサービスとして起動するので、

```bash
systemctl enable --now wal-g-mongo-oplog.service
```
でサービスを自動起動・開始してください。  

```bash
systemctl status wal-g-mongo-oplog.service
journalctl -xeu wal-g-mongo-oplog.service
```
で正常に動いてるか見てみましょう。  
</details>
