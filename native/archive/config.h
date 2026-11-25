/* 手写的最小 libarchive 配置（只读解压：7z / rar / rar5）。
 * 原版由 cmake/configure 生成 config.h；引擎构建只跑 hxcpp，不引入第二套构建系统，
 * 所以手钉一份、Windows(MSVC) 与 Android(bionic) 靠平台宏分叉。
 * 原则：只定义「确实存在」的特性（libarchive 用 #ifdef 判断），缺省即关闭并走其兜底分支。 */
#ifndef FNF_ARCHIVE_CONFIG_H
#define FNF_ARCHIVE_CONFIG_H

/* 内部头（archive_digest_private.h 等）靠这个标记判断 config.h 已先被包含 */
#define __LIBARCHIVE_CONFIG_H_INCLUDED 1

#define LIBARCHIVE_VERSION_NUMBER 3007007
#define LIBARCHIVE_VERSION_STRING "3.7.7"

/* ---- 标准头 ---- */
#define HAVE_CTYPE_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_LIMITS_H 1
#define HAVE_INTTYPES_H 1
#define SIZEOF_INT 4
#define SIZEOF_SHORT 2
#define SIZEOF_LONG_LONG 8
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_TIME_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1
#define HAVE_LOCALE_H 1

/* stdint 里的 INT*_MAX/SIZE_MAX 在 UCRT 与 bionic 都有；不声明的话 libarchive 会自己
 * 重定义一遍，和 <stdint.h> 撞（C4005）。 */
#define HAVE_DECL_SIZE_MAX 1
#define HAVE_DECL_SSIZE_MAX 0
#define HAVE_DECL_INT32_MAX 1
#define HAVE_DECL_INT32_MIN 1
#define HAVE_DECL_UINT32_MAX 1
#define HAVE_DECL_INT64_MAX 1
#define HAVE_DECL_INT64_MIN 1
#define HAVE_DECL_UINT64_MAX 1
#define HAVE_DECL_INTMAX_MAX 1
#define HAVE_DECL_INTMAX_MIN 1
#define HAVE_DECL_UINTMAX_MAX 1

/* ---- 标准函数（两平台 UCRT / bionic 都有） ---- */
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRFTIME 1
#define HAVE_STRNLEN 1
#define HAVE_STRRCHR 1
#define HAVE_STRSTR 1
#define HAVE_STRTOL 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOIMAX 1
#define HAVE_STRTOUMAX 1
#define HAVE_STRTOULL 1
#define HAVE_VSNPRINTF 1
#define HAVE_SNPRINTF 1
#define HAVE_WCHAR_T 1
#define SIZEOF_WCHAR_T 2 /* Windows 与 bionic(arm64) 的 wchar_t 都是 2 字节 */
#define HAVE_WCSCMP 1
#define HAVE_WCSCPY 1
#define HAVE_WCSLEN 1
#define HAVE_WCSNLEN 1
#define HAVE_WMEMCMP 1
#define HAVE_WMEMCPY 1
#define HAVE_WMEMMOVE 1
#define HAVE_MBRTOWC 1
#define HAVE_WCTOMB 1
#define HAVE_MBSINIT 1
#define HAVE_LONG_LONG_INT 1
#define HAVE_UNSIGNED_LONG_LONG 1

/* ---- 7z 的 LZMA/LZMA2/BCJ/Delta 全靠真 liblzma（我们自己 vendor 的那份） ---- */
#define HAVE_LZMA_H 1

/* 不要 zlib/bz2/zstd/lz4/iconv/libxml2：只解 7z/rar，不为别的格式背依赖 */
/* 注意：不定义 HAVE_ICONV 时 libarchive 走「原样透传」分支；rar5/7z 的名字本来就是
   UTF-8 / UTF-16 记录，透传不会乱码；rar4 的 ANSI 名字会原样保留（与 zip 路径行为一致）。 */

#if defined(_WIN32)
#	define _CRT_SECURE_NO_WARNINGS 1
#	define SIZEOF_LONG 4 /* LLP64 */
#elif defined(__ANDROID__)
#	define SIZEOF_LONG 8 /* LP64 */
#endif

#if defined(_WIN32)
#	define _CRT_SECURE_NO_WARNINGS 1
	/* MSVC 没有 POSIX 的 ssize_t；libarchive 的 Windows 兼容层到处用它（archive_windows.h） */
#	include <stddef.h>
#	include <basetsd.h>
	typedef SSIZE_T ssize_t;
	typedef int pid_t; /* Windows 兼容层（archive_windows.h）用它声明 __la_waitpid */
	typedef unsigned short mode_t; /* MSVC/UCRT 没有 mode_t（内部叫 _mode_t） */
	typedef unsigned int uid_t;
	typedef unsigned int gid_t;
#	define HAVE_IO_H 1
#	define HAVE_WINDOWS_H 1
#	define HAVE__SNPRINTF 1
#	define HAVE__STRICMP 1
#	define HAVE_STRICMP 1
#	define HAVE__STRTOI64 1
#	define HAVE__STRTOL 1
#	define HAVE__STRTOL_L 1
#	define HAVE_BCRYPT_H 1 /* rar5 的 sha256 走 CNG，比自带实现快 */
#else
	/* iOS / macOS / Linux / Android 都是 POSIX，bionic 只是少几个头 */
#	define HAVE_UNISTD_H 1
#	define HAVE_DIRENT_H 1
#	define HAVE_SIGNAL_H 1
#	define HAVE_PWD_H 1
#	define HAVE_GRP_H 1
#	define HAVE_UTIME_H 1
#	define HAVE_SYS_TYPES_H 1
#	define HAVE_SYS_STAT_H 1
#	define HAVE_SYS_TIME_H 1
#	define HAVE_SYS_IOCTL_H 1
#	define HAVE_SYS_PARAM_H 1
#	define HAVE_SYS_UTSNAME_H 1
#	define HAVE_FSTAT 1
#	define HAVE_FCNTL 1
#	define HAVE_FSYNC 1
#	define HAVE_GETCWD 1
#	define HAVE_MKDIR 1
#	define HAVE_RMDIR 1
#	define HAVE_UNLINK 1
#	define HAVE_CHMOD 1
#	define HAVE_FTRUNCATE 1
#	define HAVE_LSTAT 1
#	define HAVE_UMASK 1
#	define HAVE_UTIMES 1
#	define HAVE_GETPID 1
#	define HAVE_MBRTOWC 1
#	define HAVE_MBSINIT 1
#	define HAVE_WCRTOMB 1
#	define HAVE_MKSTEMP 1
#	define HAVE_READLINK 1
#endif

#endif
