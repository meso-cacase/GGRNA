# Podman setup for GGRNA

このディレクトリは、GGRNA を Apache + CGI で起動するための Podman Compose 構成です。

## 構成

```text
podman_ggrna/
├── README.md
├── compose.yml
└── apache/
    ├── Dockerfile
    └── 000-default.conf
```

- `compose.yml`: `web` サービスを定義します。
- `apache/Dockerfile`: Debian trixie-slim ベースで Apache と Perl CGI 関連パッケージをインストールします。
- `apache/000-default.conf`: Apache の VirtualHost 設定です。

## 前提

- Podman
- Podman Compose

環境によって Compose コマンドは `podman compose` または `podman-compose` のどちらかです。
以下では `podman compose` を例にしています。動かない場合は `podman-compose` に読み替えてください。

## 起動

必ずこの `podman_ggrna` ディレクトリで実行してください。
`compose.yml` は `${PWD}/..` を `/var/www/html` に読み取り専用でマウントするため、実行ディレクトリが重要です。

```sh
podman compose up -d --build
```

デフォルトではホストの `80` 番ポートをコンテナの `80` 番ポートへ割り当てます。

```sh
curl -I http://localhost/
```

## ポートを変更して起動

ホスト側のポートは `APACHE_HTTP_PORT` で変更できます。

```sh
APACHE_HTTP_PORT=8080 podman compose up -d --build
```

確認:

```sh
curl -I http://localhost:8080/
```

## ログ確認

```sh
podman compose logs -f web
```

Apache の `ErrorLog` は stderr、`CustomLog` は stdout に出力されるため、Compose のログで確認できます。

## 停止

```sh
podman compose down
```

## 再ビルド

Apache 設定や Dockerfile を変更した場合は、再ビルドして起動します。

```sh
podman compose up -d --build
```

## サービス内容

`web` サービスは以下の設定で起動します。

- ビルドコンテキスト: このディレクトリ
- Dockerfile: `apache/Dockerfile`
- コンテナ内 DocumentRoot: `/var/www/html`
- マウント: 親ディレクトリ `${PWD}/..` を `/var/www/html` に `ro` でマウント
- Apache モジュール: `cgid`, `headers`, `negotiation`, `rewrite`
- `PERL5LIB`: `/var/www/html`
- Restart policy: `always`
- ログローテーション: `10m` x `5` ファイル

## 注意点

- ホストの `80` 番ポートを使う場合、rootless Podman の環境では権限や OS 設定により起動できないことがあります。その場合は `APACHE_HTTP_PORT=8080` など、1024 以上のポートを指定してください。
- `/var/www/html` は読み取り専用マウントです。コンテナ内からアプリケーションファイルを書き換える用途には使えません。
- Apache の `ServerName` は `ggrna.dbcls.jp` に設定されています。ローカル確認では `localhost` または指定したホスト名でアクセスしてください。
