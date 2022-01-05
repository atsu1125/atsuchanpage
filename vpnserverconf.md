うちが「インターネット無料物件」で部屋にはプライベートIPしか降ってこないため自宅鯖の公開を諦めてたんですがこれでできました  
VPS上でSoftether VPN Serverを使えるようにして、自宅鯖にVPNでトラフィックを転送する設定をします  

# 最初に：
検索でよく出てくる[物理LANカードとのローカルブリッジ]とか[SecureNAT]は使わずにVPNからインターネットへ通信を通すよ  

# 理由：
1.ふつうにローカルブリッジするとVPNのネットとVPN鯖の間で通信ができない（VPN鯖からVPNでつないだ先の自宅鯖の間で通信できない、それ以外のVPN経由でのインターネットはできる）  
2.SecureNAT使うと私の愛用するMastodonのStreamingが前触れなく切れて使い物にならない（それ以外のVPN通信は問題なさそうだった）  

# 環境：
Fedora 34, Fedora 35, CentOS Stream 8  
SoftEther Ver 4.38, Build 9760, rtm  

# Softehter基本セットアップ：
とりあえずOSの基本的な設定とSoftetherの最初のセットアップをしちゃうよ、どちらも最新版にアップデートしていこうね  
セットアップの方法は公式マニュアルと他のサイト見つつやるといいね、ポイントはsystemctlでサービスをコントロールするようにする  
/etc/systemd/system/vpnserver.service  

```php:vpnserver.service
[Unit]
Description=SoftEther VPN Server
After=network.target network-online.target

[Service]
Type=forking
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStartPost=systemctl restart dhcpd.service
ExecStop=/usr/local/vpnserver/vpnserver stop
ExecStopPost=systemctl stop dhcpd.service
Restart=always

[Install]
WantedBy=multi-user.target
```
SoftEther起動時にdhcpdを起動させてるのはSoftEtherがインターフェースを作らないと起動時にこけるっぽいのと、今回はこれ用途でしかつか使わないから同時に制御しようというもの  
5555がSoftetherで設定するときに使うポートにもなるから手っ取り早くここを最初に開けておけばWindowsのSoftether VPN Server設定を用いてGUIでセットアップができるようになるよ  
仮想HUBを作ってアカウントも作ろう  
DDNS・Azure・NATトラバーサルは必要ないからSoftetherの設定ファイルで無効化しちゃうよ  
今後のWebServerを公開するためにNginxが443で待ち受けることになるからもうSoftetherの443ポートの設定も消しちゃうよ  
今回はL2TPとOpenVPNでiOSとかからもつなげるようにするからの機能を有効化してね  
あとはfirewalldのserviceファイル作って993,1194,5555,8888,500,4500を許可してね  
/etc/firewalld/services/softether.xml  

```
<?xml version="1.0" encoding="utf-8"?>
<service>
<short>SoftetherVPN</short>
<description>Softether VPN Server</description>

<!-- TCP -->
<port protocol="tcp" port="443"/>
<port protocol="tcp" port="992"/>
<port protocol="tcp" port="1194"/>
<port protocol="tcp" port="5555"/>
<port protocol="tcp" port="8888"/>

<!-- UDP -->
<port protocol="udp" port="443"/>
<port protocol="udp" port="992"/>
<port protocol="udp" port="1194"/>
<port protocol="udp" port="5555"/>
<port protocol="udp" port="8888"/>
<port protocol="udp" port="500"/>
<port protocol="udp" port="4500"/>

<!-- UDP Speed up -->
<port protocol="udp" port="40000-44999"/>
</service>

```

# OSでブリッジデバイスの作成：
そしたらブリッジの設定をしていくよ、CentOS Stream 8はネットワークをnmcliで管理するらしい  
bridgeとしてbr0を作ってnmcliで新しいIPアドレスを固定してね、ここではtapデバイスは関係ないよ  
このVPSがVPNのネットワーク上でのルータの役割になるからね、br0を専用のセグメントにしよう、既存の他のネットワークデバイスに被らないようにする  
https://qiita.com/kanatatsu64/items/b7b8eca17202386d27e3  
が理解を助けるよ、nmcli cとnmcli dは違う概念だからね、十分に理解されよう  

