うちが「インターネット無料物件」で部屋にはプライベートIPしか降ってこないため自宅鯖の公開を諦めてたんですがこれでできました
VPS上でSoftether VPN Serverを使えるようにして、自宅鯖にVPNでトラフィックを転送する設定をします

# 最初に：
検索でよく出てくる[物理LANカードとのローカルブリッジ]とか[SecureNAT]は使わずにVPNからインターネットへ通信を通すよ

# 理由：
1.ふつうにローカルブリッジするとVPNのネットとVPN鯖の間で通信ができない（VPN鯖からVPNでつないだ先の自宅鯖の間で通信できない、それ以外のVPN経由でのインターネットはできる）
2.SecureNAT使うと私の愛用するMastodonのStreamingが前触れなく切れて使い物にならない（それ以外のVPN通信は問題なさそうだった）

# 環境：
Fedora 34, Fedora 36, CentOS Stream 8, Ubuntu 22.04, Debian bullseye(2022/8/23にDebain系対応しました🎉)
SoftEther Ver 4.38 Build 9760 rtm
SoftEther VPN 4.39 Build 9772 Beta
192.168.40.0/24をVPNネットワークとして構築する
VPNサーバー（VPS側）は192.168.40.1、VPNクライアント（自宅鯖）は192.168.40.2を割り当て
ファイヤーウォールにfirewalldかufwを使用(2023/2/1にufw対応しました🎉)
NginxはVPS側に設置する、自宅鯖に持ってくることもできる

# Softehter基本セットアップ：
とりあえずOSの基本的な設定とSoftetherの最初のセットアップをしちゃうよ、どちらも最新版にアップデートしていこうね
セットアップの方法は公式マニュアルと他のサイト見つつやるといいね、ポイントはsystemctlでサービスをコントロールするようにする


for Fedora 36
```systemd:/etc/systemd/system/vpnserver.service
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

for Ubuntu 20.04
```systemd:/etc/systemd/system/vpnserver.service
[Unit]
Description=SoftEther VPN Server
After=network.target network-online.target

[Service]
Type=forking
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStartPost=systemctl restart isc-dhcp-server.service
ExecStop=/usr/local/vpnserver/vpnserver stop
ExecStopPost=systemctl stop isc-dhcp-server.service
Restart=always

[Install]
WantedBy=multi-user.target
```

SoftEther起動時にdhcpdを起動させてるのはSoftEtherがインターフェースを作らないと起動時にこけるっぽいのと、今回はこれ用途でしか使わないから同時に制御しようというもの
5555がSoftetherで設定するときに使うポートにもなるから手っ取り早くここを最初に開けておけばWindowsのSoftether VPN Server設定を用いてGUIでセットアップができるようになるよ
仮想HUBを作ってアカウントも作ろう
DDNS・Azure・NATトラバーサルは必要ないからSoftetherの設定ファイルで無効化しちゃうよ
今後のWebServerを公開するためにNginxが443で待ち受けることになるからもうSoftetherの443ポートの設定も消しちゃうよ
今回はL2TPとOpenVPNでiOSとかからもつなげるようにするからの機能を有効化してね
あとはfirewalldのserviceファイル作って992,1194,5555,8888,500,4500を許可してね

for firewalld
```xml:/etc/firewalld/services/softether.xml
<?xml version="1.0" encoding="utf-8"?>
<service>
<short>SoftetherVPN</short>
<description>Softether VPN Server</description>

<!-- TCP -->
<port protocol="tcp" port="992"/>
<port protocol="tcp" port="1194"/>
<port protocol="tcp" port="5555"/>
<port protocol="tcp" port="8888"/>

<!-- UDP -->
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

for ufw
```bash
ufw allow 5555
ufw allow 8888
ufw allow 992
ufw allow 1194
ufw allow 500/udp
ufw allow 4500/udp
```

# OSでブリッジデバイスの作成：
そしたらブリッジの設定をしていくよ、CentOS Stream 8はネットワークをnmcliで管理するらしい、Ubuntuはbrctl使うのでインストールのみ
bridgeとしてbr0を作ってnmcliで新しいIPアドレスを固定してね、ここではtapデバイスは関係ないよ
このVPSがVPNのネットワーク上でのルータの役割になるからね、br0を専用のセグメントにしよう、既存の他のネットワークデバイスに被らないようにする

