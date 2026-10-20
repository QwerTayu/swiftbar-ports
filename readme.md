# swiftbar-ports

localhost で待ち受け中のポートを、macOS のメニューバーに一覧表示する [SwiftBar](https://github.com/swiftbar/SwiftBar) プラグインです。

「どのポートで何が動いているか」をすぐ確かめて、そのままブラウザで開いたり、止めたりできます。

```
🌐 3
──────────────────────────────────────────
:3000   api · my-app (docker)     ▸ │ kill
:4321   node · my-portfolio       ▸
:5173   node · my-app             ▸
──────────────────────────────────────────
Other (12)                        ▸
──────────────────────────────────────────
Refresh
```

- 各ポートの持ち主を出します: プロセス名、プロジェクトのフォルダ名（git リポジトリならトップレベルの名前）、docker のコンテナ名。
- docker compose で立てたコンテナは、compose を実行したフォルダからプロジェクト名を出します（`api · my-app (docker)`）。そのラベルがないコンテナは、`$HOME` の下にあるバインドマウントのフォルダから出します（git worktree で立てたコンテナなら、worktree の名前になります）。
- 開発用のポートを上に並べ、ほかは `Other` のサブメニューに折りたたみます。
- メニューバーの数字は、開発用のポートの数です。

## 必要なもの

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar)（`brew install --cask swiftbar`）
- 任意: [OrbStack](https://orbstack.dev/) か Docker Desktop。`docker` コマンドが応答するときだけ、コンテナ名を出します。

`lsof`・`git`・`bash` は macOS に入っているものを使います（`/bin/bash` の 3.2 で動きます）。

## インストール

```sh
git clone https://github.com/QwerTayu/swiftbar-ports.git
cd swiftbar-ports
./install.sh
```

`install.sh` は、`ports.sh` を `~/.config/swiftbar/ports.10s.sh` へシンボリックリンクします（`10s` は 10 秒ごとに更新する意味です）。

- リンク先に普通のファイルがあれば、`ports.10s.sh.backup` に退避してから張ります。何度実行しても大丈夫です。
- SwiftBar のプラグインフォルダが別の場所なら、`SWIFTBAR_PLUGIN_DIR=/path/to/plugins ./install.sh` のように指定します。
- SwiftBar を初めて起動するときは、プラグインフォルダに `~/.config/swiftbar`（か、指定した場所）を選びます。

## 使い方

| 操作 | 動き |
|---|---|
| 開発用の行をクリック | `http://localhost:<ポート>` をデフォルトのブラウザで開く |
| サブメニューの `kill` | そのポートを止める。普通のプロセスは `kill <PID>`（SIGTERM）、docker のコンテナは `docker stop <コンテナ名>`。止めたら一覧を更新する |
| 行にホバー | 詳細（PID・コマンド・作業ディレクトリ、docker ならコンテナ名と compose のフォルダ）を出す |

- `Other` の行は、クリックでブラウザで開くだけです。macOS のシステムプロセスなどを誤って止めないよう、`kill` は付けていません。
- メニューを開くたびに最新の状態に更新されます。
- 開くブラウザは macOS のデフォルトのブラウザです。決まったブラウザで開きたいときは、`ports.sh` の先頭の `BROWSER` にアプリ名を書きます（例: `BROWSER="Google Chrome"`）。

## 「開発用」の判定

次のどちらかに当てはまるポートを「開発用」とし、上に並べます。

1. docker のコンテナが公開しているポート（`docker ps` のホスト側のポート）。
2. プロセスの作業ディレクトリ（cwd）が `$HOME` の下にある（`$HOME` そのものは除く）。

Discord や Spotify などの GUI アプリは cwd が `/` なので、自然に `Other` に入ります。

判定が外れたものは、`ports.sh` の先頭にある除外リストで直せます。

```sh
# コマンド名（lsof の COMMAND）。空白区切りで、* などのワイルドカードが使える。
EXCLUDE_COMMANDS="ControlCenter rapportd steam_osx Spotify Discord* LINE OrbStack* com.docker.*"
# ポート番号。空白区切り。
EXCLUDE_PORTS=""
# 作業ディレクトリがこの下にあるプロセス。空白区切り。
EXCLUDE_DIRS="$HOME/Library"
```

- `EXCLUDE_COMMANDS` に当てはまるプロセスは、cwd が `$HOME` の下でも `Other` に入ります。docker のコンテナのポートには効きません（OrbStack などが持っていても、コンテナとして扱います）。
- `EXCLUDE_PORTS` に当てはまるポートは、docker のコンテナでも `Other` に入ります。
- `EXCLUDE_DIRS` は、`~/Library` の下で動くアプリ（Steam など）を外すためのものです。

## アンインストール

```sh
rm ~/.config/swiftbar/ports.10s.sh
```
