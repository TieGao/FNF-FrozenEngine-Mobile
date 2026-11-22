package states;

#if BOOT_DATA_ALLOWED
#if mobile
import extension.documentpicker.DocumentPicker;
#else
import lime.ui.FileDialog;
import lime.ui.FileDialogType;
#end
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.ui.FlxBar;
import flixel.ui.FlxBar.FlxBarFillDirection;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.zip.Entry;
import haxe.zip.Reader;
import backend.ClientPrefs;
import backend.Mods;
import mobile.backend.StorageUtil;
import mobile.backend.TouchUtil;
import objects.MessageBox;
import openfl.utils.Assets as OpenFLAssets;
import sys.FileSystem;
import sys.io.File;

/**
 * 移动端数据包导入/旧版迁移界面（从 MainMenu 缺数据通知或 Advanced → Import Data Pack 进入）。
 *
 * 方案B'：APK 内嵌基础 assets（引擎裸跑所需 ~86MB），TouchPad 图集/xml 等走 FileSystem 直读
 * （CWD = 数据根 /sdcard/.FrozenEngine/）——首启基础资产由 CopyState 全量拷贝到数据根
 * （恢复的真机验证逻辑，见 Main.hx 分流）；本类只负责：
 *  1. 旧版私有目录的 CopyState 全量拷贝 → 迁移到数据根（整树 rename 优先，失败分帧增量复制；
 *     APK/CopyState 已就位的文件跳过，避免旧资源覆盖新版）；
 *  2. assets/replays 始终留在私有目录（回放防篡改，与 Replay.getReplayRootDir 一致）；
 *  3. 原版周数据（base_game，标记 assets/week2）与内容包的 zip 导入 UI（忽略可不再提示）。
 *
 * 数据包 zip 约定：官方包条目顶层只允许 assets/ content/ mods/ 前缀（与数据根同构，解压即安装）。
 * 结构自适应（解压前预扫全部条目头）：官方前缀包原样落数据根；套外层文件夹、裸 mod 内容、
 * mod 合集等民间打包自动重映射进 mods/（裸内容用 zip 文件名当 mod 名）；
 * 垃圾条目（__MACOSX/.DS_Store/Thumbs.db 等）静默跳过。
 */
class BootDataState extends MusicBeatState
{
	/** 原版数据（base_game）就绪标记：数据包必带、APK 内嵌没有的目录（week2 谱面数据）。 */
	public static final DATA_MARKER:String = 'assets/week2';
	/** 标记在 legacy assets 树内部的相对路径（迁移源校验用）。 */
	public static final MARKER_IN_ASSETS:String = 'week2';
	/** 官方模式 zip 允许的顶层前缀（结构自适应重映射后的 mod 包必落在 mods/ 下，不走这里）。 */
	public static final ALLOWED_PREFIXES:Array<String> = ['assets/', 'content/', 'mods/'];
	/** 引擎已知 mod 类别目录（= Mods.ignoreModFolders + Psych 常用的两个），识别 mod 结构用。 */
	static final CATEGORY_FOLDERS:Array<String> = Mods.ignoreModFolders.concat(['custom_notes', 'custom_songs']);
	/** 识别为垃圾的用户压缩附带条目（小写文件名）。 */
	static final JUNK_FILES:Array<String> = ['.ds_store', 'thumbs.db', 'desktop.ini'];
	/** iOS 文档选择器的 zip UTI（Android 端忽略类型参数）。 */
	public static final ZIP_UTIS:Array<String> = ['com.pkware.zip-archive', 'public.zip-archive', 'application/zip', 'application/x-zip-compressed'];
	/** 每帧处理时间片（秒），迁移/拷贝/解压共用。移动端保持小片（MIUI 内存墙+发热）；桌面端解压已是原生
	 *  zlib，放宽到 30ms 换吞吐（导入期间 UI 掉到 ~30fps，全程仅几秒）。 */
	static inline final FRAME_BUDGET:Float = #if mobile 0.012 #else 0.030 #end;
	/** DEFLATE 条目整条读入走一次性原生 inflate 的 compressed 尺寸上限（整条驻留内存）。
	 *  超限/描述符条目（dataSize 未知）退回流式解压。移动端维持 32MB（MIUI 内存墙），桌面放宽到 256MB。 */
	static inline final NATIVE_INFLATE_MAX:Int = #if mobile 33554432 #else 268435456 #end;
	/** 一次性解压的解压后尺寸上限（防 zip 炸弹把整块输出吃进内存）。超出走流式。 */
	static inline final ONESHOT_OUT_MAX:Int = #if mobile 67108864 #else 536870912 #end; // 64MB / 512MB

	/** 导入/返回后的去向；null = 回主菜单。Advanced 入口设为回 KEOptionsMenu。 */
	public static var onExit:Void->Void = null;

	var phase:BootPhase = CheckWork;

	// ---- UI ----
	var titleText:FlxText;
	var rootText:FlxText; // 数据根路径独立行（任何相位常驻，手动解压的用户照着抄）
	var infoText:FlxText;
	var progressBar:FlxBar;
	var statusText:FlxText;
	var btnSprites:Array<FlxSprite> = [];
	var btnTexts:Array<FlxText> = [];

	// ---- 工作队列（迁移 job + 内嵌补拷 job）----
	var jobQueue:Array<{src:String, dst:String, fromEmbedded:Bool}> = [];
	var jobDone:Int = 0;

	// ---- zip 导入（流式）----
	var tmpBuf:Bytes; // 64KB 分块缓冲，全流程复用（native 内存曲线恒定，防 GC 峰值撞 MIUI 内存墙）
	var inflateOutBuf:Bytes; // 流式原生解压的 256KB 输出块（全流程复用）
	var ensuredDirs:Map<String, Bool> = new Map(); // 已确保存在的父目录缓存（免逐段 exists 的 stat 风暴）
	var pendingZipPath:String; // DocumentPicker 回调跑在 JNI 线程：只写这个标记，update() 在 GL 线程消费
	var zipInput:FileInput;
	var zipReader:Reader;
	var zipStream:haxe.io.Input; // @:privateAccess 取自 zipReader
	var zipEntries:Int = 0;
	var importedAssetsEntries:Bool = false;

	// ---- zip 结构自适应（预扫头解析出的重映射规则，解压阶段逐条套用）----
	var zipStrip:Int = 0; // 每条路径先剥掉的公共外层段数
	var zipOfficialMode:Bool = true; // true=官方前缀白名单（原行为）；false=重映射进 mods/
	var zipPrefixMap:Map<String, String> = new Map(); // mods 合集模式：剥后首段（mod 名）-> mods/<改名>/
	var zipBarePrefix:String = ''; // mods 裸内容模式：统一前缀 mods/<zip名>/

