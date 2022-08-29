## 環境
OS: Debian Bullseye, CentOS 7  
Software version: mongoDB Community Edition 5.0.10  
mongoDBを使用しているアプリケーションはめいすきーです。  
https://github.com/atsu1125/misskey  
個人的にとても優れたオープンソースのSNSソフトウェアなのでおすすめです。  
が基本的にはmongoDBの利用するソフトウェア全て向けに書いています。  

## はじめに
Misskey v10, めいすきーインスタンスを運営のみなさん  
mongoDBのレプリケーションは設定されていますか？  
PostgreSQLであればWALを書き出してポイントインリカバリとかできるので  
https://qiita.com/atsu1125/items/676d24c0473ad94b3f2b  
ぶっちゃけレプリケーションなんか要らんと思いつつレプリケーションしてるんですが、mongoDBはポイントインリカバリに使えるようなログを書き出すことはできないです。  
Oplogを保管できますが、これはWALと異なり時系列が保証されてないのでポイントインリカバリには使えないです。  
つまりmongodumpで出力した時点までしか戻ることが困難ということです。  
SNSでなければマネージドを使うとポイントインリカバリもバックアップも楽なんですが、SNSの場合はSQLを大量に叩くのでオンプレミスでないと速度が遅くてきついものがあります。  
そのためバックアップはmongodumpを別途設定してもらうとして、今回は別のサーバーにレプリケーションをする設定をしたいと思います。

## mongoDBのレプリケーションの仕組み
レプリケーション全体で最低でも同バージョンのmongoDBが動く３台のサーバーが必要です。  
１台のプライマリと２台のセカンダリという構成が一般的です。  
それ以外の設定も可能ですが今回はこの構成にします。  
ちなみに２台だけで組むと一度プライマリがダウンしたあともう一度起動しても１台もプライマリにならずに終わります。  
PostgreSQLでは自動でフェイルオーバーしないんですが、  
mongoDBは自動的にプライマリをレプリカセットのサーバーから多数決で選出するため、最初はセカンダリとして起動して、優先度とステータスに応じて１台のみプライマリに自動昇格します。  
この際にレプリカセットのサーバーが２台だけだとフィフティフィフティになって多数決が成立しないため、２台ともセカンダリとして待機したままになります。  


なお、レプリケーションは間違ったオペレーションも含めて全て同期するので、オペレーションミス・サイバー攻撃に対応するためのバックアップには使えません。あくまでマシンの物理故障の対応です。  


## ホスト名の設定
ここでホスト名なんか出てくるのがびっくりですが、これは非常に大事な設定です。  
基本的に内部向けDNSサーバーを建ててレプリケーションを組むサーバー同士をホスト名で解決できるようにしてください。  
ゼロトラストセキュリティとかで外部のDNSサーバーを利用しており、内部向けDNSを使えない場合は、`/etc/hosts`にホスト名とIPアドレスの対応を各サーバーに書いてください。  
mongoDB 5.0以降からはIPアドレスベースでのレプリケーションは使用できなくなりました。できそうに見えるんですが、mongodbでステータスを取得すると`STARTUP`のままになって終わります。  
`STARTUP2`が正常にデータを受信して初期同期を始める状態です。紛らわしいね。  

## ファイヤーウォールの設定
サーバーのファイヤーウォールでレプリケーションサーバー同士の接続を許可します。
以下の要領で環境に合わせて設定してください。  
え、LANなんだからルーターでブロックしてくれるからファイヤーウォールなんて置いてない？  
セキュリティのために設置しておくことを強くお勧めします。  
特に今回はmongoDBを`0.0.0.0`でlistenさせるのでファイヤーウォールくらいしか守れるところがありません。  

for ufw
```
ufw allow from xxx.xxx.xxx.xxx to any port 27017 proto tcp`
```

for firewalld
```
firewall-cmd --add-rich-rule='rule family=ipv4 source address=xxx.xxx.xxx.xxx/32 port port=27017 protocol=tcp accept' --permanent
firewall-cmd --reload
```

## mongoDBの認証設定

最初にセキュリティのためにデータベースのユーザー認証を有効化してください。 
このユーザー認証は最初にレプリカセットでプライマリになるサーバーのみで設定します。   
以下の記事が詳しいです。  

MongoDB ユーザー認証設定は必ずしましょう by @h6591  
https://qiita.com/h6591/items/68a1ec445391be451d0d

ユーザー認証を設定したらmongoDBを使うアプリケーションで設定を反映してからmongoDBを再起動するとよいです。  

設定したらレプリケーションの認証に使うキーファイルを生成します。
```bash:/etc/mongodbkeyfile
openssl rand -base64 1024 > mongodbkeyfile
```
これを`/etc/mongodbkeyfile`とかに移動してください。
パーミッションは所有者が
CentOSの場合`mongod`で
Debianの場合`mongodb`で
所有者のみ読めるようにしましょう。

そしてmongod.confにて以下の設定を追記変更してください。

```bash:/etc/mongod.conf
net:
  port: 27017
  bindIp: 0.0.0.0

security:
  authorization: enabled
  keyFile: /etc/mongodbkeyfile

replication:
  replSetName: "replicaset0"
