#!/bin/bash
# <xbar.title>localhost ports</xbar.title>
# <xbar.desc>localhost で待ち受け中のポートと、その持ち主（プロセス・プロジェクト・docker コンテナ）を一覧にする</xbar.desc>
# <xbar.dependencies>bash,lsof</xbar.dependencies>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

# ---- 設定 -------------------------------------------------------------
# 「開発用」から外すもの。外れたものは Other に入る。
# コマンド名（lsof の COMMAND）。空白区切りで、* などのワイルドカードが使える。
# docker のコンテナのポートは、持ち主のコマンド名（OrbStack Helper など）にかかわらず開発用にする。
EXCLUDE_COMMANDS="ControlCenter rapportd steam_osx Spotify Discord* LINE OrbStack* com.docker.*"
# ポート番号。空白区切り。
EXCLUDE_PORTS=""
# 作業ディレクトリがこの下にあるプロセス。空白区切り（パスに空白は使えない）。
EXCLUDE_DIRS="$HOME/Library"
# クリックで開くブラウザ（open -a に渡すアプリ名。例: "Google Chrome"）。空ならデフォルトのブラウザで開く。
BROWSER=""
# ----------------------------------------------------------------------

# 除外リストの * をファイル名に展開させない
set -f

# SwiftBar から起動すると PATH が狭いので、docker・git などが見つかるように足す
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.orbstack/bin:$PATH"

# メニューの文字に | や改行が入ると SwiftBar の書式が崩れるので置き換える（tooltip 用に " も ' にする）
# 速さのため、外部コマンドを使わずに bash の中で置き換え、結果は変数 cleaned に入れる
clean() {
  cleaned="${1//|//}"
  cleaned="${cleaned//$'\n'/ }"
  cleaned="${cleaned//\"/\'}"
}

# 1. 待ち受けポートを集める（"ポート<TAB>PID<TAB>コマンド名"、IPv4 と IPv6 の重なりは 1 つにまとめる）
listeners="$(
  lsof -nP -iTCP -sTCP:LISTEN -F pcn 2>/dev/null | awk '
    /^p/ { pid = substr($0, 2) }
    /^c/ { cmd = substr($0, 2) }
    /^n/ {
      port = substr($0, 2); sub(/.*:/, "", port)
      if (!seen[port]++) printf "%s\t%s\t%s\n", port, pid, cmd
    }' | sort -n
)"

# 2. docker のコンテナ（"ホスト側のポート<TAB>コンテナ名<TAB>フォルダ<TAB>compose のプロジェクト名"）。
#    docker が応答するときだけ。フォルダは compose を実行したフォルダ。そのラベルがないコンテナ
#    （worktree で立てたものなど）は、$HOME の下にある最初のバインドマウントのフォルダを使う。
DOCKER="$(command -v docker)"
containers=""
if [ -n "$DOCKER" ]; then
  ps_out="$("$DOCKER" ps --format '{{.Names}}	{{.Ports}}	{{.Label "com.docker.compose.project.working_dir"}}	{{.Label "com.docker.compose.project"}}' 2>/dev/null)"
  # フォルダのラベルがないコンテナだけ、docker inspect でバインドマウントを調べる（"コンテナ名<TAB>マウント元..."）
  missing="$(printf '%s\n' "$ps_out" | awk -F'\t' '$1 != "" && $3 == "" { print $1 }')"
  mounts=""
  if [ -n "$missing" ]; then
    # shellcheck disable=SC2086
    mounts="$("$DOCKER" inspect --format '{{.Name}}{{range .Mounts}}{{if eq .Type "bind"}}	{{.Source}}{{end}}{{end}}' $missing 2>/dev/null)"
  fi
  # 例: "0.0.0.0:8004->3000/tcp, [::]:8004->3000/tcp"、"0.0.0.0:8000-8001->8000-8001/tcp"
  containers="$(
    {
      printf '%s\n' "$mounts" | sed 's/^/M\t/'
      printf '%s\n' "$ps_out" | sed 's/^/P\t/'
    } | awk -F'\t' -v home="$HOME/" '
      $1 == "M" {
        name = $2; sub(/^\//, "", name)
        for (i = 3; i <= NF; i++) if (index($i, home) == 1) { mdir[name] = $i; break }
        next
      }
      $1 == "P" && $2 != "" {
        dir = ($4 != "") ? $4 : mdir[$2]
        n = split($3, maps, ", ")
        for (i = 1; i <= n; i++) {
          if (maps[i] !~ /->/) continue
          host = maps[i]; sub(/->.*/, "", host); sub(/.*:/, "", host)
          lo = host; hi = host
          if (host ~ /-/) { split(host, r, "-"); lo = r[1]; hi = r[2] }
          for (p = lo; p <= hi; p++) if (!seen[p]++) printf "%s\t%s\t%s\t%s\n", p, $2, dir, $5
        }
      }'
  )"
fi

