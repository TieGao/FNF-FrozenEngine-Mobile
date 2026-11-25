/* 手写的最小 liblzma 配置：只开「解码器 + CRC32」，不带编码器/线程/工具链探测。
 * Windows(MSVC) 与 Android(bionic) 共用，靠平台宏分叉。原版走 autoconf/cmake 生成，
 * 这里手钉是因为引擎构建只跑 hxcpp，不引入第二套构建系统。
 * 只保留被引用到的宏：缺省 = 关闭对应特性，liblzma 源码里都有兜底分支。 */
#ifndef FNF_LZMA_CONFIG_H
#define FNF_LZMA_CONFIG_H

#define PACKAGE_NAME "liblzma"
#define PACKAGE_VERSION "5.6.3"
#define VERSION "5.6.3"

/* 两个目标都是 64 位 */
#define SIZEOF_SIZE_T 8

#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDBOOL_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_WCHAR_H 1

/* x86_64 / arm64 都允许非对齐访问，liblzma 靠这个走快路径 */
#define TUKLIB_FAST_UNALIGNED_ACCESS 1

/* ---- 只编解码器，不要编码器 ---- */
#define HAVE_DECODERS 1
#define HAVE_DECODER_LZMA1 1
#define HAVE_DECODER_LZMA2 1
#define HAVE_DECODER_DELTA 1
#define HAVE_DECODER_X86 1
#define HAVE_DECODER_ARM 1
#define HAVE_DECODER_ARM64 1
#define HAVE_DECODER_ARMTHUMB 1
#define HAVE_DECODER_IA64 1
#define HAVE_DECODER_POWERPC 1
#define HAVE_DECODER_SPARC 1
#define HAVE_DECODER_RISCV 1

/* 校验只留 CRC32（7z 的条目 CRC 由 libarchive 自己算，这里只满足解码器内部需要） */
#define HAVE_CHECK_CRC32 1

#if defined(_WIN32)
#	define _CRT_SECURE_NO_WARNINGS 1
#elif defined(__ANDROID__)
#	define HAVE_UNISTD_H 1
#	define HAVE_SYS_TYPES_H 1
#	define HAVE_SYS_STAT_H 1
#	define HAVE_SYS_CDEFS_H 1
#	define HAVE_ICONV 1 /* bionic 的 iconv 在 libc 里，不用额外链接 */
#endif

#endif