```

これらのキーファイルと設定を各レプリケーションサーバーに配置してください。  
設定できたら`systemctl restart mongod`で全サーバーを再起動してください。  

## mongoDBのレプリケーション設定

最初にレプリカセットのプライマリになるサーバーに対して接続します。ユーザー認証が効いてるので以下のコマンドでログインしないと接続できないはずです。ユーザー名と認証データベースは適宜合わせてください。  

```
mongo --authenticationDatabase admin -u mongo
```

接続しましたら以下を入力をします。  
ワンライナーじゃないですがちゃんと入力できます。  
`mongodbserver1.local`などの部分は各自のサーバーのホスト名で置き換えてください。  
今回はフェイルオーバーを意図的に無効化して設定しています。  
id:0に最初にプライマリとなるサーバーとして現在操作してるサーバーのホスト名を登録してください。
idが0のサーバーが必ずプライマリに選ばれるように他のサーバーはhidden memberとしてプライマリに昇格しないよう登録しています。  
おそらく特別な設定をしてない限りはプライマリが変わった時にアプリケーションの方で繋ぎ変えられないので、仕方ないです。  

```
rsconf = {
  _id: "replicaset0",
  members: [
    {
     _id: 0,
     host: "mongodbserver1.local:27017",
     "priority" : 10
    },
    {
     _id: 1,
     host: "mongodbserver2.local:27017",
     "hidden" : true,
     "priority" : 0
    },
    {
     _id: 2,
     host: "mongodbserver3.local:27017"
     "hidden" : true,
     "priority" : 0
    }
   ]
}
```
返ってきた内容を確認して問題なければ
```
rs.initiate( rsconf )
```
でレプリカセットの設定を反映します。  
だいぶ変わった設定方法ですが、これに慣れてください。  

```
rs.conf()
```
で現在のレプリケーションの設定が確認できます。
```
rs.status()
```
で現在のレプリケーションの状態が見れます。  
`stateStr`が`PRIMARY`のサーバーが１台あって、`SECONDARY`もしくは`STARTUP2`のサーバーが２台あれば成功です。  
`STARTUP`のサーバーがある場合は接続に失敗してるのでプロセスが生きてるか、ファイヤーウォールが許可しているか、設定ファイルが適当かを確認してください。  

## MongoDBのレプリケーションの監視
ただレプリケーションを組むだけではダメで、きちんと機能してるかを確認しましょう。  
MongoDBにログインした時に出る`Free Monitoring URL:`はどこからでも見られて便利です。  
そしてレプリケーションが失敗してる際には通知をくるようにしたいです。  
今回はシェルスクリプトとsystemd timerで構築します。  
`rs.status()`でレプリケーションの状態が取得でき、１台が`PRIMARY`で２台が`SECONDARY`な状態が正常なわけです。  
雑ではありますがこの文字列の件数をカウントすればいいんじゃないかと思います。  
その上で正常であることを常にハートビート監視用のURL（BetterUptimeとかいいと思う）に投げれば監視スクリプトが落ちても気づきます。  
それで失敗した際はすぐに通知欲しいのでDiscordに対してWebHookで通知を飛ばします。  
まずはdiscord.shっていう便利なものを入れます。
```
wget https://github.com/ChaoticWeg/discord.sh/raw/master/discord.sh
chmod +x discord.sh
mv discord.sh /usr/local/bin/
```
依存関係のjqとcurlを入れます。  
for Debian
```
apt install jq curl
```
for CentOS
```
yum install jq curl
```
それで`discord.sh`を叩いて実行できればOKです。
次に以下のシェルスクリプトを作成します。


```bash:/usr/local/bin/mongo-replica-monitor.sh
#!/bin/bash
PRIMARY=`mongo --authenticationDatabase admin -u mongo -p パスワード --eval "printjson(rs.status())" | grep -c PRIMARY`
SECONDARY=`mongo --authenticationDatabase admin -u mongo -p パスワード --eval "printjson(rs.status())" | grep -c SECONDARY`
if [ $PRIMARY = 1 ] && [ $SECONDARY -ge 2 ] ; then
echo "streaming replication is healthy"
curl ハートビート監視のURL #正常性報告
if [ -e error-replication.txt ]; then
WEBHOOK_URL="DISCORDのWEBHOOKURL"
discord.sh \
    --webhook-url "$WEBHOOK_URL" \
    --username "Streaming Replication Notice" \
    --title "Streaming Replication Notice" \
    --description "ストリーミングレプリケーションは正常に復帰しました。"

rm -f error-replication.txt
exit 0
fi
else
echo "streaming replication is unhealhy"
if [ ! -e error-replication.txt ]; then
WEBHOOK_URL="DISCORDのWEBHOOKURL"
discord.sh \
    --webhook-url "$WEBHOOK_URL" \
    --username "Streaming Replication Notice" \
    --title "Streaming Replication Notice" \
    --description "ストリーミングレプリケーションに異常発生しました。"

touch error-replication.txt
fi
fi
```

こんな感じで書いてあげたら  
以下のサービスファイルを`systemctl edit --full --force mongodb-monitor.service`で登録し

```systemd:mongodb-monitor.service
[Unit]
Description = Check replication state

[Service]
Type = oneshot
User = root
WorkingDirectory = /usr/local/bin/
ExecStart = bash /usr/local/bin/mongo-replica-monitor.sh
```
以下のタイマーファイルを`systemctl edit --full --force mongodb-monitor.timer`で登録し  
`systemctl enable --now mongodb-monitor.timer`で開始

```systemd:mongodb-monitor.timer
[Unit]
Description = Check Replication State

[Timer]
OnBootSec=3min
OnUnitActiveSec=1m
Persistent=false

[Install]
WantedBy=timers.target
```

あとは`systemctl status mongodb-monitor.service`で状態を確認。  
うまく動いてればOKです。  
エラーになってたら`journalctl -u mongodb-monitor.service`で確認。  

## おわりに
mongoDBのレプリケーション設定がバージョン4向けが多くて結構ハマりました。  
そしてレプリケーションがいつの間にか落ちていてデータを失った知り合いもいたので、  
今回は稚拙ですがレプリケーションの監視まで書いておきました。  
お役に立てればうれしいです。  
