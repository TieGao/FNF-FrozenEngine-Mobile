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
import openfl.utils.Assets as OpenFLAssets;
import sys.FileSystem;
import sys.io.File;

/**
 * 移动端首启数据准备 + 数据包导入界面。
 *
 * 方案B'：APK 内嵌基础 assets（引擎裸跑所需 ~86MB），但 TouchPad 图集、语言/周文本等
 * 大量读取走 FileSystem（CWD = 数据根 /sdcard/.FrozenEngine/）——首启数据根是空的，
 * 所以保留 CopyState 语义：启动时把内嵌基础资产拷到数据根（旧 CopyState 全量拷贝的精简版）。
 *
 * 两条进入路径：
 *  - 自动（Main 启动分流）：基础资产未就绪 → 拷贝/迁移完成后直接进 TitleState；
 *  - 手动（MainMenu 缺数据通知 / Advanced → Import Data Pack）：带界面，
 *    可选导数据包 zip / 忽略并不再提示 / 返回。
 *
 * 处理顺序（runCheck）：
 *  1. 旧版私有目录有 CopyState 全量拷贝 → 整树 rename 到数据根（同卷瞬时，含旧基础资产与 base_game 数据）；
 *     rename 失败回退为分帧增量复制（APK 内嵌已有的路径跳过，避免旧资源覆盖新版）；
 *  2. 内嵌基础资产逐条补拷（数据根缺什么拷什么）；
 *  3. assets/replays 始终留在私有目录（回放防篡改，与 Replay.getReplayRootDir 一致）；
 *  4. 原版周数据（base_game，标记 assets/week2）仍缺 → 显示导入 UI（数据包 zip）。
 *
 * 数据包 zip 约定：条目顶层只允许 assets/ content/ mods/ 前缀（与数据根同构，解压即安装）。
 */
class BootDataState extends MusicBeatState
{
	/** 基础资产就绪标记（APK 内嵌必带；数据根存在 = 引擎可跑，Main 启动分流用）。 */
	public static final BASE_ASSETS_MARKER:String = 'assets/shared/images/logoBumpin.png';
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
	/** true = 从主菜单通知/设置菜单进入（带 UI，完成后停在提示页）；false = 首启自动进入（完成直接进游戏）。 */
	public static var enteredFromMenu:Bool = false;

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
	var zipInput:FileInput;
	var zipReader:Reader;
	var zipStream:haxe.io.Input; // @:privateAccess 取自 zipReader
	var zipEntries:Int = 0;
	var importedAssetsEntries:Bool = false;

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