# 3. 各プロセスの作業ディレクトリ（"PID<TAB>cwd"）。lsof は 1 回だけ呼ぶ。
pids="$(printf '%s\n' "$listeners" | cut -f2 | sort -un | paste -sd, -)"
cwds=""
if [ -n "$pids" ]; then
  cwds="$(
    lsof -a -p "$pids" -d cwd -Fpn 2>/dev/null | awk '
      /^p/ { pid = substr($0, 2) }
      /^n/ { printf "%s\t%s\n", pid, substr($0, 2) }'
  )"
fi

# フォルダのプロジェクト名を変数 project に入れる。git リポジトリならトップレベルのフォルダ名、
# そうでなければそのフォルダ名。同じフォルダは 1 回だけ git に聞く（compose のコンテナはフォルダが重なりやすい）。
project_cache=$'\n'
project_of() {
  local dir="$1" top
  case "$project_cache" in
    *$'\n'"$dir"$'\t'*)
      project="${project_cache#*$'\n'"$dir"$'\t'}"
      project="${project%%$'\n'*}"
      return
      ;;
  esac
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
  top="${top:-$dir}"
  project="${top##*/}"
  project_cache+="$dir"$'\t'"$project"$'\n'
}

matches_any() {
  local value="$1" pattern
  for pattern in $2; do
    # shellcheck disable=SC2053
    [[ "$value" == $pattern ]] && return 0
  done
  return 1
}

in_dirs() {
  local dir="$1" d
  for d in $2; do
    [[ "$dir" == "$d" || "$dir" == "$d"/* ]] && return 0
  done
  return 1
}

# 4. ポートごとに、PID・コマンド名・cwd・コンテナの情報を 1 行にまとめる（awk 1 回で突き合わせる）。
#    空の欄があっても列がずれないよう、区切りはタブではなく \037（Unit Separator）にする。
US=$'\037'
rows="$(
  {
    printf '%s\n' "$cwds" | sed 's/^/C\t/'
    printf '%s\n' "$containers" | sed 's/^/D\t/'
    printf '%s\n' "$listeners" | sed 's/^/L\t/'
  } | awk -F'\t' -v OFS="$US" '
    $1 == "C" { cwd[$2] = $3 }
    $1 == "D" { name[$2] = $3; dir[$2] = $4; proj[$2] = $5 }
    $1 == "L" && $2 != "" { print $2, $3, $4, cwd[$3], name[$2], dir[$2], proj[$2] }'
)"

# 5. メニューの行を組み立てる
dev_lines=""
other_lines=""
dev_count=0
other_count=0

while IFS="$US" read -r port pid cmd cwd container compose_dir compose_project; do
  [ -n "$port" ] || continue
  url="http://localhost:$port"
  if [ -n "$BROWSER" ]; then
    open_action="bash=/usr/bin/open param1=-a param2=\"$BROWSER\" param3=$url terminal=false"
  else
    open_action="bash=/usr/bin/open param1=$url terminal=false"
  fi

  if [ -n "$container" ]; then
    project="$compose_project"
    [ -d "$compose_dir" ] && project_of "$compose_dir"
    owner="$container${project:+ · $project} (docker)"
    tooltip="docker: $container / ${compose_dir:-?} / PID $pid ($cmd)"
    stop_action="bash=$DOCKER param1=stop param2=$container terminal=false refresh=true"
    is_dev=1
  else
    is_dev=0
    if [[ "$cwd" == "$HOME"/* ]] && ! in_dirs "$cwd" "$EXCLUDE_DIRS" &&
      ! matches_any "$cmd" "$EXCLUDE_COMMANDS"; then
      is_dev=1
    fi
    # git でプロジェクト名を調べるのは開発用だけ。~/Library/Containers などで git を動かすと、
    # macOS のアクセス保護の確認で 1 回に数秒かかる。
    project=""
    [ "$is_dev" = 1 ] && project_of "$cwd"
    owner="$cmd${project:+ · $project}"
    tooltip="PID $pid / $cmd / ${cwd:-?}"
    stop_action="bash=/bin/kill param1=$pid terminal=false refresh=true"
  fi
  matches_any "$port" "$EXCLUDE_PORTS" && is_dev=0

  clean "$owner"
  printf -v label ':%-5s  %s' "$port" "$cleaned"
  clean "$tooltip"
  tooltip="tooltip=\"$cleaned\""
  if [ "$is_dev" = 1 ]; then
    dev_count=$((dev_count + 1))
    # 開発用の行は、クリックでブラウザで開き、サブメニューの kill で止める。
    # 親の行に動作がないと、SwiftBar が一覧を作り直したときにグレーの押せない行になり、
    # サブメニューも開けなくなるので、親の行には必ず動作（ここでは開く）を付ける。
    dev_lines+="$label | $open_action $tooltip font=Menlo"$'\n'
    dev_lines+="--kill | $stop_action"$'\n'
  else
    other_count=$((other_count + 1))
    other_lines+="--$label | $open_action $tooltip font=Menlo"$'\n'
  fi
done <<< "$rows"

# 6. メニューを出す
echo "$dev_count | sfimage=network"
echo "---"
if [ "$dev_count" = 0 ]; then
  echo "No dev ports"
else
  printf '%s' "$dev_lines"
fi
echo "---"
echo "Other ($other_count)"
printf '%s' "$other_lines"
echo "---"
echo "Refresh | refresh=true"