```
sudo nmcli c add type bridge con-name br0 ifname br0
sudo nmcli c mod br0 ipv4.method manual ipv4.addresses 192.168.40.1/24 ipv4.gateway 192.168.40.1
```


# Softetherでtapデバイスの作成・先ほどのブリッジデバイスとSoftehter起動時にブリッジ：
そしたらSoftether VPN管理ツールからローカルブリッジで仮想HUBとSoftether上で新しく作成する仮想tapデバイスとをブリッジしてね  
そのあとさっき作ったsystemctlのsoftetherのserviceファイルに  

```php:vpnserver.service
ExecStartPost=/usr/bin/sleep 5s
ExecStartPost=/usr/sbin/ip link set dev tap_vpn（←さっき設定した任意のtapデバイス名） master br0
```
の行を追加してね、brctlは今は使わないらしくipコマンドでブリッジさせるよ  
ファイル書いたらdaemon-reloadかけてからvpnserverを再起動させるよ、ip addr showでbr0にだけIP振られているのを確認してね、  
これでこのbr0のIPでVPNのクライアントからこの鯖にローカルでつながるようになるよ  

# VPN用のDHCPサーバーの設定：
こっからはこのbr0をインターネットにつなげたい、SoftetherがやってくれてるようなDHCPサーバーを自分で作ってくよ  
確かにDHCPサーバーなくてもVPNはつながるけど、L2TPの場合はエラーになるのだ  
そのためDHCPサーバーをセットアップしてIPアドレス自動取得できるようにする  
dnfでdhcpdを入れて/etc/dhcp/dhcpd.confを書いてくよ  

```php:dhcpd.conf
authoritative;
subnet 192.168.40.0 netmask 255.255.255.0 {
range 192.168.40.20 192.168.40.200;
option domain-name-servers 1.1.1.2, 1.0.0.2;
option routers 192.168.40.1;
option broadcast-address 192.168.40.255;
default-lease-time 28800;
max-lease-time 43200;
}

```
基本は標準的なルータと同じように簡単に書いてあげればよし、デフォルトゲートウェイはbr0のIPになるし  
br0と同じサブネットになっていればOK、DNSサーバーはパブリックDNSの1.1.1.1とか入れとくといい  
これも自動起動できるようにsystemctlにサービス登録しておこう  

For Fedora 35

```md:dhcpd.service
ExecStart=/usr/sbin/dhcpd -f -cf /etc/dhcp/dhcpd.conf -user dhcpd -group dhcpd --no-pid br0 $DHCPDARGS
```
ExecStartの部分だけ最後に`br0`などインターフェース名を書かないと起動に失敗するので追記しておく  

# NAT（マスカレード）の設定：
そしたら次にNATを設定していく、IPマスカレードってやつができればいい  
インターフェースのファイアーウォールゾーンをbr0をinternalに変更してやる  

```
sudo firewall-cmd --add-masquerade --permanent
sudo firewall-cmd --add-masquerade --permanent --zone=internal
sudo firewall-cmd --zone=internal --change-interface=br0 --permanent
```
For Fedora 35

```
sudo firewall-cmd --add-masquerade --permanent
sudo firewall-cmd --zone=internal --change-interface=br0 --permanent
sudo firewall-cmd --permanent --new-policy policy_int_to_ext
sudo firewall-cmd --permanent --policy policy_int_to_ext --add-ingress-zone internal
sudo firewall-cmd --permanent --policy policy_int_to_ext --add-egress-zone FedoraServer
sudo firewall-cmd --permanent --policy policy_int_to_ext --set-priority 100
sudo firewall-cmd --permanent --policy policy_int_to_ext --set-target ACCEPT
```

変更するとfirewallの設定が変わるからsshが切れないようにはしてね
そしてfirewall-cmdでデフォルトとinternalの両方のゾーンにマスカレードを有効化する、これだけで十分
設定ができたら、既存のsshは閉じずに新しくsshとか開いて接続が通ってるか確認してね、ダメだったらfirewall-cmdで見直す
firewallがダメな状態で既存のSSH切るともうつながらなくなるからね

