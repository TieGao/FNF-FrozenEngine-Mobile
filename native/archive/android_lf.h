/*
 * android_lf.h — Android 大文件支持垫片。
 *
 * libarchive 原版由 cmake 在 Android 目标上生成这个头（archive.h 里
 * `#if defined(__LIBARCHIVE_BUILD) && defined(__ANDROID__)` 直接 #include "android_lf.h"）。
 * 这里手写一份等效内容，免得再引一套构建系统。
 *
 * arm64 上 off_t 本来就是 64 位，这两个宏是给 32 位 ABI 兜底的（bionic 从 API 21 起支持）。
 */
#ifndef ARCHIVE_ANDROID_LF_H_INCLUDED
#define ARCHIVE_ANDROID_LF_H_INCLUDED

#ifndef _FILE_OFFSET_BITS
#define _FILE_OFFSET_BITS 64
#endif
#ifndef _LARGEFILE_SOURCE
#define _LARGEFILE_SOURCE 1
#endif

#endif
