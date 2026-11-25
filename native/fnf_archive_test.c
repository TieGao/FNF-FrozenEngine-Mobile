/*
 * fnf_archive_test.c — 原生解码层的验收工具（不参与引擎构建）。
 *
 *   fnf_archive_test list    <archive>
 *   fnf_archive_test extract <archive> <outDir>
 *
 * 对拍方式：7z x -o<ref> <archive> 之后，比较两棵树的逐文件 md5 清单。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fnf_archive.h"

#ifdef _WIN32
#include <direct.h>
#define fnf_mkdir(p) _mkdir(p)
#define fnf_sep(c) ((c) == '\\' || (c) == '/')
#else
#include <sys/stat.h>
#include <unistd.h>
#define fnf_mkdir(p) mkdir(p, 0755)
#define fnf_sep(c) ((c) == '/')
#endif

static void ensure_parent_dirs(const char *path)
{
	char tmp[4096];
	size_t i, len;

	len = strlen(path);
	if (len >= sizeof(tmp))
		return;
	memcpy(tmp, path, len + 1);
	for (i = 1; i < len; i++)
	{
		if (fnf_sep(tmp[i]))
		{
			char save = tmp[i];
			tmp[i] = '\0';
			fnf_mkdir(tmp);
			tmp[i] = save;
		}
	}
}

static int do_list(const char *path)
{
	int count = 0;
	int r;

	if (fnf_arch_open(path) != 0)
	{
		fprintf(stderr, "open failed: %s\n", fnf_arch_error());
		return 1;
	}
	while ((r = fnf_arch_next()) == 1)
	{
		const char *n = fnf_arch_name();
		printf("%s\t%.0f\t%s\n", fnf_arch_isdir() ? "D" : "F", fnf_arch_size(), n != NULL ? n : "(null)");
		count++;
		fnf_arch_skip();
	}
	if (r < 0)
		fprintf(stderr, "error: %s\n", fnf_arch_error());
	fnf_arch_close();
	fprintf(stderr, "entries=%d\n", count);
	return r < 0 ? 1 : 0;
}

static int do_extract(const char *path, const char *outDir)
{
	char dst[4096];
	int count = 0;
	int failed = 0;
	int r;

	if (fnf_arch_open(path) != 0)
	{
		fprintf(stderr, "open failed: %s\n", fnf_arch_error());
		return 1;
	}
	while ((r = fnf_arch_next()) == 1)
	{
		const char *n = fnf_arch_name();
		char *p;
		if (n == NULL)
			continue;
		snprintf(dst, sizeof(dst), "%s/%s", outDir, n);
		for (p = dst; *p; p++)
			if (*p == '\\')
				p[0] = '/';
		if (fnf_arch_isdir())
		{
			fnf_mkdir(dst);
			continue;
		}
		ensure_parent_dirs(dst);
		if (fnf_arch_extract(dst) != 0)
		{
			fprintf(stderr, "extract failed: %s (%s)\n", n, fnf_arch_error());
			failed++;
		}
		count++;
	}
	if (r < 0)
	{
		fprintf(stderr, "error: %s\n", fnf_arch_error());
		failed++;
	}
	fnf_arch_close();
	fprintf(stderr, "extracted=%d failed=%d\n", count, failed);
	return failed ? 1 : 0;
}

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		fprintf(stderr, "usage: %s list|extract <archive> [outDir]\n", argv[0]);
		return 2;
	}
	if (strcmp(argv[1], "list") == 0)
		return do_list(argv[2]);
	if (strcmp(argv[1], "extract") == 0 && argc >= 4)
		return do_extract(argv[2], argv[3]);
	fprintf(stderr, "bad args\n");
	return 2;
}
