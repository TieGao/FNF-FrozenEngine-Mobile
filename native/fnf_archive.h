/* fnf_archive.h — rar/7z 原生解码层的 C 接口（Haxe 侧只认这几个符号）。
 *
 * 单例句柄：同一时刻只开一个归档（导入界面是模态的）。open 会先关掉上一个。 */
#ifndef FNF_ARCHIVE_H
#define FNF_ARCHIVE_H

/* hxcpp 会用 C++ 编译器编 .c（实测符号是 C++ 修饰名），所以这里必须显式 extern "C"，
 * 否则 Haxe 侧按 C 名找不到符号（LNK2019 fnf_arch_open(char const *)）。 */
#ifdef __cplusplus
extern "C" {
#endif

/* 打开归档：0=成功，-1=失败 */
int fnf_arch_open(const char *path);

/* 关掉当前归档（可重复调用） */
void fnf_arch_close(void);

/* 前进到下一个条目：1=有，0=结束，-1=出错 */
int fnf_arch_next(void);

/* 当前条目名（UTF-8，生命周期到下一次 next 为止） */
const char *fnf_arch_name(void);

/* 当前条目解压后大小（字节；未知 <0） */
double fnf_arch_size(void);

/* 当前条目是不是目录 */
int fnf_arch_isdir(void);

/* 把当前条目流式写到 dstPath：0=成功，-1=失败 */
int fnf_arch_extract(const char *dstPath);

/* 跳过当前条目数据（预扫用）：0=成功 */
int fnf_arch_skip(void);

/* 最近一次错误文本 */
const char *fnf_arch_error(void);

#ifdef __cplusplus
}
#endif

#endif
