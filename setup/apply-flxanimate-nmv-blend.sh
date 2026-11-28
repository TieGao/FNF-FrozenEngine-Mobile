#!/bin/sh
# 把 NMV 的 blend 语义补丁打进 flxanimate 的 git 检出（setup/flxanimate-nmv-blend.patch）。
#
# 为什么非打不可：source/flxanimate/PsychFlxAnimate.hx 直接写 params.blendNoBake，
# 而 Dot-Stuff 上游（pin 的 0188d47c）没有这个字段 → 干净检出编译直接炸：
#   flxanimate.animate.SymbolParameters has no field blendNoBake
# 补丁内容 = SymbolParameters.blendNoBake（不走 cacheAsBitmap 离屏烘焙）
#          + FlxAnimate.parseElement 沿绘制树实时传 blend
#          + Clipper 层贴回时带上被它遮罩那一层的 blend。
#
# 幂等：先 `apply --reverse --check` 探「已打过」，再正向 apply；重复调用无副作用。
#
# 位置无关：仓库根按**本脚本所在目录**反推，不看调用方的 CWD。setup/unix.sh 与
# setup/windows.bat 开头都有 `cd ..`，历史上那版补丁块用 source/nmv、
# ../../../setup/... 这类相对路径，CWD 一挪全部门控失效、补丁从来没在 CI 里打上过
# （11-22 / 11-28 Android job 两度踩同一个坑）。
#
# 库定位顺序：$HAXELIB_REPO → `haxelib config` → ~/haxelib → ~/.haxelib。
#
# 退出码：0 = 不需要 / 已打过 / 刚打过；1 = 需要但打不上（库版本漂移或被本地改脏）。
# 早失败好过编译期再报一次看不懂的「字段不存在」。

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PATCH="$SCRIPT_DIR/flxanimate-nmv-blend.patch"

# 门控：main 分支既没有 source/nmv，也没有任何消费端（blendNoBake 只存在于 NMV
# 分支的 PsychFlxAnimate），静默跳过 —— 这个脚本会被两个分支共用的 workflow 调到。
if [ ! -d "$REPO_ROOT/source/nmv" ]; then
  echo "flxanimate nmv-blend patch: 非 NMV 检出，跳过"
  exit 0
fi
if [ ! -f "$PATCH" ]; then
  echo "flxanimate nmv-blend patch: 找不到补丁文件 $PATCH" >&2
  exit 1
fi

# Windows 上 HAXELIB_REPO / haxelib config 给的是反斜杠路径，交给 MSYS 转一下；
# Linux / macOS 没有 cygpath，原样返回。
to_unix() {
  if command -v cygpath >/dev/null 2>&1; then
    _p=$(cygpath -u "$1" 2>/dev/null)
    if [ -n "${_p:-}" ]; then
      printf '%s\n' "$_p"
      return 0
    fi
  fi
  printf '%s\n' "$1"
}

HAXELIB_ROOT_ENV=""
if [ -n "${HAXELIB_REPO:-}" ]; then
  HAXELIB_ROOT_ENV=$(to_unix "$HAXELIB_REPO")
fi

HAXELIB_ROOT_CFG=""
if command -v haxelib >/dev/null 2>&1; then
  HAXELIB_ROOT_CFG=$(haxelib config 2>/dev/null | head -n 1)
  if [ -n "${HAXELIB_ROOT_CFG:-}" ]; then
    HAXELIB_ROOT_CFG=$(to_unix "$HAXELIB_ROOT_CFG")
  fi
fi

LIB=""
for root in "${HAXELIB_ROOT_ENV:-}" "${HAXELIB_ROOT_CFG:-}" "${HOME:-}/haxelib" "${HOME:-}/.haxelib"; do
  [ -n "$root" ] || continue
  cand="${root%/}/flxanimate/git"
  if [ -f "$cand/flxanimate/FlxAnimate.hx" ] && [ -d "$cand/.git" ]; then
    LIB="$cand"
    break
  fi
done

if [ -z "$LIB" ]; then
  echo "flxanimate nmv-blend patch: 找不到 flxanimate 的 git 检出" >&2
  echo "  HAXELIB_REPO='${HAXELIB_REPO:-}'  haxelib config='${HAXELIB_ROOT_CFG:-}'  \$HOME='${HOME:-}'" >&2
  echo "  必须用 haxelib git 安装（haxelib install 的 release 版没有 .git，改不了）" >&2
  exit 1
fi

# 补丁文件在工作区可能被 core.autocrlf 翻成 CRLF；git apply 对 CRLF patch 不稳，
# 统一摞成 LF 再用。
TMP_PATCH="${TMPDIR:-/tmp}/fnf-flxanimate-nmv-blend.$$.patch"
trap 'rm -f "$TMP_PATCH"' EXIT INT TERM
if ! tr -d '\r' < "$PATCH" > "$TMP_PATCH"; then
  echo "flxanimate nmv-blend patch: 生成临时补丁失败（${TMP_PATCH}）" >&2
  exit 1
fi

if git -C "$LIB" apply --reverse --check "$TMP_PATCH" >/dev/null 2>&1; then
  echo "flxanimate nmv-blend patch: 已打过，跳过（${LIB}）"
  exit 0
fi

if git -C "$LIB" apply --ignore-whitespace "$TMP_PATCH"; then
  echo "flxanimate nmv-blend patch: applied → $LIB"
  exit 0
fi

echo "flxanimate nmv-blend patch: 应用失败（${LIB}）" >&2
echo "  多半是 flxanimate 版本漂移：setup/unix.sh、setup/windows.bat 里 pin 的 commit" >&2
echo "  与 setup/flxanimate-nmv-blend.patch 的上下文对不上了 —— 需要按新 commit 重做补丁。" >&2
exit 1