			case PickingZip | Finish:
		}
	}

	// ================= 就绪检测 =================

	/** 基础资产是否已就绪（Main 启动分流用）。 */
	public static function checkBaseAssetsReady():Bool
	{
		return FileSystem.exists(BASE_ASSETS_MARKER);
	}

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
		// 基础资产就绪 = 引擎可跑；base_game 数据另算（缺则主菜单会弹通知）
		if (!checkBaseAssetsReady())
		{
			// 内嵌资产都没有（异常 APK）——照旧进游戏让崩溃处理接管，不做死循环
			finishBoot();
			return;
		}

		if (!enteredFromMenu && checkBaseGameData())
		{
			// 首启自动进入且原版数据已随迁移就位：无需停留，直接进游戏
			finishBoot();
			return;
		}

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

	/** 组装工作队列：内嵌补拷 + 旧拷贝分帧迁移（仅 rename 失败时）。 */
	function collectJobs():Array<{src:String, dst:String, fromEmbedded:Bool}>
	{
		var jobs:Array<{src:String, dst:String, fromEmbedded:Bool}> = [];

		// a) 内嵌基础资产补拷
		for (asset in OpenFLAssets.list())
		{
			if (!StringTools.startsWith(asset, 'assets/'))
				continue;
			if (!FileSystem.exists(asset))
				jobs.push({src: asset, dst: asset, fromEmbedded: true});
		}

		// b) 旧拷贝迁移（数据根还没有 base_game 标记时才有意义）
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
				// 增量迁移：数据根已有（含刚补拷的内嵌资产）跳过，避免旧资源覆盖新版
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
		DocumentPicker.pick(ZIP_UTIS, function(p:String)
		{
			if (p == null)
			{
				phase = Missing;
				return;
			}
			openZip(p);
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
			showProgressUI();
			phase = Extracting;
		}
		catch (e:Dynamic)
		{
			CoolUtil.showPopUp(Language.getPhrase('data.boot.zip.openfail', 'Cannot read zip file:\n{1}', [e.message]), Language.getPhrase('mobile_error', "Error!"));
			phase = Missing;
		}
	}

	function processExtractSlice():Void
	{
		var budget:Float = Sys.time() + FRAME_BUDGET;
		while (Sys.time() < budget)
		{
			var entry:Entry = null;
			try
			{
				entry = zipReader.readEntryHeader();
			}
			catch (e:Dynamic)
			{
				zipFail(Language.getPhrase('data.boot.zip.fail', 'Extraction failed: {1}', [e.message]));
				return;
			}

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
		progressBar.percent = (Sys.time() * 40) % 100; // 总量未知，脉冲式进度
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

		try
		{
			ensureParentDirs(name);
			writeEntryData(entry, name);
		}
		catch (e:Dynamic)
		{
			trace('[BootData] 解压写入失败: $name (${e.message})');
		}
		return true;
	}

	/** 从 zip 流读取一个条目的数据写入目标文件（对应 std Reader.read 的单条目逻辑）。 */
	function writeEntryData(entry:Entry, dstPath:String):Void
	{
		var out:FileOutput = File.write(dstPath, true);
		var tmp:Bytes = Bytes.alloc(65536);
		if (entry.crc32 == null)
		{
			// 数据描述符条目（流式写出的 zip）：长度未知，边解压边写，读完跳过描述符
			if (!entry.compressed)
				throw Language.getPhrase('data.boot.zip.baddescriptor', 'Unsupported zip entry (data descriptor + stored)');
			var z = new haxe.zip.InflateImpl(zipStream, false, false);
			while (true)
			{
				var n = z.readBytes(tmp, 0, tmp.length);
				out.writeBytes(tmp, 0, n);
				if (n < tmp.length)
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
				var n:Int = zipStream.readBytes(tmp, 0, left < tmp.length ? left : tmp.length);
				out.writeBytes(tmp, 0, n);
				left -= n;
			}
		}
		else
		{
			// DEFLATE：读出压缩块，交 zlib 解压（cpp 原生实现，快）
			var raw:Bytes = zipStream.read(entry.dataSize);
			entry.data = raw;
			var data:Bytes = Reader.unzip(entry);
			out.writeBytes(data, 0, data.length);
		}
		out.close();
	}

	function zipDone():Void
	{
		closeZip();
		if (checkBaseGameData())
		{
			if (enteredFromMenu)
				showReadyUI();
			else
				finishBoot();
			return;
		}
		// 没有标记但导入成功：可能是可选内容分类包（只含 content/mods，无 assets）
		CoolUtil.showPopUp(importedAssetsEntries
			? Language.getPhrase('data.boot.zip.incomplete', 'Data pack incomplete (base game data missing).\nPlease use the full data pack.')
			: Language.getPhrase('data.boot.zip.contentok', 'Content pack imported.\nBase game data is still missing;\nimport the full data pack to complete.'),
			Language.getPhrase('mobile_notice', 'Notice!'));
		showMissingUI();
	}

	function zipFail(msg:String):Void
	{
		closeZip();
		CoolUtil.showPopUp(msg, Language.getPhrase('mobile_error', "Error!"));
		showMissingUI();
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

	/** 数据就绪：提示后点任意处返回（仅菜单进入）。 */
	function showReadyUI():Void
	{
		phase = Ready;
		clearAllButtons();
		titleText.text = Language.getPhrase('data.boot.ready.title', 'Data is ready');
		infoText.text = Language.getPhrase('data.boot.ready.body', 'Base game data and content packs are available.');
		progressBar.visible = false;
		statusText.visible = false;
		addBtn(Language.getPhrase('data.boot.btn.back', 'Back'), FlxG.height - 200);
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
