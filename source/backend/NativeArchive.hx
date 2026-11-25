package backend;

#if cpp
/**
 * rar / 7z 数据包的原生解码层（libarchive + liblzma，只读解压）。
 *
 * 为什么要有这个类：
 *  - zip 走 haxe.zip.Reader + hxcpp 内置 zlib 就够了，但 rar/7z 没有任何 Haxe/标准库实现；
 *  - `unarr` 不支持 RAR5（WinRAR 5+ 默认格式，等于现代 .rar 全废），所以用 libarchive；
 *  - libarchive 的 7z 读取器天然流式：solid 包按「解一段、写一段、跳过」处理，内存只有一个
 *    解码窗口 + liblzma 字典（-mx9 约 64MB），不像 LZMA SDK 的 SzArEx_Extract 把整个 solid
 *    folder 一次解到内存（那在手机上是必杀）。
 *
 * 原生源码清单在下面的 @:buildXml 里。四个坑（改之前先读）：
 *  1) <file> 必须挂在顶层 <files id=...> 里，再由 <target id="haxe"> 引用；直接嵌进 <target>
 *     不报错但文件被静默忽略，最后表现成链接期 undefined symbol。
 *  2) 相对路径基准是 hxcpp 的构建目录 export/<build>/<target>/obj（不是项目根），所以项目根
 *     要写 ../../../../；windows / android 深度一致。
 *  3) libarchive 与 liblzma 各要一份 config.h，而两者都按 <config.h> 找：靠分组 + 各自的 -I
 *     区分（liblzma 的在 native/lzma/cfg，libarchive 的在 native/archive）。
 *  4) C 符号声明必须对调用它的那个 TU 可见：`#include "fnf_archive.h"` 是挂在
 *     BootDataState 的 @:cppFileCode 上的（@:cppFileCode 只进本类的 .cpp，而调用发生在
 *     BootDataState.cpp）。这里额外给 files id="haxe" 加了 -Inative，供那条 include 找头。
 *
 * 句柄是单例的（导入界面模态，一次只开一个包），所以这里不出现任何指针类型。
 */
