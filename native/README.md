# native/ —— rar / 7z 数据包解码层

数据包导入除了 zip（引擎自带 `haxe.zip.Reader` + hxcpp 内置 zlib 的流式路径）之外，
还支持 **rar / 7z**。这两种容器没有任何 Haxe 实现，所以要 vendor 第三方 C 源码。

## 组成

| 目录 | 内容 | 版本 | 许可 |
|---|---|---|---|
| `archive/` | libarchive（**裁剪**：只保留 7z / rar / rar5 读取 + core） | 3.7.7 | BSD-2-Clause |
| `lzma/` | liblzma（**裁剪**：只保留 LZMA/LZMA2/BCJ/Delta 解码器 + CRC32） | 5.6.3 | 0BSD |
| `fnf_archive.c/.h` | 胶水层：单例句柄 + 逐条 `next/name/size/extract/skip` | — | 与引擎同 |
| `fnf_archive_test.c` | 验收工具（**不参与引擎构建**）：列目录 / 解压，用于与 7-Zip 官方结果逐文件 md5 对拍 | — | 与引擎同 |

为什么是 libarchive 而不是更小的方案：`unarr` 不支持 RAR5（WinRAR 5+ 默认格式，等于现代
.rar 全废）；LZMA SDK 的 `SzArEx_Extract` 只能把整个 solid folder 解到一个预分配大 buffer
（7z 默认 solid，1GB 包就要 1GB 常驻内存，手机必被系统杀）。libarchive 的 7z/rar 读取器是
流式的：解一段写一段，内存只有一个解码窗口 + liblzma 字典（-mx9 约 64MB）。

## 构建方式

由 `source/backend/NativeArchive.hx` 里的 `@:buildXml` 注入 hxcpp 构建，**没有第二套构建系统**。
四个必须知道的坑写在那份文件的注释里（`<file>` 必须挂顶层 `<files>`、相对路径基准是
`export/<build>/<target>/obj`、两个库各自的 `config.h` 靠分组 `-I` 区分、
C 符号声明要挂在调用方 TU 的 `@:cppFileCode` 上并带 `extern "C"`）。

⚠️ **相对路径基准随平台而变**：hxcpp 的 C++ 工作目录在 Windows / Android 是
`export/<build>/<target>/obj`，而 iOS 的 Xcode `Build Haxe` 外部构建会再 cd 进
`export/release/ios/<App>/haxe/build/Release-iphoneos-64`（深 3 级）。所以
`NativeArchive.hx` 的 `@:buildXml` 统一用 `${FNF_NATIVE_DIR}`（`<section if="ios">`
改成 7 级 `../`）；新增 C 源文件时只写 `${FNF_NATIVE_DIR}/...`，别写死 `../../../../native`。

⚠️ **hxcpp 不跟踪 C 头文件依赖**：改了 `config.h` / `fnf_archive.h` 之后，相关的 .obj 不会自动
重编，得手动删掉对应 obj（或 touch 对应的 .c）再构建，否则会拿到旧符号/旧配置。

## 已知限制

- 加密（带密码）的 rar/7z 不支持：libarchive 会报 "Encrypted file is unsupported"。
- 分卷、自解压包不支持（libarchive 的既有边界）。
- rar4 的**非 Unicode** 文件名按原字节透传（与 zip 路径行为一致），中文名可能显示为乱码；
  rar5 / 7z 的文件名是 UTF-16 记录，正常。
- 性能：solid LZMA2 -mx9 单线程解码约 18MB/s 出（950MB 包 ≈ 60s），压缩率换来的代价。

## 裁剪说明

- libarchive 只编 `archive_read_*`（无 write/disk/extract/match/pathmatch），格式只留
  7z / rar / rar5，filter 只留 `none`（zip 不走这里）。
- liblzma 只编解码器（`HAVE_DECODERS`，无 `HAVE_ENCODERS`），check 只留 CRC32。
- 两个库的 `config.h` 都是手写的最小集（原版靠 autoconf/cmake 生成），带平台分叉：
  `_WIN32` / POSIX（Android、iOS、macOS、Linux）。