# VPNサーバー設定最終確認：
これまでの手順ができてたら試しにWindowsのsoftetherクライアントからVPN Serverに接続するとウィンドウが出てきて  
VPSのDHCPサーバーからdhcpでIPアドレス・デフォルトゲートウェイなどが自動取得されてくるはず  
詳しいネットワーク情報はipconfig /allで確認できるね、私はMS-DOSわからんのでもっといい方法あるかもしれない  
あとはインターネットに繋がるか適当にブラウザ開いて確認するといい、Windowsの場合はSoftether Clientで接続設定すると  
VPNのインターフェースが勝手にデフォルトゲートウェイになるからその辺の設定が不要で楽だね  
これでVPNのサーバーの設定はできたかなと思う  

# 自宅鯖でVPN Client設定：
あとは自宅鯖側でSoftetherのVPN Clientをインストールして構成して通るか確かめる  
この設定が面倒なのだが、適宜各自の自宅鯖のOSに合わせて設定してみて欲しい  
VPN Clientの設定もインストール後にサービス起動までできれば、  
あとはSoftether VPN Clientのリモート設定を有効化するコマンドを打ってやれば、WindowsのSoftether VPNのリモート設定ソフトからGUIで設定ができる  
正常にVPN接続ができるようになったら、自宅鯖はDHCP自動取得ではなくIPを固定して  
毎回システム起動時にSoftetherが起動してVPNに自動でつながるように設定する、そうしないと再起動時に自宅鯖につながらなくなる  
それでとりあえず、自宅鯖とVPNサーバーの常時VPN接続設定はOK  

# VPSから自宅鯖へトラフィックを転送：
VPSでNginx入れてstreamディレクティブに転送したいポートを書いたり、httpディレクティブにリバースプロキシの設定書いてやる  
Nginxのリバースプロキシはフルの理解できてないのだけどなんかがんばればできる  
nginx/nginx.confにはこれ追加  

```php:nginx.conf
stream {
        include /etc/nginx/stream/*.conf;
}
```
httpディテクティブでリバースプロキシを書く方法はいろいろあると思うけど無難にproxy_passで設定する  

```php:exaple-com.conf
    server {
    server_name example.com; # managed by Certbot

        location / {
            proxy_pass http://192.168.50.10:3001;
            proxy_set_header X-Real-IP $remote_addr;
            index index.html index.htm;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
            proxy_redirect off;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_cache_bypass $http_upgrade;
        }
    client_max_body_size 16G;
    listen [::]:443 ssl; # managed by Certbot
    listen 443 ssl; # managed by Certbot

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem; # managed by Certbot
}

    server {
    if ($host = example.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

       	listen       80 ;
        listen       [::]:80 ;
    server_name example.com;
    return 404; # managed by Certbot
}

```
streamの設定はhttpディレクティブで使用してないフォルダを作ってconf入れてね  
転送先はVPNの先の自宅鯖だからproxy passにIPアドレスを書いてあげる  
streamディレクティブはこんな感じのconfファイルnginx/stream/ssh2.confとかで書くのだ  
nginx-mod-streamが入ってないとエラーになるのでインストールしてね  

```php:ssh2.conf
  upstream ssh2 {
    server 192.168.40.103:22;
  }
  server {
    listen 2223;
    proxy_pass    ssh2;

  }
```
firewall-cmdでVPS上のexternal, internalのそれぞれのゾーンで開放したいポートを開ければOK  
適宜設定すればVPSのホスト名で自宅鯖へ直接sshやhttpが通るはず、これで自宅鯖を公開できたね  

# 留意点：
自宅鯖のデフォルトゲートウェイはおそらくご家庭のLANになっていると思うので、自宅鯖からPostfixでメールを送ったりするとOP25Bとspfに引っかかって送信できないということが起こる、ここはMailjetとかSendgridをご利用になって回避するのが賢いかなあと、メールの送信だけVPS経由にしてもいいけど、最近はVPSもOP25Bあったりするらしいからねえ  