For Fedora 36

```bash
sudo nmcli c add type bridge con-name br0 ifname br0
sudo nmcli c mod br0 ipv4.method manual ipv4.addresses 192.168.40.1/24 ipv4.gateway 192.168.40.1
sudo nmcli c up br0
```

For Ubuntu 20.04

```bash
sudo apt install bridge-utils
```
Ubuntuはこれインストールするだけ

# Softetherでtapデバイスの作成・先ほどのブリッジデバイスとSoftehter起動時にブリッジ：
そしたらSoftether VPN管理ツールからローカルブリッジで仮想HUBとSoftether上で新しく仮想tapデバイス作成してブリッジしてね
そのあとさっき作ったsystemctlのsoftetherのserviceファイルに

For Fedora 36

```systemd:/etc/systemd/system/vpnserver.service
#ExecStartPost=systemctl restart dhcpd.service の前に追記
ExecStartPost=/usr/bin/sleep 5s
ExecStartPost=/usr/sbin/ip link set dev tap_vpn（←さっき設定した任意のtapデバイス名） master br0
```

For Ubuntu 20.04

```systemd:/etc/systemd/system/vpnserver.service
#ExecStartPost=systemctl restart isc-dhcp-server.service の前に追記
ExecStartPost=/usr/bin/sleep 5s
ExecStartPost=/usr/bin/bash -c '/usr/sbin/brctl addbr br0;/usr/sbin/ip link set dev tap_vpn master br0;/usr/sbin/ip link set dev br0 up;/usr/sbin/ip addr add 192.168.40.1/24 dev br0'

#ExecStopPost=systemctl stop isc-dhcp-server.service　の後に追記
ExecStopPost=/usr/bin/bash -c '/usr/sbin/ip link set dev br0 down;/usr/sbin/brctl delbr br0'
```
の行を追加してね、RHEL8系だとbrctlは今は使わないらしくipコマンドでブリッジさせるよ、Ubuntuはbrctl使うので起動時の処理でブリッジする
ファイル書いたら`systemctl daemon-reload`かけてからvpnserverを再起動させるよ、`ip a`でbr0にだけIPv4アドレス振られているのを確認してね、これでこのbr0のサブネットでVPNのクライアントからこのVPSにLANと同じようにつながるようになるよ

# VPN用のDHCPサーバーの設定：
こっからはこのbr0をインターネットにつなげたい、SoftetherがセキュアNATでやってくれてるようなDHCPサーバーを自分で作ってくよ
確かにDHCPサーバーなくてもVPNはつながるけど、L2TPの場合はエラーになるのだ
そのためDHCPサーバーをセットアップしてIPアドレス自動取得できるようにする
dnfでdhcpdを入れて/etc/dhcp/dhcpd.confを書いてくよ

```conf:dhcpd.conf
authoritative;
subnet 192.168.40.0 netmask 255.255.255.0 {
range 192.168.40.2 192.168.40.200;
option domain-name-servers 1.1.1.2, 1.0.0.2;
option routers 192.168.40.1;
option broadcast-address 192.168.40.255;
default-lease-time 28800;
max-lease-time 43200;
}

```
基本は標準的なルータと同じように簡単に書いてあげればよし、デフォルトゲートウェイはbr0のIPになるし
br0と同じサブネットになっていればOK、DNSサーバーはパブリックDNSの1.1.1.1とか入れとくといい
これも自動起動できるようにsystemctlにサービス登録しておこう(`systemctl enable --now dhcpd` or `systemctl enable --now isc-dhcp-server`)

For Fedora 35, Fedora 36 and ubuntu 22.04

```conf:/etc/dhcp/dhcpd.conf
DHCPDARGS="br0";
```
`br0`などインターフェース名を書かないと起動に失敗するので追記しておく

# NAT（マスカレード）の設定：
そしたら次にNATを設定していく、IPマスカレードってやつができればいい
インターフェースのファイアーウォールゾーンをbr0をinternalに変更してやる

