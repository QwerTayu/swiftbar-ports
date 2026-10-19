#!/bin/bash
# ports.sh を SwiftBar のプラグインフォルダにリンクする（何度実行しても安全）
set -eu
REPO="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/.config/swiftbar}"

link() {
  local src="$REPO/$1" dst="$PLUGIN_DIR/$2"
  mkdir -p "$(dirname "$dst")"
  # 既存の普通のファイルがあればバックアップしてlogに出力
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.backup"
    echo "backup: $dst -> $dst.backup"
  fi
  ln -sfn "$src" "$dst"
  echo "link: $dst -> $src"
}

# ファイル名の 10s が SwiftBar の更新間隔（10 秒ごと）
link ports.sh ports.10s.sh
