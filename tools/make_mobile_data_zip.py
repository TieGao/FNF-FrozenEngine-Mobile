#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
移动端数据包打包脚本（方案A：数据外置 /sdcard/.FrozenEngine/）。

APK 瘦身后不再内嵌 assets/content/mods，数据由本脚本打成 zip 随完整包发布；
用户在游戏引导屏"导入数据包 zip"或自行解压到数据根即可（zip 顶层与数据根同构）。

用法（在仓库根目录执行）：
  python tools/make_mobile_data_zip.py                    # 全量：assets + content + mods
  python tools/make_mobile_data_zip.py --content Erect    # 只打原版歌曲分类包（content/VanillaSongs/Erect + readme）

产物：
  FrozenEngine-mobile-data-full.zip            # 全量数据包
  FrozenEngine-mobile-content-<Cat>.zip        # 可选内容分类包
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
# 数据就绪标记（与 BootDataState.DATA_MARKER 对应），打全量包后自检
DATA_MARKER = 'assets/shared/images/logoBumpin.png'


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

    # 全量数据包
    out = 'FrozenEngine-mobile-data-full.zip'
    total = 0
    with zipfile.ZipFile(out, 'w', allowZip64=True) as zf:
        total += add_tree(zf, 'assets', 'assets')
        total += add_tree(zf, 'content', 'content')
        total += add_tree(zf, 'example_mods', 'mods')
    with zipfile.ZipFile(out) as zf:
        ok = DATA_MARKER in zf.namelist()
    size_mb = os.path.getsize(out) / 1024 / 1024
    print(f'[完成] {out}: {total} 个文件, {size_mb:.0f} MB, 标记文件{"OK" if ok else "缺失!"}')
    if not ok:
        sys.exit(1)


if __name__ == '__main__':
    main()