For Fedora 34 firewalld

```sh
sudo firewall-cmd --add-masquerade --permanent
sudo firewall-cmd --add-masquerade --permanent --zone=internal
sudo firewall-cmd --zone=internal --change-interface=br0 --permanent
```

For Fedora 35, Fedora 36 and Ubuntu 22.04 firewalld

```sh
sudo firewall-cmd --add-masquerade --permanent
sudo firewall-cmd --zone=internal --change-interface=br0 --permanent
sudo firewall-cmd --permanent --new-policy policy_int_to_ext
sudo firewall-cmd --permanent --policy policy_int_to_ext --add-ingress-zone internal
sudo firewall-cmd --permanent --policy policy_int_to_ext --add-egress-zone public
#(デフォルトのゾーン：FedoraServerかpublicな気がする)
sudo firewall-cmd --permanent --policy policy_int_to_ext --set-priority 100
sudo firewall-cmd --permanent --policy policy_int_to_ext --set-target ACCEPT
```

変更するとfirewallの設定が変わるからsshが切れないようにはしてね
そして`firewall-cmd`でデフォルトとinternalの両方のゾーンにマスカレードを有効化する、これだけで十分
設定ができたら、既存のsshは閉じずに新しくsshとか開いて接続が通ってるか確認してね、ダメだったら`firewall-cmd`で見直す
firewallがダメな状態で既存のSSH切るともうつながらなくなるからね

For ufw

```
sudo nano /etc/default/ufw
```

```sh:/etc/default/ufw
 DEFAULT_FORWARD_POLICY="ACCEPT"
```

```
sudo nano /etc/sysctl.conf 
```

```sh:/etc/sysctl.conf
net.ipv4.ip_forward=1
```

```
sudo sysctl -p
```

```
sudo nano /etc/ufw/before.rules
```

```
# NAT
*nat
-F
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.40.0/24 -o eth0 -j MASQUERADE
#たぶん外部インターフェースがeth0かどうかは環境によって違うので適宜変更

COMMIT
```

```
sudo ufw reload
```


# VPNサーバー設定最終確認：
これまでの手順ができてたら試しにWindowsのsoftetherクライアントからVPN Serverに接続するとウィンドウが出てきて
VPSのDHCPサーバーからdhcpでIPアドレス・デフォルトゲートウェイなどが自動取得されてくるはず
詳しいネットワーク情報は`ipconfig /all`で確認できるね、私はMS-DOSわからんのでもっといい方法あるかもしれない
あとはインターネットに繋がるか適当にブラウザ開いて確認するといい、Windowsの場合はSoftether Clientで接続設定すると
VPNのインターフェースが勝手にデフォルトゲートウェイになるからその辺の設定が不要で楽だね
これでVPNのサーバーの設定はできたかなと思う

# 自宅鯖でVPN Client設定：
あとは自宅鯖側でSoftetherのVPN Clientをインストールして構成して通るか確かめる
この設定が面倒なのだが、適宜各自の自宅鯖のOSに合わせて設定してみて欲しい
VPN Clientの設定もインストール後にサービス起動までできれば、あとは`./vpncmd`を使ってRemoteEnable, PasswordSetを設定して、ファイヤーウォールで9930/tcpを許可すると
WindowsのSoftether VPNのリモート設定ソフトからGUIで設定ができる、
正常にVPN接続ができるようになったら、自宅鯖はDHCP自動取得ではなくIPを固定して
毎回システム起動時にSoftetherが起動してVPNに自動でつながるように「スタートアップ接続」を設定する、そうしないと再起動時に自宅鯖につながらなくなる
それでとりあえず、自宅鯖とVPNサーバーの常時VPN接続設定はOK
あとはTCPコネクション数をデフォルトの1から8に増やすとか、IPv6で接続してみるとかすると、速度が向上するはず

### たとえばFedora 36なら
SoftEtherクライアントを入れて