	// ---- zip 导入计时取证（慢导入排查：时间在解压 CPU / 写盘 I/O / 头解析，汇总落盘 logs/）----
	var tHeader:Float = 0;
	var tInflate:Float = 0;
	var tCopy:Float = 0;
	var tWrite:Float = 0;
	var tPrep:Float = 0; // exists/delete/open/ensureDirs
	var bytesOut:Int = 0;
	var zipTotalBytes:Float = 0;
	var zipStartedAt:Float = 0;
	var zipPathUsed:String = '';

	override function create()
	{
		FlxG.camera.bgColor = FlxColor.BLACK;
		buildUI();
		runCheck();
		addTouchPad('NONE', 'B');
		super.create();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		switch (phase)
		{
			case CheckWork | Missing | Ready:
				handleButtons();
				// B 键/ESC 返回：只在静止相位放行（迁移/解压中不允许中断）
				if ((phase == Missing || phase == Ready) && controls.BACK)
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					exitBootData();
				}

			case Working:
				processWorkSlice();

			case Extracting:
				processExtractSlice();

			case PickingZip:
				if (pendingZipPath != null)
				{
					var p = pendingZipPath;
					pendingZipPath = null;
					if (p.length == 0)
					{
						phase = Missing;
						showMissingUI();
					}
					else
						openZip(p);
				}

			case Finish:
		}
	}

	// ================= 就绪检测 =================

	/** 原版数据（base_game）是否已导入数据根。 */
	public static function checkBaseGameData():Bool
	{
		return FileSystem.exists(DATA_MARKER) && FileSystem.isDirectory(DATA_MARKER);
	}

	function runCheck():Void
	{
		// 1) 快速路径：旧版私有目录整树 rename（同卷瞬时完成，含旧基础资产与 base_game 数据）
		tryRenameMigrate();

		// 2) 内嵌基础资产补拷（数据根缺什么拷什么；rename 成功后这里通常全跳过）
		//    + rename 失败时的旧拷贝分帧增量复制队列
		jobQueue = collectJobs();
		jobDone = 0;
		if (jobQueue.length > 0)
		{
			showProgressUI();
			phase = Working;
			return;
		}

		finishWork();
	}

	function finishWork():Void
	{
		// 基础资产由 CopyState 保证（Main 分流），这里只看 base_game 数据
		if (checkBaseGameData())
			showReadyUI();
		else
			showMissingUI();
	}

	/** 旧版 CopyState 的落点（旧存储根语义）：android=私有目录，iOS/其它=旧 CWD。 */
	static function legacyStorageRoot():String
	{
		#if android
		return StorageUtil.getPrivateStorageDirectory();
		#elseif ios
		return Path.addTrailingSlash(lime.system.System.documentsDirectory);
		#else
		return Sys.getCwd();
		#end
	}

	function tryRenameMigrate():Void
	{
		var legacyAssets:String = legacyStorageRoot() + 'assets';
		if (!FileSystem.exists(legacyAssets) || !FileSystem.exists(legacyAssets + '/' + MARKER_IN_ASSETS))
			return;
		if (FileSystem.exists('assets'))
			return; // 数据根已有 assets，不整树覆盖

		try
		{
			FileSystem.rename(legacyAssets, 'assets');
			relocateReplaysFromDataRoot();
		}
		catch (e:Dynamic)
		{
			// rename 失败：留待 collectJobs 走分帧增量复制
			trace('[BootData] rename 迁移失败，回退分帧复制: ' + e.message);
		}
	}

	/** 组装工作队列：旧拷贝分帧迁移（仅 rename 失败时；内嵌基础资产由 CopyState 负责）。 */
	function collectJobs():Array<{src:String, dst:String, fromEmbedded:Bool}>
	{
		var jobs:Array<{src:String, dst:String, fromEmbedded:Bool}> = [];

		// 旧拷贝迁移（数据根还没有 base_game 标记时才有意义）
		if (!checkBaseGameData())
		{
			var legacyAssets:String = legacyStorageRoot() + 'assets';
			if (FileSystem.exists(legacyAssets) && FileSystem.exists(legacyAssets + '/' + MARKER_IN_ASSETS))
				jobs = jobs.concat(walkLegacy(legacyAssets, ''));
		}
		return jobs;
	}

	function walkLegacy(absDir:String, relDir:String):Array<{src:String, dst:String, fromEmbedded:Bool}>
	{
		var out:Array<{src:String, dst:String, fromEmbedded:Bool}> = [];
		var entries:Array<String>;
		try
		{
			entries = FileSystem.readDirectory(absDir);
		}
		catch (e:Dynamic)
			return out;

		for (name in entries)
		{
			var rel:String = relDir.length == 0 ? name : relDir + '/' + name;
			if (rel == 'replays' || rel.startsWith('replays/'))
				continue; // 回放不迁移，留在私有目录
			var abs:String = absDir + '/' + name;
			if (FileSystem.isDirectory(abs))
				out = out.concat(walkLegacy(abs, rel));
			else
			{
				// 增量迁移：数据根已有（含 CopyState 先行拷好的内嵌资产）跳过，避免旧资源覆盖新版
				if (!FileSystem.exists('assets/' + rel))
					out.push({src: abs, dst: 'assets/' + rel, fromEmbedded: false});
			}
		}
		return out;
	}

	function processWorkSlice():Void
	{
		var budget:Float = Sys.time() + FRAME_BUDGET;
		while (Sys.time() < budget)
		{
			if (jobDone >= jobQueue.length)
			{
				finishJobs();
				return;
			}
			var job = jobQueue[jobDone];
			try
			{
				ensureParentDirs(job.dst);
				// 先删后写：覆盖旧安装（不同 uid）的遗留文件时，删+建能拿到当前 uid 的属主（FUSE 语义，仅移动端）
				#if android
				if (FileSystem.exists(job.dst))
					try FileSystem.deleteFile(job.dst) catch (e:Dynamic) {}
				#end
				if (job.fromEmbedded)
					File.saveBytes(job.dst, OpenFLAssets.getBytes(job.src));
				else
					File.copy(job.src, job.dst);
			}
			catch (e:Dynamic)
			{
				trace('[BootData] 处理失败: ${job.dst} (${e.message})');
			}
			jobDone++;
		}
		statusText.text = Language.getPhrase('data.boot.copying', 'Preparing base assets {1}/{2}', [jobDone, jobQueue.length]);
		progressBar.percent = (jobDone / jobQueue.length) * 100;
	}

	function finishJobs():Void
	{
		// rename 没走成时，旧拷贝树里可能还留着 replays 与残骸：清理（保留 replays 语义）
		var legacyAssets:String = legacyStorageRoot() + 'assets';
		if (FileSystem.exists(legacyAssets) && FileSystem.exists(legacyAssets + '/' + MARKER_IN_ASSETS))
		{
			relocateReplaysFromLegacy(legacyAssets);
			deleteTree(legacyAssets);
		}
		finishWork();
	}

	/** rename 迁移成功后，把 replays 子树挪回私有目录（防篡改语义）。 */
	function relocateReplaysFromDataRoot():Void
	{
		try
		{
			if (!FileSystem.exists('assets/replays'))
				return;
			var privAssets:String = StorageUtil.getPrivateStorageDirectory() + 'assets';
			if (!FileSystem.exists(privAssets))
				FileSystem.createDirectory(privAssets);
			var dst:String = privAssets + '/replays';
			if (!FileSystem.exists(dst))
				FileSystem.rename('assets/replays', dst);
			// 目标已存在时保留数据根侧，避免误删回放
		}
		catch (e:Dynamic)
		{
			trace('[BootData] replays 迁回私有目录失败: ' + e.message);
		}
	}

	function relocateReplaysFromLegacy(legacyAssets:String):Void
	{
		try
		{
			var src:String = legacyAssets + '/replays';
			if (!FileSystem.exists(src))
				return;
			var privAssets:String = StorageUtil.getPrivateStorageDirectory() + 'assets';
			if (!FileSystem.exists(privAssets))
				FileSystem.createDirectory(privAssets);
			var dst:String = privAssets + '/replays';
			if (!FileSystem.exists(dst))
				FileSystem.rename(src, dst);
		}
		catch (e:Dynamic)
		{
			trace('[BootData] replays 迁回私有目录失败: ' + e.message);
		}
	}

	// ================= zip 导入（流式） =================

	function startZipImport():Void
	{
		phase = PickingZip;
		// 回调可能不在 GL 线程（移动端 JNI / 桌面 lime 线程池）：直接碰显示列表会偶发
		// native 崩溃（SIGTRAP/SIGSEGV），这里只落标记，update() 的 PickingZip 相位里消费。
		#if mobile
		DocumentPicker.pick(ZIP_UTIS, function(p:String)
		{
			// 取消时上层回调 null：转空串 sentinel，与"还没返回"区分
			pendingZipPath = (p == null) ? '' : p;
		});
		#else
		var dialog = new FileDialog();
		dialog.onSelect.add(function(path:String)
		{
			pendingZipPath = path;
		});
		dialog.onCancel.add(function()
		{
			pendingZipPath = ''; // 取消：空串 sentinel
		});
		dialog.browse(FileDialogType.OPEN, 'zip', null,
			Language.getPhrase('data.boot.zip.pick.title', 'Select a data pack or mod zip'));
		#end
	}

	function openZip(zipPath:String):Void
	{
		// 预扫定结构：官方包原样落数据根；套层/裸 mod 包重映射进 mods/；识别不出=拒收
		switch (scanZipRule(zipPath))
		{
			case ScanReject:
				MessageBox.show(Language.getPhrase('mobile_error', 'Error!'),
					Language.getPhrase('data.boot.zip.notmod', 'Cannot recognize a mod or data pack structure in this zip.\nPlease check the zip contents.'),
					MessageBoxType.MESSAGE, null, 8.0);
				phase = Missing;
				return;
			default: // ScanOk 用规则；ScanStrict 保持旧行为
		}
		try
		{
			zipInput = File.read(zipPath, true);
			zipReader = new Reader(zipInput);
			@:privateAccess zipStream = zipReader.i;
			zipEntries = 0;
			importedAssetsEntries = false;
			// 计时取证初始化
			tHeader = tInflate = tCopy = tWrite = tPrep = 0;
			bytesOut = 0;
			zipStartedAt = Sys.time();
			zipPathUsed = zipPath;
			try zipTotalBytes = FileSystem.stat(zipPath).size
			catch (e:Dynamic)
				zipTotalBytes = 0;
			showProgressUI();
			phase = Extracting;
		}
		catch (e:Dynamic)
		{
			MessageBox.show(Language.getPhrase('mobile_error', 'Error!'),
				Language.getPhrase('data.boot.zip.openfail', 'Cannot read zip file:\n{1}', [e.message]), MessageBoxType.MESSAGE, null, 8.0);
			phase = Missing;
		}
	}

	function processExtractSlice():Void
	{
		var budget:Float = Sys.time() + FRAME_BUDGET;
		while (Sys.time() < budget)
		{
			var entry:Entry = null;
			var t0:Float = Sys.time();
			try
			{
				entry = zipReader.readEntryHeader();
			}
			catch (e:Dynamic)
			{
				zipFail(Language.getPhrase('data.boot.zip.fail', 'Extraction failed: {1}', [e.message]));
				return;
			}
			tHeader += Sys.time() - t0;

			if (entry == null)
			{
				zipDone();
				return;
			}

			if (!processEntry(entry))
			{
				zipFail(Language.getPhrase('data.boot.zip.badentry', 'Unexpected file in data pack:\n{1}\nPlease use the official data pack.', [entry.fileName]));
				return;
			}
			zipEntries++;
		}
		statusText.text = Language.getPhrase('data.boot.extracted', 'Extracted {1} files...', [zipEntries]);
		// 真进度：以 zip 流已消费字节为准（tell 精确，含当前条目内部进度）
		if (zipTotalBytes > 0)
			progressBar.percent = Math.min(zipInput.tell() / zipTotalBytes * 100, 100);
		else
			progressBar.percent = (Sys.time() * 40) % 100; // 拿不到大小时退回脉冲
	}

	/** 校验并落盘一个条目（直接流式写盘，不整块驻留内存）。路径先经预扫规则重映射。 */
	function processEntry(entry:Entry):Bool
	{
		var raw:String = entry.fileName;
		if (raw.length == 0 || StringTools.endsWith(raw, '/'))
		{
			// 目录条目：数据段恒空，但流式打包器可能挂数据描述符——统一直播对齐
			skipEntryData(entry, zipStream);
			return true;
		}
		var name:String = normalizeEntryName(raw);
		if (name.length == 0 || isJunkPath(name))
		{
			// ★垃圾条目（desktop.ini/.DS_Store…）可能带非空数据（ADOFAI 包 42B desktop.ini 实锤）：
			//   不把数据从流里吃掉就错位下一头，后续全包报废 "Invalid Zip Data"
			skipEntryData(entry, zipStream);
			return true;
		}
		// 安全校验：拒绝绝对路径与 '..' 段（重映射在原始名上做，剥前缀不可能造出逃逸）
		if (!safeRelativePath(name))
			return false;
		var mapped:String = remapEntryPath(name);
		if (zipOfficialMode)
		{
			if (!startsWithOfficialPrefix(mapped))
				return false;
			if (StringTools.startsWith(mapped, 'assets/'))
				importedAssetsEntries = true;
		}

		var te:Float = Sys.time();
		try
		{
			var t0:Float = Sys.time();
			ensureParentDirs(mapped);
			tPrep += Sys.time() - t0;
			#if android
			writeEntryData(entry, StorageUtil.getStorageDirectory() + mapped);
			#else
			writeEntryData(entry, mapped);
			#end
		}
		catch (e:Dynamic)
		{
			trace('[BootData] 解压写入失败: $name (${e.message})');
		}
		var dt:Float = Sys.time() - te;
		if (dt > 0.3)
			trace('[BootData] slow entry: $name size=${entry.dataSize} comp=${entry.compressed} ${Math.round(dt * 1000)}ms');
		return true;
	}

	/** 从 zip 流读取一个条目的数据写入目标文件。
	 *  cpp：DEFLATE 已知尺寸整条读入一次性原生 zlib 解压（≤NATIVE_INFLATE_MAX/ONESHOT_OUT_MAX），
	 *  超限/描述符走流式原生（64KB 窗口 + 256KB 输出块常驻复用）；移动端整条路径维持小上限防内存峰值。 */
	function writeEntryData(entry:Entry, dstPath:String):Void
	{
		if (tmpBuf == null)
			tmpBuf = Bytes.alloc(65536);
		// 先删后写：覆盖旧安装（不同 uid）的遗留文件时，删+建能拿到当前 uid 的属主（FUSE 语义，仅移动端）
		var t0:Float = Sys.time();
		#if android
		if (FileSystem.exists(dstPath))
			try FileSystem.deleteFile(dstPath) catch (e:Dynamic) {}
		#end
		var out:FileOutput = File.write(dstPath, true);
		tPrep += Sys.time() - t0;
		try
		{
			if (entry.crc32 == null)
			{
				// 数据描述符条目（流式写出的 zip）：长度未知，边解压边写，读完跳过描述符
				if (!entry.compressed)
					throw Language.getPhrase('data.boot.zip.baddescriptor', 'Unsupported zip entry (data descriptor + stored)');
				// cpp 原生 zlib 流式（结束后自动回卷到描述符起点）；非 cpp 兜底 InflateImpl
				#if cpp
				t0 = Sys.time();
				var n:Int = nativeInflateStream(zipStream, out, false);
				tInflate += Sys.time() - t0;
				bytesOut += n;
				#else
				var z = new haxe.zip.InflateImpl(zipStream, false, false);
				while (true)
				{
					t0 = Sys.time();
					var n = z.readBytes(tmpBuf, 0, tmpBuf.length);
					tInflate += Sys.time() - t0;
					t0 = Sys.time();
					out.writeBytes(tmpBuf, 0, n);
					tWrite += Sys.time() - t0;
					bytesOut += n;
					if (n < tmpBuf.length)
						break;
				}
				#end
				// 描述符：crc + csize + usize（可能带 0x08074b50 标记）
				var crc = zipStream.readInt32();
				if (crc == 0x08074b50)
					zipStream.readInt32();
				zipStream.readInt32();
				zipStream.readInt32();
			}
			else if (!entry.compressed)
			{
				// STORED：分块直拷
				var left:Int = entry.dataSize;
				while (left > 0)
				{
					t0 = Sys.time();
					var n:Int = zipStream.readBytes(tmpBuf, 0, left < tmpBuf.length ? left : tmpBuf.length);
					tCopy += Sys.time() - t0;
					t0 = Sys.time();
					out.writeBytes(tmpBuf, 0, n);
					tWrite += Sys.time() - t0;
					bytesOut += n;
					left -= n;
				}
			}
			else
			{
				// DEFLATE。非描述符条目的 crc/csize/usize 都在 local header 里，deflate 数据后
				// 直接是下一个条目——绝不能多读，否则 header 错位全包报废。
				// cpp（桌面+移动）：hxcpp 内置原生 zlib——已知尺寸整条读入一次性解压（实测 ~210MB/s 出）；
				// 超限/描述符/尺寸异常条目退流式原生（86MB/s，内存恒定）。
				// 弃用 lime CFFI deflate：Windows 实测仅 ~15MB/s（90MB 包 inflate 占 14.8s/16.4s）。
				// 非 cpp 兜底保留纯 Haxe InflateImpl（~20MB/s）。
				#if cpp
				if (entry.dataSize > 0 && entry.dataSize <= NATIVE_INFLATE_MAX && entry.fileSize > 0 && entry.fileSize <= ONESHOT_OUT_MAX)
				{
					t0 = Sys.time();
					var raw:Bytes = zipStream.read(entry.dataSize);
					tCopy += Sys.time() - t0;
					t0 = Sys.time();
					var data:Bytes = nativeDecompressOneShot(raw, entry.fileSize, out);
					if (data == null)
					{
						// 声明尺寸装不下整个流（尺寸不可信）：前 entry.fileSize 字节已由 one-shot 落盘，流式续解余量
						t0 = Sys.time();
						var n:Int = nativeInflateStream(zipStream, out, false);
						tInflate += Sys.time() - t0;
						bytesOut += entry.fileSize + n;
					}
					else
					{
						tInflate += Sys.time() - t0;
						if (data.length != entry.fileSize)
							trace('[BootData] 解压长度异常: $dstPath 期待 ${entry.fileSize} 实得 ${data.length}');
						t0 = Sys.time();
						out.writeBytes(data, 0, data.length);
						tWrite += Sys.time() - t0;
						bytesOut += data.length;
					}
				}
				else
				{
					t0 = Sys.time();
					var n:Int = nativeInflateStream(zipStream, out, false);
					tInflate += Sys.time() - t0;
					bytesOut += n;
				}
				#else
				if (entry.dataSize > 0 && entry.dataSize <= NATIVE_INFLATE_MAX)
				{
					t0 = Sys.time();
					var raw:Bytes = zipStream.read(entry.dataSize);
					tCopy += Sys.time() - t0;
					t0 = Sys.time();
					var data:Bytes = lime._internal.format.Deflate.decompress(raw);
					tInflate += Sys.time() - t0;
					if (data == null)
						throw 'native inflate returned null';
					if (entry.fileSize > 0 && data.length != entry.fileSize)
						trace('[BootData] 解压长度异常: $dstPath 期待 ${entry.fileSize} 实得 ${data.length}');
					t0 = Sys.time();
					out.writeBytes(data, 0, data.length);
					tWrite += Sys.time() - t0;
					bytesOut += data.length;
				}
				else
				{
					var z = new haxe.zip.InflateImpl(zipStream, false, false);
					while (true)
					{
						t0 = Sys.time();
						var n = z.readBytes(tmpBuf, 0, tmpBuf.length);
						tInflate += Sys.time() - t0;
						t0 = Sys.time();
						out.writeBytes(tmpBuf, 0, n);
						tWrite += Sys.time() - t0;
						bytesOut += n;
						if (n < tmpBuf.length)
							break;
					}
				}
				#end
			}
			t0 = Sys.time();
			out.close();
			tWrite += Sys.time() - t0;
		}
		catch (e:Dynamic)
		{
			// 异常路径也要关句柄，防 fd 泄漏放大内存问题
			try
				out.close()
			catch (e2:Dynamic) {}
			throw e;
		}
	}

	#if cpp
	/** 原生 zlib 一次性解压（hxcpp 内置 zlib，预分配 expectSize 输出，实测 ~210MB/s）。
	 *  ★fresh stream 的 execute 返回值累计==单次，官方 hxcpp 与 TieGao fork 语义一致。
	 *  返回 null = 声明尺寸装不下整个流（尺寸不可信）：前 expectSize 字节已写入 out、流已回卷到未消费处，
	 *  调用方退 nativeInflateStream 续解余量（bytesOut 记 expectSize）。 */
	function nativeDecompressOneShot(raw:Bytes, expectSize:Int, out:FileOutput):Bytes
	{
		var z = new haxe.zip.Uncompress(-15); // 负 windowBits = raw deflate（zip 条目无 zlib 头）
		var outBuf = Bytes.alloc(expectSize);
		var r = z.execute(raw, 0, outBuf, 0);
		z.close();
		// deflate 流比 header csize 短的"撒谎" zip：把多读的字节回卷，防下一头错位
		var over:Int = raw.length - r.read;
		if (over > 0)
			(cast zipStream:FileInput).seek(-over, sys.io.FileSeek.SeekCur);
		if (!r.done)
		{
			// 输出缓冲写满仍未到流尾：已解出的部分先落盘，避免流式续解漏掉开头
			if (r.write > 0)
				out.writeBytes(outBuf, 0, r.write);
			return null;
		}
		return (r.write == expectSize) ? outBuf : outBuf.sub(0, r.write);
	}

	/** 原生 zlib 流式解压：边喂边解（窗口 64KB/输出块 256KB 常驻复用，内存恒定）。
	 *  out=null 时纯丢弃（预扫跳数据用）。结束后把 st 回卷到 deflate 流末尾，
	 *  描述符/下一头紧随其后可直接读。
	 *  ★TieGao hxcpp fork 的 _hx_inflate_buffer 返回累计 total_in/total_out（官方 hxcpp 4.3.2 是单次增量），
	 *  本方法按累计换算增量——换库/升级 hxcpp 时需同步核对语义。 */
	function nativeInflateStream(st:haxe.io.Input, out:FileOutput, discard:Bool):Int
	{
		if (tmpBuf == null)
			tmpBuf = Bytes.alloc(65536);
		if (inflateOutBuf == null)
			inflateOutBuf = Bytes.alloc(262144);
		var inBuf:Bytes = tmpBuf;
		var outBuf:Bytes = inflateOutBuf;
		var z = new haxe.zip.Uncompress(-15);
		var baseIn:Int = 0;
		var baseOut:Int = 0;
		var pending:Int = 0; // inBuf[0..pending) = 待消费压缩字节
		var fed:Int = 0; // 本条目从 st 累计读入的字节
		var eof:Bool = false;
		var wrote:Int = 0;
		var done:Bool = false;
		while (!done)
		{
			// 补料到窗口满（FileInput.readBytes 单次 fread 可能短读，循环补满；流尾 Eof 收尾）
			while (!eof && pending < inBuf.length)
			{
				var n:Int = 0;
				try
					n = st.readBytes(inBuf, pending, inBuf.length - pending)
				catch (e:haxe.io.Eof)
					eof = true;
				if (!eof && n > 0)
				{
					pending += n;
					fed += n;
				}
			}
			// execute 输入必须右尺寸（CFFI 原语无长度参，见整个缓冲）：窗口满用 inBuf 本体，流尾用右尺寸副本
			var src:Bytes;
			if (pending == inBuf.length)
				src = inBuf;
			else
			{
				if (pending == 0)
					throw 'truncated deflate stream';
				src = Bytes.alloc(pending);
				src.blit(0, inBuf, 0, pending);
			}
			var r = z.execute(src, 0, outBuf, 0);
			var dIn:Int = r.read - baseIn;
			var dOut:Int = r.write - baseOut;
			baseIn = r.read;
			baseOut = r.write;
			if (dOut > 0 && !discard)
				out.writeBytes(outBuf, 0, dOut);
			wrote += dOut;
			if (r.done)
				done = true;
			else if (dIn == 0 && dOut == 0)
				throw 'deflate stream stalled';
			else
			{
				// 未消费部分压回窗口前部
				var left:Int = pending - dIn;
				if (left > 0)
					inBuf.blit(0, inBuf, pending - left, left);
				pending = left;
			}
		}
		z.close();
		// 回卷：已读进缓冲但 deflate 流未消费的字节（描述符/下一头）留在流上
		var over:Int = fed - baseIn;
		if (over > 0)
			(cast st:FileInput).seek(-over, sys.io.FileSeek.SeekCur);
		return wrote;
	}
	#end

	function zipDone():Void
	{
		closeZip();
		dumpZipTiming('done');
		if (checkBaseGameData())
		{
			showReadyUI(true);
			return;
		}
		// 没有标记但导入成功：可选内容分类包（只含 content/mods，无 assets）——
		// 用引擎内 toast 提示（不弹原生对话框，Android 上有卡死前科），停留在导入界面可继续导
		MessageBox.show(Language.getPhrase('data.boot.zip.done.title', 'Import finished'),
			importedAssetsEntries
				? Language.getPhrase('data.boot.zip.incomplete', 'Data pack incomplete (base game data missing).\nPlease use the full data pack.')
				: Language.getPhrase('data.boot.zip.contentok', 'Content pack imported.\nBase game data is still missing;\nimport the full data pack to complete.'),
			MessageBoxType.MESSAGE, null, 6.0);
		showMissingUI();
	}

	function zipFail(msg:String):Void
	{
		closeZip();
		dumpZipTiming('fail');
		MessageBox.show(Language.getPhrase('mobile_error', 'Error!'), msg, MessageBoxType.MESSAGE, null, 8.0);
		showMissingUI();
	}

	/** 导入计时汇总：落 logs/ + trace。慢导入取证用——时间在解压 CPU 还是写盘 I/O 一眼可辨。 */
	function dumpZipTiming(how:String):Void
	{
		var total:Float = Sys.time() - zipStartedAt;
		var msg:String = '[$how] path=$zipPathUsed\n'
			+ 'entries=$zipEntries bytesOut=$bytesOut zipTotal=${Math.round(zipTotalBytes)}\n'
			+ 'wall=' + Math.round(total * 1000) + 'ms'
			+ ' header=' + Math.round(tHeader * 1000)
			+ ' inflate=' + Math.round(tInflate * 1000)
			+ ' copy=' + Math.round(tCopy * 1000)
			+ ' write=' + Math.round(tWrite * 1000)
			+ ' prep=' + Math.round(tPrep * 1000) + '\n';
		trace('[BootData] ' + StringTools.replace(msg, '\n', ' | '));
		try
		{
			if (!FileSystem.exists('logs'))
				FileSystem.createDirectory('logs');
			File.saveContent('logs/' + Date.now().toString().replace(' ', '-').replace(':', "'") + '-BootDataImport.txt', msg);
		}
		catch (e:Dynamic) {}
	}

	function closeZip():Void
	{
		try
			zipInput.close()
		catch (e:Dynamic) {}
		zipInput = null;
		zipReader = null;
		zipStream = null;
	}

	// ================= zip 预扫（结构自适应） =================

	/** 预扫：只解析全部条目头并跳过数据，识别 zip 结构定重映射规则。
	 *  支持民间打包：套外层文件夹（下载目录/版本号包一层）、裸 mod 内容（zip 的是文件夹里面的东西）、
	 *  mod 合集（多个 mod 文件夹平铺）。ScanReject=识别不出任何 mod/数据包结构；ScanStrict=退回旧行为。 */
	function scanZipRule(zipPath:String):ZipScanOutcome
	{
		// 保守默认：任何提前 return 的路径都保持旧行为
		zipStrip = 0;
		zipOfficialMode = true;
		zipBarePrefix = '';
		zipPrefixMap = new Map();

		var names:Array<String> = [];
		var inp:FileInput = null;
		try
			inp = File.read(zipPath, true)
		catch (e:Dynamic)
			return ScanStrict; // 打不开：openZip 会给出更明确的报错
		try
		{
			var r = new Reader(inp);
			var st:haxe.io.Input = null;
			@:privateAccess st = r.i;
			if (tmpBuf == null)
				tmpBuf = Bytes.alloc(65536);
			while (true)
			{
				var e:Entry = r.readEntryHeader();
				if (e == null)
					break;
				var isDir:Bool = StringTools.endsWith(e.fileName, '/');
				var name:String = normalizeEntryName(e.fileName);
				skipEntryData(e, st);
				if (isDir || name.length == 0 || isJunkPath(name))
					continue;
				if (!safeRelativePath(name))
					continue; // 危险条目不参与分类；解压阶段仍会原样拒绝（保持旧报错）
				names.push(name);
			}
		}
		catch (e:Dynamic)
		{
			// 预扫中断（损坏/怪 zip）：退回旧严格模式，让解压阶段给出与从前一致的报错
			trace('[BootData] zip 预扫失败，退回严格官方模式: ' + e.message);
			try
				inp.close()
			catch (e2:Dynamic) {}
			return ScanStrict;
		}
		try
			inp.close()
		catch (e:Dynamic) {}
		return classifyZip(names, zipPath);
	}

	/** 预扫跳过当前条目的数据，让流对齐到下一个条目头。描述符条目长度未知，流式解压丢弃。 */
	function skipEntryData(e:Entry, st:haxe.io.Input):Void
	{
		if (e.crc32 == null)
		{
			// 数据描述符条目：边解压边丢 + 跳过描述符尾（crc+csize+usize，可带 0x08074b50 标记）
			// cpp 走原生 zlib 流式丢弃（nativeInflateStream 结束时已回卷到描述符起点）
			#if cpp
			nativeInflateStream(st, null, true);
			#else
			var z = new haxe.zip.InflateImpl(st, false, false);
			while (true)
			{
				var n = z.readBytes(tmpBuf, 0, tmpBuf.length);
				if (n < tmpBuf.length)
					break;
			}
			#end
			var crc = st.readInt32();
			if (crc == 0x08074b50)
				st.readInt32();
			st.readInt32();
			st.readInt32();
		}
		else if (e.dataSize > 0)
		{
			var fi:FileInput = cast(st, FileInput);
			fi.seek(e.dataSize, sys.io.FileSeek.SeekCur);
		}
	}

	/** 从预扫收集的路径定规则（names 已去掉垃圾条目与危险条目）。 */
	function classifyZip(names:Array<String>, zipPath:String):ZipScanOutcome
	{
		if (names.length == 0)
			return ScanReject; // 空包/全垃圾条目

		// 1) 公共外层前缀深度：所有条目共有的前 N 段目录（N 不吃掉任何条目的文件名）
		var segLists:Array<Array<String>> = [for (n in names) n.split('/')];
		var minDepth:Int = 2147483647;
		for (s in segLists)
			if (s.length < minDepth)
				minDepth = s.length;
		var common:Int = 0;
		while (common < minDepth - 1)
		{
			var seg:String = segLists[0][common];
			var same:Bool = true;
			for (s in segLists)
				if (s[common] != seg)
				{
					same = false;
					break;
				}
			if (!same)
				break;
			common++;
		}

		// 2) 官方前缀判定：从浅到深试剥。全部命中=干净官方包（含套层的）；部分命中=坏条目在
		//    解压阶段原样报"Unexpected file in data pack"（旧严格语义）。
		for (s in 0...(common + 1))
		{
			var hit:Bool = false;
			for (n in names)
			{
				if (startsWithOfficialPrefix(stripSegments(n, s)))
				{
					hit = true;
					break;
				}
			}
			if (hit)
			{
				zipStrip = s;
				zipOfficialMode = true;
				trace('[BootData] zip 预扫: 官方结构，剥 $s 层外层前缀');
				return ScanOk;
			}
		}

		// 3) mod 分类：剥满公共前缀后，裸内容（根级文件或类别目录开头）→mods/<zip名>/；
		//    mod 文件夹/合集→mods/<名>/
		var stripped:Array<String> = [for (n in names) stripSegments(n, common)];
		if (!looksLikeModContent(stripped))
			return ScanReject;

		var bare:Bool = false;
		for (n in stripped)
		{
			if (n.indexOf('/') < 0 || isCategoryFolder(n.substr(0, n.indexOf('/'))))
			{
				bare = true;
				break;
			}
		}
		zipOfficialMode = false;
		zipStrip = common;
		if (bare)
		{
			zipBarePrefix = 'mods/' + sanitizeModFolderName(zipDisplayName(zipPath)) + '/';
			trace('[BootData] zip 预扫: 裸 mod 内容，整体映射到 ' + zipBarePrefix);
		}
		else
		{
			zipBarePrefix = '';
			for (n in stripped)
			{
				var first:String = n.substr(0, n.indexOf('/'));
				if (!zipPrefixMap.exists(first))
					zipPrefixMap.set(first, 'mods/' + sanitizeModFolderName(first) + '/');
			}
			trace('[BootData] zip 预扫: mod 包/合集，剥 $common 层，${Lambda.count(zipPrefixMap)} 个 mod 文件夹');
		}
		return ScanOk;
	}

	/** 解压阶段把 zip 内路径映射到数据根相对路径（规则来自预扫）。 */
	function remapEntryPath(name:String):String
	{
		if (zipOfficialMode)
			return stripSegments(name, zipStrip);
		var stripped:String = stripSegments(name, zipStrip);
		if (zipBarePrefix.length > 0)
			return zipBarePrefix + stripped;
		var segs:Array<String> = stripped.split('/');
		var first:String = segs.shift();
		var prefix:String = zipPrefixMap.get(first);
		if (prefix == null)
			prefix = 'mods/' + sanitizeModFolderName(first) + '/'; // 预扫漏网段兜底
		return prefix + segs.join('/');
	}

	static function startsWithOfficialPrefix(name:String):Bool
	{
		for (prefix in ALLOWED_PREFIXES)
			if (StringTools.startsWith(name, prefix))
				return true;
		return false;
	}

	static function isCategoryFolder(seg:String):Bool
	{
		return CATEGORY_FOLDERS.indexOf(seg.toLowerCase()) >= 0;
	}

	/** mod 结构守卫：至少有一处引擎已知类别目录或 data.json，防任意 zip 被静默装成野 mod。 */
	static function looksLikeModContent(paths:Array<String>):Bool
	{
		for (n in paths)
		{
			var segs:Array<String> = n.toLowerCase().split('/');
			if (segs[segs.length - 1] == 'data.json')
				return true;
			for (s in segs)
				if (isCategoryFolder(s))
					return true;
		}
		return false;
	}

	/** zip 条目名规范化：反斜杠转斜杠、去空段与当前目录段（'a//b'、'a/./b' 噪声）。 */
	static function normalizeEntryName(raw:String):String
	{
		var parts:Array<String> = StringTools.replace(raw, '\\', '/').split('/');
		var out:Array<String> = [];
		for (p in parts)
			if (p.length > 0 && p != '.')
				out.push(p);
		return out.join('/');
	}

	/** 用户压缩常见的垃圾条目（macOS/Windows 附带物），静默跳过不落盘。 */
	static function isJunkPath(name:String):Bool
	{
		var lower:String = name.toLowerCase();
		if (lower.indexOf('__macosx/') == 0 || lower.indexOf('/__macosx/') >= 0)
			return true;
		var base:String = lower.substr(lower.lastIndexOf('/') + 1);
		if (JUNK_FILES.indexOf(base) >= 0)
			return true;
		return StringTools.startsWith(base, '._'); // AppleDouble 资源分叉
	}

	/** 相对路径安全校验：拒绝绝对路径与 '..' 段（比逐字符串查 '../' 更严，堵住 'mods/a/..' 尾段）。 */
	static function safeRelativePath(name:String):Bool
	{
		if (StringTools.startsWith(name, '/'))
			return false;
		for (seg in name.split('/'))
			if (seg == '..')
				return false;
		return true;
	}

	static function stripSegments(name:String, n:Int):String
	{
		if (n <= 0)
			return name;
		var segs:Array<String> = name.split('/');
		if (n >= segs.length)
			return name;
		return segs.slice(n).join('/');
	}

	static function zipDisplayName(zipPath:String):String
	{
		return Path.withoutExtension(Path.withoutDirectory(zipPath));
	}

	/** mod 文件夹名清洗：modsList.txt 用 '|' 分列、换行会断行，路径分隔符也不能混进来。 */
	static function sanitizeModFolderName(s:String):String
	{
		var buf:StringBuf = new StringBuf();
		for (i in 0...s.length)
		{
			var c:Int = s.charCodeAt(i);
			if (c == 0x7C /*|*/ || c == 0x2F /*/*/ || c == 0x5C /*\*/ || c < 0x20)
				c = 0x5F; // '_'
			buf.addChar(c);
		}
		var r:String = StringTools.trim(buf.toString());
		if (r.length == 0 || r == '.' || r == '..')
			r = 'ImportedMod';
		if (r.length > 64)
			r = r.substr(0, 64);
		return r;
	}

	// ================= 文件工具 =================

	function ensureParentDirs(relPath:String):Void
	{
		var parts:Array<String> = relPath.split('/');
		parts.pop(); // 最后一段是文件名
		// 从数据根拼绝对路径，和 CopyState 一致：不依赖进程 CWD，chdir 没生效也不会写错位置
		#if android
		var cur:String = StorageUtil.getStorageDirectory();
		if (cur.endsWith('/')) cur = cur.substr(0, cur.length - 1);
		#else
		var cur:String = '';
		#end
		for (p in parts)
		{
			cur += (cur.length == 0 ? '' : '/') + p;
			// 目录缓存：万级条目的包每条逐段 exists 是 stat 风暴，首建后直接跳过
			if (!ensuredDirs.exists(cur))
			{
				if (!FileSystem.exists(cur))
					FileSystem.createDirectory(cur);
				ensuredDirs.set(cur, true);
			}
		}
	}

	function deleteTree(path:String):Void
	{
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path))
		{
			for (name in FileSystem.readDirectory(path))
				deleteTree(path + '/' + name);
			try
				FileSystem.deleteDirectory(path)
			catch (e:Dynamic)
				trace('[BootData] 无法删除目录 $path: ' + e.message);
		}
		else
		{
			try
				FileSystem.deleteFile(path)
			catch (e:Dynamic)
				trace('[BootData] 无法删除文件 $path: ' + e.message);
		}
	}

	// ================= UI =================

	function buildUI():Void
	{
		// 菜单背景：与主菜单同源 menuBG，覆盖式缩放防露黑边（算法照抄 ModsMenuState）；
		// 导入页文字密度高，加暗化遮罩保证可读
		var menuBg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuBG'));
		menuBg.antialiasing = ClientPrefs.data.antialiasing;
		var coverScale:Float = Math.max(FlxG.width / menuBg.width, FlxG.height / menuBg.height);
		menuBg.setGraphicSize(Std.int(menuBg.width * coverScale), Std.int(menuBg.height * coverScale));
		menuBg.updateHitbox();
		menuBg.screenCenter();
		add(menuBg);

		var dim:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		dim.alpha = 0.45;
		dim.scrollFactor.set();
		add(dim);

		titleText = makeText(40, 64, FlxG.width - 80, '', 34, FlxColor.WHITE, CENTER, true);
		add(titleText);

		rootText = makeText(40, 134, FlxG.width - 80, '', 18, 0xFFC8C8D8, CENTER, true);
		add(rootText);

		infoText = makeText(40, 178, FlxG.width - 80, '', 20, FlxColor.WHITE, CENTER, true);
		add(infoText);

		progressBar = new FlxBar(0, FlxG.height - 26, FlxBarFillDirection.LEFT_TO_RIGHT, FlxG.width, 26);
		progressBar.visible = false;
		add(progressBar);

		statusText = makeText(0, FlxG.height - 60, FlxG.width, '', 20, FlxColor.WHITE, CENTER, true);
		statusText.visible = false;
		add(statusText);
	}

	function makeText(x:Float, y:Float, width:Float, text:String, size:Int, color:FlxColor, align:FlxTextAlign, ?border:Bool = false):FlxText
	{
		var t = new FlxText(x, y, width, text, size);
		if (border)
		{
			t.setFormat(Paths.font('vcr.ttf'), size, color, align, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.borderSize = 2;
		}
		else
			t.setFormat(Paths.font('vcr.ttf'), size, color, align);
		t.scrollFactor.set();
		return t;
	}

	function addBtn(label:String, y:Float):Void
	{
		var w:Int = 620;
		var x:Float = (FlxG.width - w) / 2;
		var spr = new FlxSprite(x, y).makeGraphic(w, 96, 0xFF2E2E44);
		spr.scrollFactor.set();
		add(spr);
		var txt = makeText(x, y + 26, w, label, 24, FlxColor.WHITE, CENTER);
		add(txt);
		btnSprites.push(spr);
		btnTexts.push(txt);
	}

	function clearAllButtons():Void
	{
		for (s in btnSprites)
			remove(s);
		for (t in btnTexts)
			remove(t);
		btnSprites = [];
		btnTexts = [];
	}

	function showProgressUI():Void
	{
		clearAllButtons();
		titleText.text = Language.getPhrase('data.boot.preparing', 'Preparing data');
		rootText.text = '';
		infoText.text = '';
		statusText.text = '';
		progressBar.percent = 0;
		progressBar.visible = true;
		statusText.visible = true;
	}

	/** 原版数据就绪：可继续导分类包，也可返回。 */
	function showReadyUI(?imported:Bool = false):Void
	{
		phase = Ready;
		clearAllButtons();
		titleText.text = Language.getPhrase('data.boot.ready.title', 'Data is ready');
		rootText.text = Language.getPhrase('data.boot.root', 'Data root: {1}', [StorageUtil.getStorageDirectory()]);
		infoText.text = Language.getPhrase('data.boot.ready.body', 'Base game data and content packs are available.\nYou can import more content or mod packs anytime.');
		progressBar.visible = false;
		statusText.visible = false;
		addBtn(Language.getPhrase('data.boot.btn.importmore', 'Import more data / mod packs'), FlxG.height - 310);
		addBtn(Language.getPhrase('data.boot.btn.back', 'Back'), FlxG.height - 190);
	}

	function showMissingUI():Void
	{
		phase = Missing;
		progressBar.visible = false;
		statusText.visible = false;

		titleText.text = Language.getPhrase('data.notice.title', 'Base game data not installed');
		rootText.text = Language.getPhrase('data.boot.root', 'Data root: {1}', [StorageUtil.getStorageDirectory()]);
		// 三种导入形态都支持：FE 完整数据包 / 内容包 / mod 压缩包（官方结构或民间套层打包均可）
		infoText.text = Language.getPhrase('data.boot.missing.body',
			'Import from here:\n• FE data pack (base game + content)\n• Content packs & mod zips (folder-wrapped OK)\nOr extract the pack to the data root above with a file manager.');

		clearAllButtons();
		addBtn(Language.getPhrase('data.boot.btn.import', 'Import data / mod pack zip'), FlxG.height - 320);
		addBtn(Language.getPhrase('data.boot.btn.ignore', 'Ignore and don\'t ask again'), FlxG.height - 200);
		addBtn(Language.getPhrase('data.boot.btn.back', 'Back'), FlxG.height - 90);
	}

	function handleButtons():Void
	{
		for (i in 0...btnSprites.length)
		{
			if (!btnSprites[i].visible)
				continue;
			var pressed:Bool = (TouchUtil.justPressed && TouchUtil.overlaps(btnSprites[i]))
				|| (FlxG.mouse.justPressed && FlxG.mouse.overlaps(btnSprites[i]));
			if (pressed)
			{
				if (phase == Ready)
				{
					// 就绪页：0=继续导入（回导入界面） 1=返回
					if (i == 0)
						showMissingUI();
					else
						exitBootData();
					return;
				}
				switch (i)
				{
					case 0:
						startZipImport();
					case 1:
						// 忽略并不再提示：主菜单的缺失 MessageBox 从此不再弹
						if (FlxG.save.data != null)
						{
							FlxG.save.data.dataNoticeIgnored = true;
							FlxG.save.flush();
						}
						exitBootData();
					default:
						exitBootData();
				}
				return;
			}
		}
	}

	function exitBootData():Void
	{
		phase = Finish;
		if (onExit != null)
		{
			var cb = onExit;
			onExit = null;
			cb();
		}
		else
			MusicBeatState.switchState(new MainMenuState());
	}

	function finishBoot():Void
	{
		phase = Finish;
		// 数据就绪，进入游戏（后续 TitleState 自行加载资源）
		MusicBeatState.switchState(new TitleState());
	}
}

enum BootPhase
{
	CheckWork;
	Working;
	Ready;
	Missing;
	PickingZip;
	Extracting;
	Finish;
}

/** zip 预扫结果：ScanOk=重映射规则可用；ScanStrict=退回旧行为；ScanReject=识别不出结构，拒收。 */
enum ZipScanOutcome
{
	ScanOk;
	ScanStrict;
	ScanReject;
}
#end