@:buildXml('
<files id="haxe">
	<compilerflag value="-I../../../../native"/>
	<compilerflag value="-utf-8" if="windows"/>
</files>
<files id="fnf_lzma" c_standard="11">
	<compilerflag value="-utf-8" if="windows"/>
	<compilerflag value="-DHAVE_CONFIG_H"/>
	<compilerflag value="-DLZMA_API_STATIC"/>
	<compilerflag value="-I../../../../native/lzma/cfg"/>
	<compilerflag value="-I../../../../native/lzma/"/>
	<compilerflag value="-I../../../../native/lzma/api"/>
	<compilerflag value="-I../../../../native/lzma/common"/>
	<compilerflag value="-I../../../../native/lzma/lz"/>
	<compilerflag value="-I../../../../native/lzma/lzma"/>
	<compilerflag value="-I../../../../native/lzma/check"/>
	<compilerflag value="-I../../../../native/lzma/delta"/>
	<compilerflag value="-I../../../../native/lzma/simple"/>
	<compilerflag value="-I../../../../native/lzma/rangecoder"/>
	<file name="../../../../native/lzma/check/check.c"/>
	<file name="../../../../native/lzma/check/crc32_fast.c"/>
	<file name="../../../../native/lzma/check/crc32_table.c"/>
	<file name="../../../../native/lzma/common/common.c"/>
	<file name="../../../../native/lzma/common/filter_common.c"/>
	<file name="../../../../native/lzma/common/filter_decoder.c"/>
	<file name="../../../../native/lzma/delta/delta_common.c"/>
	<file name="../../../../native/lzma/delta/delta_decoder.c"/>
	<file name="../../../../native/lzma/lz/lz_decoder.c"/>
	<file name="../../../../native/lzma/lzma/fastpos_table.c"/>
	<file name="../../../../native/lzma/lzma/lzma2_decoder.c"/>
	<file name="../../../../native/lzma/lzma/lzma_decoder.c"/>
	<file name="../../../../native/lzma/simple/arm.c"/>
	<file name="../../../../native/lzma/simple/arm64.c"/>
	<file name="../../../../native/lzma/simple/armthumb.c"/>
	<file name="../../../../native/lzma/simple/ia64.c"/>
	<file name="../../../../native/lzma/simple/powerpc.c"/>
	<file name="../../../../native/lzma/simple/riscv.c"/>
	<file name="../../../../native/lzma/simple/simple_coder.c"/>
	<file name="../../../../native/lzma/simple/simple_decoder.c"/>
	<file name="../../../../native/lzma/simple/sparc.c"/>
	<file name="../../../../native/lzma/simple/x86.c"/>
</files>
<files id="fnf_archive" c_standard="11">
	<compilerflag value="-utf-8" if="windows"/>
	<compilerflag value="-DHAVE_CONFIG_H"/>
	<compilerflag value="-DLZMA_API_STATIC"/>
	<compilerflag value="-DLIBARCHIVE_STATIC"/>
	<compilerflag value="-I../../../../native/archive"/>
	<compilerflag value="-I../../../../native/lzma/api"/>
	<file name="../../../../native/archive/archive_acl.c"/>
	<file name="../../../../native/archive/archive_blake2s_ref.c"/>
	<file name="../../../../native/archive/archive_blake2sp_ref.c"/>
	<file name="../../../../native/archive/archive_check_magic.c"/>
	<file name="../../../../native/archive/archive_cryptor.c"/>
	<file name="../../../../native/archive/archive_digest.c"/>
	<file name="../../../../native/archive/archive_entry.c"/>
	<file name="../../../../native/archive/archive_entry_sparse.c"/>
	<file name="../../../../native/archive/archive_entry_stat.c"/>
	<file name="../../../../native/archive/archive_entry_strmode.c"/>
	<file name="../../../../native/archive/archive_entry_xattr.c"/>
	<file name="../../../../native/archive/archive_hmac.c"/>
	<file name="../../../../native/archive/archive_options.c"/>
	<file name="../../../../native/archive/archive_ppmd7.c"/>
	<file name="../../../../native/archive/archive_random.c"/>
	<file name="../../../../native/archive/archive_rb.c"/>
	<file name="../../../../native/archive/archive_read.c"/>
	<file name="../../../../native/archive/archive_read_add_passphrase.c"/>
	<file name="../../../../native/archive/archive_read_open_fd.c"/>
	<file name="../../../../native/archive/archive_read_open_filename.c"/>
	<file name="../../../../native/archive/archive_read_set_options.c"/>
	<file name="../../../../native/archive/archive_read_support_filter_none.c"/>
	<file name="../../../../native/archive/archive_read_support_format_7zip.c"/>
	<file name="../../../../native/archive/archive_read_support_format_rar.c"/>
	<file name="../../../../native/archive/archive_read_support_format_rar5.c"/>
	<file name="../../../../native/archive/archive_string.c"/>
	<file name="../../../../native/archive/archive_string_sprintf.c"/>
	<file name="../../../../native/archive/archive_util.c"/>
	<file name="../../../../native/archive/archive_version_details.c"/>
	<file name="../../../../native/archive/archive_virtual.c"/>
	<file name="../../../../native/archive/xxhash.c"/>
	<file name="../../../../native/fnf_archive.c"/>
	<section if="windows">
		<file name="../../../../native/archive/archive_windows.c"/>
	</section>
</files>
<target id="haxe">
	<files id="fnf_lzma"/>
	<files id="fnf_archive"/>
</target>
')
@:keep
extern class NativeArchive
{
	@:native("fnf_arch_open")
	public static function archOpen(path:cpp.ConstCharStar):Int;

	@:native("fnf_arch_close")
	public static function archClose():Void;

	@:native("fnf_arch_next")
	public static function archNext():Int;

	@:native("fnf_arch_name")
	public static function archName():cpp.ConstCharStar;

	@:native("fnf_arch_size")
	public static function archSize():Float;

	@:native("fnf_arch_isdir")
	public static function archIsDir():Int;

	@:native("fnf_arch_extract")
	public static function archExtract(dstPath:cpp.ConstCharStar):Int;

	@:native("fnf_arch_skip")
	public static function archSkip():Int;

	@:native("fnf_arch_error")
	public static function archError():cpp.ConstCharStar;
}
#end
