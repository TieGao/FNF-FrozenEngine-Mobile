/*
 * fnf_archive.c — rar / 7z 数据包读取的 C 胶水层（基于 libarchive，只读解压）。
 *
 * 为什么是 C 而不是 C++：libarchive 是纯 C，hxcpp 只需要 extern "C" 符号，少一层名字修饰。
 *
 * 接口约定：**单例句柄**。导入界面是模态的，同一时刻只会开一个归档，所以句柄藏在 C 侧，
 * Haxe 完全不碰指针（省掉 Dynamic/RawPointer 与 void* 之间的转换）。
 *
 * 内存：解压全程流式（64KB 缓冲），solid 7z / solid rar 也只有一个解码窗口在内存里，
 * 不会像 LZMA SDK 的 SzArEx_Extract 那样把整个 folder 一次性解到内存。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <archive.h>
#include <archive_entry.h>

#include "fnf_archive.h"

#define FNF_ARCH_BUF_SIZE (64 * 1024)

#if defined(_WIN32)
#include <windows.h>
/* libarchive 的 archive_read_open_filename() 在 Windows 上把路径按 mbstowcs（ANSI 代码页）
 * 解释，而 Haxe 侧给的是 UTF-8 —— 中文路径会直接打不开。所以 Windows 上统一自己转 UTF-16，
 * 走 archive_read_open_filename_w / _wfopen；POSIX 上 UTF-8 字节就是路径本身，直接传。 */
static wchar_t *fnf_utf8_to_w(const char *s)
{
	int n;
	wchar_t *w;
	if (s == NULL)
		return NULL;
	n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
	if (n <= 0)
		return NULL;
	w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)n);
	if (w == NULL)
		return NULL;
	if (MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n) <= 0)
	{
		free(w);
		return NULL;
	}
	return w;
}
#endif

struct fnf_arch
{
	struct archive *a;
	struct archive_entry *entry;
	int at_eof;
	char errbuf[512];
	unsigned char buf[FNF_ARCH_BUF_SIZE];
};

static struct fnf_arch *g_arch = NULL;
static char g_oom_error[] = "out of memory";

static void fnf_set_error(struct fnf_arch *h, const char *msg)
{
	if (h == NULL)
		return;
	snprintf(h->errbuf, sizeof(h->errbuf), "%s", msg != NULL ? msg : "unknown error");
}

void fnf_arch_close(void)
{
	if (g_arch == NULL)
		return;
	if (g_arch->a != NULL)
		archive_read_free(g_arch->a);
	free(g_arch);
	g_arch = NULL;
}

int fnf_arch_open(const char *path)
{
	struct fnf_arch *h;
	int r;

	fnf_arch_close();

	if (path == NULL || path[0] == '\0')
		return -1;

	h = (struct fnf_arch *)calloc(1, sizeof(struct fnf_arch));
	if (h == NULL)
		return -1;
	g_arch = h;

	h->a = archive_read_new();
	if (h->a == NULL)
	{
		fnf_arch_close();
		return -1;
	}

	/* 只开三种容器 + 「外层不压缩」。zip 走引擎自己的流式路径（已调好，不必绕一圈）。 */
	archive_read_support_filter_none(h->a);
	archive_read_support_format_7zip(h->a);
	archive_read_support_format_rar(h->a);
	archive_read_support_format_rar5(h->a);

#if defined(_WIN32)
	{
		wchar_t *wpath = fnf_utf8_to_w(path);
		r = (wpath != NULL) ? archive_read_open_filename_w(h->a, wpath, 128 * 1024) : ARCHIVE_FATAL;
		free(wpath);
	}
#else
	r = archive_read_open_filename(h->a, path, 128 * 1024);
#endif
	if (r != ARCHIVE_OK)
	{
		fnf_set_error(h, archive_error_string(h->a));
		archive_read_free(h->a);
		h->a = NULL;
		return -1;
	}
	return 0;
}

int fnf_arch_next(void)
{
	struct fnf_arch *h = g_arch;
	int r;

	if (h == NULL || h->a == NULL)
		return -1;
	if (h->at_eof)
		return 0;
	h->entry = NULL;
	r = archive_read_next_header(h->a, &h->entry);
	if (r == ARCHIVE_EOF)
	{
		h->at_eof = 1;
		return 0;
	}
	if (r < ARCHIVE_WARN)
	{
		fnf_set_error(h, archive_error_string(h->a));
		return -1;
	}
	if (r == ARCHIVE_WARN)
	{
		/* 警告级（个别属性读不出）不该让整包失败：记下原因继续。 */
		fnf_set_error(h, archive_error_string(h->a));
	}
	return 1;
}

const char *fnf_arch_name(void)
{
	struct fnf_arch *h = g_arch;
	const char *p;

	if (h == NULL || h->entry == NULL)
		return NULL;
	/* 7z/rar5 容器里本来就是 UTF-8 / UTF-16，libarchive 内部转好；
	 * rar4 的 ANSI 名原样透传（与 zip 路径行为一致）。 */
	p = archive_entry_pathname_utf8(h->entry);
	if (p == NULL)
		p = archive_entry_pathname(h->entry);
	return p;
}

double fnf_arch_size(void)
{
	struct fnf_arch *h = g_arch;
	if (h == NULL || h->entry == NULL)
		return -1;
	/* 用 double 回给 Haxe：省掉 long long / Int64 的封送 */
	return (double)archive_entry_size(h->entry);
}

int fnf_arch_isdir(void)
{
	struct fnf_arch *h = g_arch;
	const char *p;

	if (h == NULL || h->entry == NULL)
		return 0;
	if (archive_entry_filetype(h->entry) == AE_IFDIR)
		return 1;
	p = fnf_arch_name();
	return (p != NULL && p[0] != '\0' && p[strlen(p) - 1] == '/') ? 1 : 0;
}

int fnf_arch_extract(const char *dstPath)
{
	struct fnf_arch *h = g_arch;
	FILE *fp;
	long long n;

	if (h == NULL || h->a == NULL || h->entry == NULL)
		return -1;
	if (dstPath == NULL)
	{
		fnf_set_error(h, "no destination path");
		return -1;
	}

#if defined(_WIN32)
	{
		wchar_t *wdst = fnf_utf8_to_w(dstPath);
		fp = (wdst != NULL) ? _wfopen(wdst, L"wb") : NULL;
		free(wdst);
	}
#else
	fp = fopen(dstPath, "wb");
#endif
	if (fp == NULL)
	{
		fnf_set_error(h, "cannot open destination file");
		return -1;
	}

	while ((n = (long long)archive_read_data(h->a, h->buf, FNF_ARCH_BUF_SIZE)) > 0)
	{
		if (fwrite(h->buf, 1, (size_t)n, fp) != (size_t)n)
		{
			fnf_set_error(h, "write failed (storage full?)");
			fclose(fp);
			return -1;
		}
	}

	if (n < 0)
	{
		fnf_set_error(h, archive_error_string(h->a));
		fclose(fp);
		return -1;
	}

	if (fclose(fp) != 0)
	{
		fnf_set_error(h, "close failed (storage full?)");
		return -1;
	}
	return 0;
}

int fnf_arch_skip(void)
{
	struct fnf_arch *h = g_arch;
	if (h == NULL || h->a == NULL)
		return -1;
	if (archive_read_data_skip(h->a) != ARCHIVE_OK)
	{
		fnf_set_error(h, archive_error_string(h->a));
		return -1;
	}
	return 0;
}

const char *fnf_arch_error(void)
{
	if (g_arch == NULL)
		return g_oom_error;
	return g_arch->errbuf;
}
