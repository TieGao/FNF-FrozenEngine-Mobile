#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
移动端数据包打包脚本（方案B'：数据外置 /sdcard/.FrozenEngine/，游戏内 BootDataState 综合体入口导入）。

APK 只内嵌基础 assets（引擎裸跑所需）+ mods 模板；原版资源 / 内容分类由本脚本打成独立 zip，
release 固定发布——用户下载任意一个官方 zip，游戏内"导入数据包 zip"一键导入（按顶层前缀自动落位）。

用法（在仓库根目录执行）：
  python tools/make_mobile_data_zip.py                    # 全量：base_game 摊平 + content 全量 + mods 模板
  python tools/make_mobile_data_zip.py --base             # 原版资源包（base_game 摊平进 assets/）
  python tools/make_mobile_data_zip.py --content Erect PicoMix BFMix Collab   # 原版额外曲分类包
  python tools/make_mobile_data_zip.py --customcharts     # CustomCharts 包

产物：
  FrozenEngine-mobile-data-full.zip            # 全量数据包
  FrozenEngine-mobile-base.zip                 # 原版资源包（必装）
  FrozenEngine-mobile-content-<Cat>.zip        # 可选内容分类包（Erect/PicoMix/BFMix/Collab）
  FrozenEngine-mobile-customcharts.zip         # CustomCharts 包
"""
import argparse
import os
import sys
import zipfile

# 已压缩媒体直接 STORED（免白耗 CPU），文本类 DEFLATED
STORED_EXT = {
    '.ogg', '.mp3', '.wav', '.png', '.jpg', '.jpeg', '.webm', '.mp4', '.ttf', '.otf',
    '.atlas', '.webp', '.ico', '.dll', '.ndll', '.so',
}
# 原版数据就绪标记（与 BootDataState.DATA_MARKER 对应），打全量包后自检
DATA_MARKER = 'assets/week2'


def add_file(zf: zipfile.ZipFile, full: str, arcname: str):
    ext = os.path.splitext(full)[1].lower()
    method = zipfile.ZIP_STORED if ext in STORED_EXT else zipfile.ZIP_DEFLATED
    zf.write(full, arcname, compress_type=method)


def add_tree(zf: zipfile.ZipFile, src_root: str, arc_root: str) -> int:
    if not os.path.isdir(src_root):
        return 0
    count = 0
    for dirpath, dirnames, filenames in os.walk(src_root):
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, src_root).replace('\\', '/')
            add_file(zf, full, f'{arc_root}/{rel}')
            count += 1
    return count


def main():
    ap = argparse.ArgumentParser(description='打包移动端数据包 zip')
    ap.add_argument('--content', nargs='+', metavar='CAT',
                    help='只打可选内容分类包（content/VanillaSongs/<CAT>，如 Erect PicoMix BFMix Collab）')
    ap.add_argument('--base', action='store_true',
                    help='只打原版资源包（base_game 摊平进 assets/，不含 content/mods）')
    ap.add_argument('--customcharts', action='store_true',
                    help='只打 CustomCharts 包（content/CustomCharts + readme）')
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    if args.content:
        for cat in args.content:
            out = f'FrozenEngine-mobile-content-{cat}.zip'
            src = os.path.join('content', 'VanillaSongs', cat)
            if not os.path.isdir(src):
                print(f'[跳过] 不存在: {src}')
                continue
            with zipfile.ZipFile(out, 'w', allowZip64=True) as zf:
                n = add_tree(zf, src, f'content/VanillaSongs/{cat}')
                if os.path.isfile('content/readme.txt'):
                    add_file(zf, 'content/readme.txt', 'content/readme.txt')
                    n += 1
            size_mb = os.path.getsize(out) / 1024 / 1024
            print(f'[完成] {out}: {n} 个文件, {size_mb:.0f} MB')
        return

    if args.base:
        out = 'FrozenEngine-mobile-base.zip'
        with zipfile.ZipFile(out, 'w', allowZip64=True) as zf:
            n = add_tree(zf, 'assets/base_game', 'assets')
        ok = any(name.startswith('assets/week2/') for name in zipfile.ZipFile(out).namelist())
        size_mb = os.path.getsize(out) / 1024 / 1024
        print(f'[完成] {out}: {n} 个文件, {size_mb:.0f} MB, 原版数据标记{"OK" if ok else "缺失!"}')
        if not ok:
            sys.exit(1)
        return

    if args.customcharts:
        out = 'FrozenEngine-mobile-customcharts.zip'
        with zipfile.ZipFile(out, 'w', allowZip64=True) as zf:
            n = add_tree(zf, 'content/CustomCharts', 'content/CustomCharts')
            if os.path.isfile('content/readme.txt'):
                add_file(zf, 'content/readme.txt', 'content/readme.txt')
                n += 1
        size_mb = os.path.getsize(out) / 1024 / 1024
        print(f'[完成] {out}: {n} 个文件, {size_mb:.0f} MB')
        return

    # 全量数据包：base_game 数据摊平进 assets/（与桌面 rename='assets' 同口径）+ content + mods 模板
    out = 'FrozenEngine-mobile-data-full.zip'
    total = 0
    with zipfile.ZipFile(out, 'w', allowZip64=True) as zf:
        total += add_tree(zf, 'assets/base_game', 'assets')
        total += add_tree(zf, 'content', 'content')
        total += add_tree(zf, 'example_mods', 'mods')
        # modsList.txt 仅在非空时打：空文件无默认 mod 状态可言（Mods 会自动扫描 mods/ 补全），
        # 且 BootDataState 白名单只认 assets/ content/ mods/ 前缀，顶层 modsList.txt 会让导入整体失败
        if os.path.isfile('list.txt') and os.path.getsize('list.txt') > 0:
            add_file(zf, 'list.txt', 'modsList.txt')  # 与桌面 bin 旁 modsList.txt 同口径（首启默认 mod 开关状态）
            total += 1
    with zipfile.ZipFile(out) as zf:
        ok = any(n.startswith(DATA_MARKER + '/') for n in zf.namelist())
    size_mb = os.path.getsize(out) / 1024 / 1024
    print(f'[完成] {out}: {total} 个文件, {size_mb:.0f} MB, 原版数据标记{"OK" if ok else "缺失!"}')
    if not ok:
        sys.exit(1)


if __name__ == '__main__':
    main()
