#!/bin/bash

versionfiledirectory="/home/cherrypick"

if [ ! -e $versionfiledirectory/versioncheck.txt ]; then
touch $versionfiledirectory/versioncheck.txt
echo 1 > $versionfiledirectory/versioncheck.txt
fi
oldversion=`cat $versionfiledirectory/versioncheck.txt`
echo "Current Version is $oldversion"

#現在安定板はv12.119.2だが古すぎるためv13のlatestタグがついているバージョンをGithubから取得
#プレリリースは受信しない
#もしくはコードネームがナスビなのか確認（カレンダーバージョニングに対応）
VERSION=`curl -s https://api.github.com/repos/kokonect-link/cherrypick/releases/latest | grep tag_name | cut -d '"' -f 4`
echo "Latest Misskey version is $VERSION"
stableversion=${VERSION}
codename=$(curl -s https://raw.githubusercontent.com/kokonect-link/cherrypick/$stableversion/package.json | grep "codename" | cut -d '"' -f 4)
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

git clone https://github.com/kokonect-link/cherrypick -b $stableversion cherrypick-$stableversion
docker build --no-cache -t ghcr.io/atsu1125/cherrypick:${stableversion} -t ghcr.io/atsu1125/cherrypick:latest cherrypick-${stableversion}
docker push ghcr.io/atsu1125/cherrypick:${stableversion}
docker push ghcr.io/atsu1125/cherrypick:latest
rm -rf cherrypick-${stableversion}

echo ${stableversion} > versioncheck.txt

#このelseはバージョンが最新版であるか、異常値を取得してしまったか、メジャーバージョンが変わってしまったかがマッチ
#いつまでif引き回してるんだって感じではあるが仕方ない
else
echo $oldversion is latest.
fi
