### はじめに
mongoDBをオブジェクトストレージにバックアップしたい  
でもPostgreSQLみたいに便利なバックアップツールがない  
https://qiita.com/atsu1125/items/676d24c0473ad94b3f2b  
PostgreSQLならポイントインリカバリに使えるようなバックアップが構築可能なのに…  
最近WAL-GもmongoDBにベータ対応したけど  
https://wal-g.readthedocs.io/MongoDB/  

ここは自作スクリプトでバックアップするしかなさそう  
ただ`mongodump`の実行時にはサーバーのスペックがかなり持っていかれるので、  
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