```bash
sudo nmcli c add type bridge con-name br1 ifname br1
sudo nmcli c mod br1 ipv4.method manual ipv4.addresses 192.168.40.2/24 ipv4.gateway 192.168.40.1
sudo nmcli c up br1
```
でブリッジデバイス作って、`./vpncmd`で設定情報を投入したら

```systemd:/etc/systemd/system/vpnclient.service
[Unit]
Description=SoftEther VPN Client
After=network.target network-online.target

[Service]
Type=forking
ExecStart=/usr/local/vpnclient/vpnclient start
ExecStartPost=/usr/bin/sleep 5s
ExecStartPost=/usr/sbin/ip link set dev vpn_vpn master br1
ExecStop=/usr/local/vpnclient/vpnclient stop
Restart=always

[Install]
WantedBy=multi-user.target
```
ってサービスファイルで動く

### たとえばDebian Bullseyeなら
SoftEtherクライアントと`bridge-utils`を入れて、接続情報を`./vpncmd`とかで投入したら
```systemd:/etc/systemd/system/vpnclient.service
[Unit]
Description=SoftEther VPN Client
After=network.target network-online.target

[Service]
Type=forking
ExecStart=/usr/local/vpnclient/vpnclient start
ExecStartPost=/usr/bin/sleep 5s
ExecStartPost=/usr/bin/bash -c '/usr/sbin/brctl addbr br1;/usr/sbin/ip link set dev vpn_vpn master br1;/usr/sbin/ip link set dev br1 up;/usr/sbin/ip addr add 192.168.40.2/24 dev br1'
ExecStop=/usr/local/vpnserver/vpnclient stop
ExecStopPost=/usr/bin/bash -c '/usr/sbin/ip link set dev br1 down;/usr/sbin/brctl delbr br1'
Restart=always

[Install]
WantedBy=multi-user.targe
```
ってサービスファイル書けば動く

# VPSから自宅鯖へトラフィックを転送：
VPSでNginx入れてstreamディレクティブに転送したいポートを書いたり、httpディレクティブにリバースプロキシの設定書いてやる
Nginxのリバースプロキシはフルの理解できてないのだけどなんかがんばればできる
nginx/nginx.confにはこれ追加

```nginx:/etc/nginx/nginx.conf
stream {
        include /etc/nginx/stream/*.conf;
}
```
httpディテクティブでリバースプロキシを書く方法はいろいろあると思うけど無難にproxy_passで設定する

```nginx:/etc/nginx/conf.d/exaple-com.conf
    server {
    server_name example.com;

        location / {
            proxy_pass http://192.168.40.2:3001;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
        }
    listen [::]:443 ssl;
    listen 443 ssl;
}

```
streamの設定はhttpディレクティブで使用してないフォルダを作ってconf入れてね
転送先はVPNの先の自宅鯖だから`proxy pass`にIPアドレスを書いてあげる
streamディレクティブはこんな感じのconfファイル`nginx/stream/ssh.conf`とかで書くのだ
nginx-mod-streamが入ってないとエラーになるのでインストールしてね

```nginx:/etc/nginx/stream/ssh.conf
  upstream ssh {
    server 192.168.40.2:22;
  }
  server {
    listen 2222;
    proxy_pass    ssh;

  }
```
firewall-cmdでVPS上のexternal, internalのそれぞれのゾーンで開放したいポートを開ければOK
適宜設定すればVPSのホスト名で自宅鯖へ直接sshやhttpが通るはず、これで自宅鯖を公開できたね

# 留意点：
自宅鯖のデフォルトゲートウェイはおそらくご家庭のLANになっていると思うので、自宅鯖からPostfixでメールを送ったりするとOP25Bとspfに引っかかって送信できないということが起こる、ここはMailjetとかSendgridをご利用になって回避するのが賢いかなあと、メールの送信だけVPS経由にしてもいいけど、最近はVPSもOP25Bあるからその場合はNG、OP25BないならVPNサーバー上にSMTPプロキシを立てるのもあり
デフォルトゲートウェイを変えてしまうと問題が起きる場合もあるので、VPNサーバー上にHTTPプロキシを立てて必要なアプリケーションだけ通すようにするとか、静的ルートを登録するようにするのもいいかも
