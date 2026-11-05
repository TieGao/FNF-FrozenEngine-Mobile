package states;

#if BOOT_DATA_ALLOWED
import extension.documentpicker.DocumentPicker;
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
 * 数据包 zip 约定：条目顶层只允许 assets/ content/ mods/ 前缀（与数据根同构，解压即安装）。
 */
class BootDataState extends MusicBeatState
{
	/** 原版数据（base_game）就绪标记：数据包必带、APK 内嵌没有的目录（week2 谱面数据）。 */
	public static final DATA_MARKER:String = 'assets/week2';
	/** 标记在 legacy assets 树内部的相对路径（迁移源校验用）。 */
	public static final MARKER_IN_ASSETS:String = 'week2';
	/** 数据包 zip 内允许的顶层前缀。 */
	public static final ALLOWED_PREFIXES:Array<String> = ['assets/', 'content/', 'mods/'];
	/** iOS 文档选择器的 zip UTI（Android 端忽略类型参数）。 */
	public static final ZIP_UTIS:Array<String> = ['com.pkware.zip-archive', 'public.zip-archive', 'application/zip', 'application/x-zip-compressed'];
	/** 每帧处理时间片（秒），迁移/拷贝/解压共用。 */
	static inline final FRAME_BUDGET:Float = 0.012;

	/** 导入/返回后的去向；null = 回主菜单。Advanced 入口设为回 KEOptionsMenu。 */
	public static var onExit:Void->Void = null;

	var phase:BootPhase = CheckWork;

	// ---- UI ----
	var titleText:FlxText;
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
	var pendingZipPath:String; // DocumentPicker 回调跑在 JNI 线程：只写这个标记，update() 在 GL 线程消费
	var zipInput:FileInput;
	var zipReader:Reader;
	var zipStream:haxe.io.Input; // @:privateAccess 取自 zipReader
	var zipEntries:Int = 0;
	var importedAssetsEntries:Bool = false;

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
		super.create();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		switch (phase)
		{
			case CheckWork | Missing | Ready:
				handleButtons();

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
				// 先删后写：覆盖旧安装（不同 uid）的遗留文件时，删+建能拿到当前 uid 的属主
				if (FileSystem.exists(job.dst))
					try FileSystem.deleteFile(job.dst) catch (e:Dynamic) {}
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
		// ⚠️ DocumentPicker 回调在 JNI 线程：直接碰显示列表会偶发 native 崩溃（SIGTRAP/SIGSEGV），
		// 这里只落标记，update() 的 GL 线程相位里消费。
		DocumentPicker.pick(ZIP_UTIS, function(p:String)
		{
			// 取消时上层回调 null：转空串 sentinel，与"还没返回"区分
			pendingZipPath = (p == null) ? '' : p;
		});
	}

	function openZip(zipPath:String):Void
	{
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

	/** 校验并落盘一个条目（直接流式写盘，不整块驻留内存）。 */
	function processEntry(entry:Entry):Bool
	{
		var name:String = StringTools.replace(entry.fileName, '\\', '/');
		if (name.length == 0 || StringTools.endsWith(name, '/'))
			return true; // 目录条目
		// 安全校验：拒绝绝对路径与上级目录跳转
		if (StringTools.startsWith(name, '/') || name.indexOf('../') >= 0)
			return false;
		var ok:Bool = false;
		for (prefix in ALLOWED_PREFIXES)
			if (StringTools.startsWith(name, prefix))
			{
				ok = true;
				break;
			}
		if (!ok)
			return false;
		if (StringTools.startsWith(name, 'assets/'))
			importedAssetsEntries = true;

		var te:Float = Sys.time();
		try
		{
			var t0:Float = Sys.time();
			ensureParentDirs(name);
			tPrep += Sys.time() - t0;
			writeEntryData(entry, name);
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

	/** 从 zip 流读取一个条目的数据写入目标文件。全程流式：单条目内存恒为 64KB 缓冲，
	 *  DEFLATE 用 InflateImpl 边解压边写（不整条目驻留 raw+data），防 native 内存峰值崩溃。 */
	function writeEntryData(entry:Entry, dstPath:String):Void
	{
		if (tmpBuf == null)
			tmpBuf = Bytes.alloc(65536);
		// 先删后写：覆盖旧安装（不同 uid）的遗留文件时，删+建能拿到当前 uid 的属主
		var t0:Float = Sys.time();
		if (FileSystem.exists(dstPath))
			try FileSystem.deleteFile(dstPath) catch (e:Dynamic) {}
		var out:FileOutput = File.write(dstPath, true);
		tPrep += Sys.time() - t0;
		try
		{
			if (entry.crc32 == null)
			{
				// 数据描述符条目（流式写出的 zip）：长度未知，边解压边写，读完跳过描述符
				if (!entry.compressed)
					throw Language.getPhrase('data.boot.zip.baddescriptor', 'Unsupported zip entry (data descriptor + stored)');
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
				// DEFLATE：流式解压直写。非描述符条目的 crc/csize/usize 都在 local header 里，
				// deflate 数据后直接是下一个条目——绝不能多读，否则 header 错位全包报废
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

	// ================= 文件工具 =================

	function ensureParentDirs(relPath:String):Void
	{
		var parts:Array<String> = relPath.split('/');
		parts.pop(); // 最后一段是文件名
		var cur:String = '';
		for (p in parts)
		{
			cur += (cur.length == 0 ? '' : '/') + p;
			if (!FileSystem.exists(cur))
				FileSystem.createDirectory(cur);
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
		titleText = makeText(40, 90, FlxG.width - 80, '', 34, FlxColor.WHITE, CENTER);
		add(titleText);

		infoText = makeText(40, 190, FlxG.width - 80, '', 20, 0xFFC8C8D8, CENTER);
		add(infoText);

		progressBar = new FlxBar(0, FlxG.height - 26, FlxBarFillDirection.LEFT_TO_RIGHT, FlxG.width, 26);
		progressBar.visible = false;
		add(progressBar);

		statusText = makeText(0, FlxG.height - 60, FlxG.width, '', 20, FlxColor.WHITE, CENTER);
		statusText.visible = false;
		add(statusText);
	}

	function makeText(x:Float, y:Float, width:Float, text:String, size:Int, color:FlxColor, align:FlxTextAlign):FlxText
	{
		var t = new FlxText(x, y, width, text, size);
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
		infoText.text = Language.getPhrase('data.boot.ready.body', 'Base game data and content packs are available.');
		progressBar.visible = false;
		statusText.visible = false;
		addBtn(Language.getPhrase('data.boot.btn.importmore', 'Import more data packs'), FlxG.height - 310);
		addBtn(Language.getPhrase('data.boot.btn.back', 'Back'), FlxG.height - 190);
	}

	function showMissingUI():Void
	{
		phase = Missing;
		progressBar.visible = false;
		statusText.visible = false;

		titleText.text = Language.getPhrase('data.notice.title', 'Base game data not installed');
		infoText.text = Language.getPhrase('data.boot.missing.body', 'Data root: {1}\nTap the button below to import the data pack zip, or\nextract it to the path above with a file manager.', [StorageUtil.getStorageDirectory()]);

		clearAllButtons();
		addBtn(Language.getPhrase('data.boot.btn.import', 'Import data pack zip'), FlxG.height - 320);
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
#end
