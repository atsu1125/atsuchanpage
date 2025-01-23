#!/bin/bash

versionfiledirectory="/home/misskey"
misskeydirectory="/home/misskey/misskey"

#アップデートの必要があるのかバージョンチェック
dockerversion=`docker-compose -f $misskeydirectory/docker-compose.yml images | grep web | sed -n '1p' | awk '{print $3}'`
#バージョンチェック用のファイルがないなら新規作成して稼働中のバージョンを代入
#バージョンチェック用のファイルが必要な理由は例えばこのスクリプトが中止されたときバージョンが変わらなくなることがあるから
if [ ! -e $versionfiledirectory/versioncheck.txt ]; then
touch $versionfiledirectory/versioncheck.txt
echo $dockerversion > $versionfiledirectory/versioncheck.txt
fi
oldversion=`cat $versionfiledirectory/versioncheck.txt`
echo "Current Version is $oldversion"

#現在安定板はv12.119.2だが古すぎるためv13のlatestタグがついているバージョンをGithubから取得
#プレリリースは受信しない
#もしくはコードネームがナスビなのか確認（カレンダーバージョニングに対応）
VERSION=`curl -s https://api.github.com/repos/misskey-dev/misskey/releases/latest | grep tag_name | cut -d '"' -f 4`
echo "Latest Misskey version is $VERSION"
stableversion=${VERSION}
codename=$(curl -s https://raw.githubusercontent.com/misskey-dev/misskey/$stableversion/package.json | grep "codename" | cut -d '"' -f 4)
echo "Codename is $codename"

#Github APIから取得した値が異常値もしくはメジャーバージョンをまたぐなら更新をさせない
if [[ $stableversion =~ 13\.+[0-9] ]] || [[ $codename =~ nasubi ]]; then
echo version check is ok.
versioncheck=0
else
echo version check was failed.
versioncheck=1
fi
if [ $oldversion != $stableversion ] && [ $versioncheck = 0 ]; then
echo Misskeyの安定版は${oldversion}から${stableversion}に変わりました。
echo アップデートを実行します。

#docker-composeのimageのバージョンを書き換えてupコマンドで更新開始

sudo sed -i -e "/^ *image: misskey\/misskey:/c\    image: misskey\/misskey:$stableversion" $misskeydirectory/docker-compose.yml
docker-compose -f $misskeydirectory/docker-compose.yml pull;docker-compose -f $misskeydirectory/docker-compose.yml up -d

#アップデート完了までスタンバイする（12秒ごとにヘルスチェック6回失敗したら諦める）
HEALTH=`docker-compose -f $misskeydirectory/docker-compose.yml ps | grep -c '(healthy)'`
TIMEOUT=0

until [ ${HEALTH} -gt 3 ] || [ ${TIMEOUT} -gt 6 ] ;
do
echo waiting the node is online...
sleep 12s
HEALTH=`docker-compose -f $misskeydirectory/docker-compose.yml ps | grep -c '(healthy)'`
TIMEOUT=$(( $TIMEOUT + 1 ))
done

#稼働中のバージョンがアップデート先のバージョンかチェック
dockerversion=`docker-compose -f $misskeydirectory/docker-compose.yml images | grep web | sed -n '1p' | awk '{print $3}'`
if [[ $stableversion = $dockerversion ]] && [ ${HEALTH} -gt 3 ] ; then
echo アップデート完了しました。バージョンを記憶します。
echo $dockerversion > $versionfiledirectory/versioncheck.txt
else
#もしバージョンアップに失敗してそうなら旧バージョンに戻す
echo アップデート失敗しました。元に戻します。
sudo sed -i -e "/^ *image: misskey\/misskey:/c\    image: misskey\/misskey:$oldversion" $misskeydirectory/docker-compose.yml
docker-compose -f $misskeydirectory/docker-compose.yml up -d
fi

#このelseはバージョンが最新版であるか、異常値を取得してしまったか、メジャーバージョンが変わってしまったかがマッチ
#いつまでif引き回してるんだって感じではあるが仕方ない
else
echo $oldversion is latest.
fi
