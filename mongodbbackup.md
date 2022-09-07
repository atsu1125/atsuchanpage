mongoDBをオブジェクトストレージにバックアップするやつ
```bash
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
