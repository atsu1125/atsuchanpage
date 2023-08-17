Misskey自動アップデート  
misskey.ioのmissskeystableさんに追従することで安定最新版を常に利用できる  
https://misskey.io/@misskeystable

## 条件
docker composeでMisskeyをソースコード変えずに運用していること  
`/home/misskey/misskey/docker-compose.yml`にdocker-compose.ymlがあること  
Misskey v12系のバージョンを運用していること

## 環境設定
`touch /home/misskey/misskeystable.txt`

For Fedora
`dnf install jq curl`

For Debian
`apt install jq curl`

## スクリプト


<details><summary>amd64コンピュータDocker版；こっちのが楽</summary>

`docker-compose.yml`で
```
    image: misskey/misskey:latest
```
を記載

/home/misskey/misskeystable.sh
```bash:misskeystable.sh
#!/bin/bash
oldversion=`cat /home/misskey/misskeystable.txt`
stableversion=`curl --silent -X POST https://misskey.io/api/users/show -d '{"username":"misskeystable"}' | jq -r '.description'`
health=`curl --silent -I -X POST https://misskey.io/api/ping | grep HTTP | awk '{print $2}'`
if [[ $stableversion =~ 12\.+[0-9] ]] && [ $health = 200 ]; then
echo version check is ok.
versioncheck=0
else
echo version check was failed.
versioncheck=1
fi
if [ $oldversion != $stableversion ] && [ $versioncheck = 0 ]; then
echo Misskeyの安定版は${oldversion}から${stableversion}に変わりました。
echo アップデートを実行します。

echo ５分待機します。
sleep 300
sudo sed -i -e "/^ *image: misskey\/misskey:/c\    image: misskey\/misskey:$stableversion" /home/misskey/misskey/docker-compose.yml
docker compose -f /home/misskey/misskey/docker-compose.yml pull;docker compose -f /home/misskey/misskey/docker-compose.yml up -d

echo アップデート完了しました。バージョンを記憶します。
echo $stableversion > /home/misskey/misskeystable.txt
else
echo $oldversion is latest.
dockerversion=`docker compose -f /home/misskey/misskey/docker-compose.yml images | sed -n '3p' | awk '{print $3}'`
if [[ $oldversion != $dockerversion ]] ; then
docker compose -f /home/misskey/misskey/docker-compose.yml pull;docker compose -f /home/misskey/misskey/docker-compose.yml up -d
fi
fi
```
</details>



<details><summary>arm64コンピュータDocker版：ローカルビルド重い</summary>
  
`docker-compose.yml`で
```
    image: misskey_web:latest
```
を記載

/home/misskey/misskeystable.sh
```bash:misskeystable.sh
#!/bin/bash
oldversion=`cat /home/misskey/misskeystable.txt`
stableversion=`curl --silent -X POST https://misskey.io/api/users/show -d '{"username":"misskeystable"}' | jq -r '.description'`
health=`curl --silent -I -X POST https://misskey.io/api/ping | grep HTTP | awk '{print $2}'`
if [[ $stableversion =~ 12\.+[0-9] ]] && [ $health = 200 ]; then
echo version check is ok.
versioncheck=0
else
echo version check was failed.
versioncheck=1
fi
if [ $oldversion != $stableversion ] && [ $versioncheck = 0 ]; then
echo Misskeyの安定版は${oldversion}から${stableversion}に変わりました。
echo アップデートを実行します。

echo ５分待機します。
sleep 300

su - misskey -c 'cd /home/misskey/misskey/;git fetch --tags;git reset --hard origin/develop;git checkout ${stableversion}'
docker compose -f /home/misskey/misskey/docker-compose.yml build
docker compose -f /home/misskey/misskey/docker-compose.yml up -d

echo アップデート完了しました。バージョンを記憶します。
echo $stableversion > /home/misskey/misskeystable.txt
else
echo $oldversion is latest.
fi
```
  
</details>

## Systemdサービス登録

/etc/systemd/system/misskey-auto-update.service
```systemd:/etc/systemd/system/misskey-auto-update.service
[Unit]
Description = Misskey Auto Updater

[Service]
Type = simple
User = root
WorkingDirectory = /home/misskey/
ExecStart = /bin/bash /home/misskey/misskeystable.sh
```

/etc/systemd/system/misskey-auto-update.timer
```systemd:/etc/systemd/system/misskey-auto-update.timer
[Unit]
Description = Misskey Auto Updater

[Timer]
OnBootSec=5min
OnCalendar=hourly
Persistent=false

[Install]
WantedBy=timers.target
```

`systemctl daemon-reload`  

`systemctl enable --now misskey-auto-update.timer`  
