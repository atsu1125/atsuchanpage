Mastodonって結構容量食うよね。  
リモートのメディアファイルをローカルにキャッシュするからオブジェクトストレージ使ってないとすぐいっぱいになる。  
よくディスクフルになって落ちてるインスタンスがあるので今回はそれに対処するスクリプトを書いてみました。  
本当にこれでいいかとは思うのですがこれで動作しましたのでここに記します。  
これを基に改良していくのがいいんじゃないかしら、一応動作テストはしたけどベータ版みたいに思ってもらって。  
作業環境はOSがFedora 34でMastodonはv3.4.1です。
追記：Debian bullseyeでMastodonがv3.4.8でも動作確認済み。

# スクリプト
days, size, access_token, instance_domain, visibility, hashtag1, hashtag2については変数なので諸々で変えてください。  
ディスク全体の容量取得はデバイスのパス（/dev/sda1）が違うかもしれないので変更していただきたい。  
このスクリプトをmastodonユーザーのホームディレクトリにでも入れてください。  
ちなみにお分かりの通り結果はmastodonにそのまま投稿させます。  
ブラウザから投稿したいMastodonアカウントでログインして、  
Mastodon Web UIの設定からアプリケーションを作成してアクセストークンを入手してください。  
つってもこれで間違ってデータ消したら困るからバックアップは取るにして、  
最初からmastodonのtootctlを実行しないように、  
RAILS_ENVなんたらとcurlの行だけコメントインして実行して見て、  
sizeの値を変えたりしてechoの出力を見てwhileの文が大丈夫そうだなと思ったらコメントアウトすればいいと思うわよ。  

```bash:mastodon-media-remove-adv.sh
#!/bin/bash
#Mastodonメディア使用量取得・変数定義
cd /home/mastodon/live
ATTACHMENTS=`RAILS_ENV=production ~/.rbenv/shims/bundle exec bin/tootctl media usage | grep Attachments | awk '{print $2}' | awk '{printf("%d\n",$1)}'`
days=182 #何日前のデータから削除開始するか
if [ -e /home/mastodon/days.txt ]; then
days=`cat /home/mastodon/days.txt` #もし前回実行データあるならこれを見る
fi
size=20 #何ギガバイトまで許容するか
access_token="アクセストークン入れる" #Mastodonで作成したアプリのアクセストークン
instance_domain=atsuchan.page
visibility=public
hashtag1=#bot
hashtag2=#atsuchan_page

#ATTACHMENTSが{size}GBよりも多いなら日数を減じて削除を繰り返す・それ以外なら終了しMastodonに報告する
while :
do
  if ((ATTACHMENTS > ${size})) && ((days > 0)) ; then
    echo "${ATTACHMENTS}GBのため${days}日前までのメディア削除実行"
    RAILS_ENV=production ~/.rbenv/shims/bundle exec bin/tootctl media remove --days=${days};RAILS_ENV=production ~/.rbenv/shims/bundle exec bin/tootctl preview_cards remove --days=${days}
    days=`expr $days + -1`
    ATTACHMENTS=`RAILS_ENV=production ~/.rbenv/shims/bundle exec bin/tootctl media usage | grep Attachments | awk '{print $2}' | awk '{printf("%d\n",$1)}'`
    echo "${days}日前までの削除を完了"
  else
    echo "${ATTACHMENTS}GBにつきメディア削除実行なし"
    echo ${days} > /home/mastodon/days.txt
    DISKSPACE=`df -h -l | grep /dev/vda1 | awk '{print $4}'`
    curl -X POST \
         -d "status=Mastodonメディア使用量は${ATTACHMENTS}GBです。${days}日間までのリモートメディアファイルを保持しています。ディスク全体の空き容量は${DISKSPACE}Bです。 ${hashtag1} ${hashtag2}" \
         -d "visibility=${visibility}" \
         --header "Authorization: Bearer ${access_token}" \
         -sS https://${instance_domain}/api/v1/statuses
    break
  fi
done

exit 0
```

For docker environment
```bash:mastodon-media-remove-adv.sh
#!/bin/bash
#Mastodonメディア使用量取得・変数定義
cd /home/mastodon #dockerディレクトリ
ATTACHMENTS=`docker-compose run --rm web bundle exec bin/tootctl media usage | grep Attachments | awk '{print $2}' | awk '{printf("%d\n",$1)}'`
days=150 #何日前のデータから削除開始するか
if [ -e /home/mastodon/days.txt ]; then
days=`cat /home/mastodon/days.txt` #もし前回実行データあるならこれを見る
fi
size=50 #何ギガバイトまで許容するか
#ATTACHMENTSが{size}GBよりも多いなら日数を減じて削除を繰り返す・それ以外なら終了
while :
do
  if ((${ATTACHMENTS} > ${size})) && ((${days} > 0)) ; then
    docker-compose run --rm web bundle exec bin/tootctl media remove --days=${days};docker-compose run --rm web bundle exec bin/tootctl preview_cards remove --days=${days}
    days=`expr ${days} + -1`
    ATTACHMENTS=`docker-compose run --rm web bundle exec bin/tootctl media usage | grep Attachments | awk '{print $2}' | awk '{printf("%d\n",$1)}'`
    echo "${days}日前までの削除を完了"
  else
    echo "${ATTACHMENTS}GBにつきメディア削除実行終了"
    echo ${days} > /home/mastodon/days.txt
    break
  fi
done
exit 0
```


# 自動化
これを自動で定期的に走らせないといけないのでサービス化してcron.dailyで実行させます  
これは`/etc/cron.daily`内に置く（crondサービスが自動で開始する設定になってるか、anacronが入ってるかなどはチェックしてね、置くだけではアレ）  
そしてパーミッションがrootで実行権限あるか確認してね  

```bash:mastodon-media-remove-adv
#!/bin/bash
systemctl start mastodon-media-remove-adv.service
```

これは`/etc/systemd/system`内に置く、保存したら`systemctl daemon-reload`してね  

```systemd:mastodon-media-remove-adv.service
[Unit]
Description = Mastodon old media remove

[Service]
Type = onehost
User = mastodon
WorkingDirectory = /home/mastodon
ExecStart = /usr/bin/bash -c 'bash /home/mastodon/mastodon-media-remove-adv.sh'
#ExecStartPost = curl "heartbeat用のURLを書く" #もしbetteruptimeとかでcronが実行されたか監視したいなら
```

これでとりあえずいいんじゃないかしら。  
あとは  

```
sudo bash /etc/cron.daily/mastodon-media-remove-adv
```
して、Mastodonにトゥートされたか確認したり  

```bash
sudo journalctl -u mastodon-media-remove-adv.service -f
```
あたりでログを見てやるといいわよ。  

# あとがき
スマートじゃないなあと思うのはAttachments以外の容量を考慮していないこととDBが肥大した場合のディスクフルなどはどうしようもない  
