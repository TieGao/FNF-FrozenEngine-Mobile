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
 * 移动端首屏数据引导（替代旧 CopyState）。
 *
 * 方案A：APK 不再内嵌 assets/content/mods，数据全部外置到数据根
 * （android = /sdcard/.FrozenEngine/，= 游戏 CWD，与桌面运行目录同构）。
 * 启动时检测数据根：
 *  1. 已就绪（存在标记文件）→ 直接进 TitleState；
 *  2. 旧版本把 assets 拷进了私有目录（旧 CopyState 行为）→ 迁移到数据根：
 *     rename 优先（同卷瞬时完成），失败回退为分帧复制；assets/replays 始终
 *     留在私有目录不迁移（回放防篡改语义，与 Replay.getReplayRootDir 一致）；
 *  3. 无数据 → 引导屏：游戏内导入数据包 zip / 重新检测 / 手动解压路径说明。
 *
 * 数据包 zip 约定：条目顶层只允许 assets/ content/ mods/ 前缀（与数据根同构，
 * 解压即安装），防止误选无关 zip 把数据根写脏。
 */
class BootDataState extends MusicBeatState
{
	/** 数据就绪标记：数据包必带、读取成本低的文件（标题 logo）。 */
	public static final DATA_MARKER:String = 'assets/shared/images/logoBumpin.png';
	/** 标记文件在 assets 树内部的相对路径（迁移源校验用）。 */
	public static final MARKER_IN_ASSETS:String = 'shared/images/logoBumpin.png';
	/** 数据包 zip 内允许的顶层前缀。 */
	public static final ALLOWED_PREFIXES:Array<String> = ['assets/', 'content/', 'mods/'];
	/** iOS 文档选择器的 zip UTI（Android 端忽略类型参数）。 */
	public static final ZIP_UTIS:Array<String> = ['com.pkware.zip-archive', 'public.zip-archive', 'application/zip', 'application/x-zip-compressed'];
	/** 内嵌启动字体（Project.xml 以 type=binary 打包，getBytes 可靠）。 */
	public static final BOOT_FONT_ASSET:String = 'assets/boot/cjk.ttf';
	/** 每帧处理时间片（秒），迁移与解压共用，保证引导屏不掉帧死机观感。 */
	static inline final FRAME_BUDGET:Float = 0.012;

	var phase:BootPhase = CheckMigrate;

	// ---- UI ----
	var bgColorVisual:FlxSprite;
	var bootFontPath:String;
	var titleText:FlxText;
	var infoText:FlxText;
	var hintText:FlxText;
	var progressBar:FlxBar;
	var statusText:FlxText;
	var btnSprites:Array<FlxSprite> = [];
	var btnTexts:Array<FlxText> = [];

	// ---- 迁移（分帧复制回退）----
	var migrateQueue:Array<String> = []; // 相对 legacy assets 树的路径
	var migrateDone:Int = 0;

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
			case CheckMigrate | Missing:
				handleButtons();

			case Migrating:
				processMigrateSlice();

			case Extracting:
				processExtractSlice();

			case PickingZip | Finish:
		}
	}

	// ================= 检测 / 迁移 =================

	/** 数据根是否已就绪（供 Main 启动分流调用）。 */
	public static function checkDataInstalled():Bool
	{
		return FileSystem.exists(DATA_MARKER);
	}

	function runCheck():Void
	{
		if (checkDataInstalled())
		{
			finishBoot();
			return;
		}

		// 快速路径：整树 rename（同卷瞬时完成）
		if (tryRenameMigrate())
		{
			finishBoot();
			return;
		}

		// 慢速路径：旧拷贝存在但 rename 失败 → 分帧复制（排除 replays）
		migrateQueue = collectMigrateFiles();
		migrateDone = 0;
		if (migrateQueue.length > 0)
		{
			showProgressUI('迁移旧数据...');
			phase = Migrating;
		}
		else
		{
			showMissingUI();
			phase = Missing;
		}
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

	function tryRenameMigrate():Bool
	{
		var legacyAssets:String = legacyStorageRoot() + 'assets';
		if (!FileSystem.exists(legacyAssets) || !FileSystem.exists(legacyAssets + '/' + MARKER_IN_ASSETS))
			return false;
		if (FileSystem.exists('assets'))
			return false; // 数据根已有 assets，不覆盖

		try
		{
			FileSystem.rename(legacyAssets, 'assets');
		}
		catch (e:Dynamic)
		{
			return false; // 回退到分帧复制
		}
		relocateReplaysFromDataRoot();
		return checkDataInstalled();
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

	function collectMigrateFiles():Array<String>
	{
		var legacyAssets:String = legacyStorageRoot() + 'assets';
		if (!FileSystem.exists(legacyAssets) || !FileSystem.exists(legacyAssets + '/' + MARKER_IN_ASSETS))
			return [];
		return walkDir(legacyAssets, ''); // 相对 legacy assets 的路径列表（排除 replays）
	}

	function walkDir(absDir:String, relDir:String):Array<String>
	{
		var out:Array<String> = [];
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
				out = out.concat(walkDir(abs, rel));
			else
				out.push(rel);
		}
		return out;
	}

	function processMigrateSlice():Void
	{
		var legacyAssets:String = legacyStorageRoot() + 'assets';
		var budget:Float = Sys.time() + FRAME_BUDGET;
		while (Sys.time() < budget)
		{
			if (migrateDone >= migrateQueue.length)
			{
				finishMigrate();
				return;
			}
			var rel:String = migrateQueue[migrateDone];
			try
			{
				var dstRel:String = 'assets/' + rel;
				ensureParentDirs(dstRel);
				File.copy(legacyAssets + '/' + rel, dstRel);
			}
			catch (e:Dynamic)
			{
				trace('[BootData] 迁移失败: $rel (${e.message})');
			}
			migrateDone++;
		}
		statusText.text = '迁移旧数据 $migrateDone/${migrateQueue.length}';
		progressBar.percent = (migrateDone / migrateQueue.length) * 100;
	}

	function finishMigrate():Void
	{
		// replays 留在原地（legacy 树内），先挪回私有语义位置再清理
		var legacyAssets:String = legacyStorageRoot() + 'assets';
		relocateReplaysFromLegacy(legacyAssets);
		deleteTree(legacyAssets);

		if (checkDataInstalled())
			finishBoot();
		else
		{
			showMissingUI();
			phase = Missing;
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
			showProgressUI('解压数据包...');
			phase = Extracting;
		}
		catch (e:Dynamic)
		{
			CoolUtil.showPopUp('无法读取 zip 文件：\n${e.message}', '错误');
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
				zipFail('解压失败：${e.message}');
				return;
			}

			if (entry == null)
			{
				zipDone();
				return;
			}

			if (!processEntry(entry))
			{
				zipFail('数据包内含非预期文件：\n${entry.fileName}\n请使用官方数据包。');
				return;
			}
			zipEntries++;
		}
		statusText.text = '已解压 $zipEntries 个文件...';
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
		try
		{
			if (entry.crc32 == null)
			{
				// 数据描述符条目（流式写出的 zip）：长度未知，边解压边写，读完跳过描述符
				if (!entry.compressed)
					throw '不支持的 zip 条目（数据描述符 + 无压缩）';
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
		}
		catch (e:Dynamic)
		{
			throw e;
		}
		out.close();
	}

	function zipDone():Void
	{
		closeZip();
		if (checkDataInstalled())
		{
			finishBoot();
			return;
		}
		// 没有标记但导入成功：可能是可选内容分类包（只含 content/mods，无 assets）
		CoolUtil.showPopUp(importedAssetsEntries
			? '数据包不完整（缺少游戏资源必需文件），\n请使用完整数据包重试。'
			: '内容包已导入。\n但游戏资源（assets）仍缺失，\n请先导入完整数据包后才能启动。', '提示');
		showMissingUI();
		phase = Missing;
	}

	function zipFail(msg:String):Void
	{
		closeZip();
		CoolUtil.showPopUp(msg, '错误');
		showMissingUI();
		phase = Missing;
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
		bootFontPath = extractBootFont();

		bgColorVisual = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xFF101018);
		bgColorVisual.scrollFactor.set();
		add(bgColorVisual);

		titleText = makeText(40, 90, FlxG.width - 80, '', 34, FlxColor.WHITE, CENTER);
		add(titleText);

		infoText = makeText(40, 190, FlxG.width - 80, '', 20, 0xFFC8C8D8, CENTER);
		add(infoText);

		hintText = makeText(40, 0, FlxG.width - 80, '', 16, 0xFF8888A0, CENTER);
		add(hintText);

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
		// bootFontPath 为 null（字体解压失败）时回落 flixel 默认字体
		t.setFormat(bootFontPath, size, color, align);
		t.scrollFactor.set();
		return t;
	}

	/** 把内嵌 CJK 字体解到私有目录，返回真实文件路径（数据未就绪时 Paths.font 不可用）。 */
	function extractBootFont():String
	{
		try
		{
			var p:String = StorageUtil.getPrivateStorageDirectory() + 'boot-cjk.ttf';
			if (!FileSystem.exists(p))
			{
				if (!OpenFLAssets.exists(BOOT_FONT_ASSET))
					return null;
				File.saveBytes(p, OpenFLAssets.getBytes(BOOT_FONT_ASSET));
			}
			return p;
		}
		catch (e:Dynamic)
		{
			trace('[BootData] 启动字体解压失败: ' + e.message);
			return null;
		}
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

	function setButtonsVisible(visible:Bool):Void
	{
		for (s in btnSprites)
			s.visible = visible;
		for (t in btnTexts)
			t.visible = visible;
	}

	function showMissingUI():Void
	{
		progressBar.visible = false;
		statusText.visible = false;

		titleText.text = '游戏数据未安装';
		infoText.text = '数据根目录：' + StorageUtil.getStorageDirectory()
			+ '\n点击下方按钮导入数据包 zip，或用电脑 / 文件管理器\n将数据包解压到上述目录后重新启动。';
		hintText.text = 'English: Import the data pack zip below, or extract it to the path above.';

		if (btnSprites.length == 0)
		{
			addBtn('导入数据包 zip', FlxG.height - 270);
			addBtn('重新检测', FlxG.height - 150);
		}
		else
			setButtonsVisible(true);
	}

	function showProgressUI(initial:String):Void
	{
		setButtonsVisible(false);
		titleText.text = '正在准备数据';
		infoText.text = '';
		hintText.text = '';
		statusText.text = initial;
		progressBar.percent = 0;
		progressBar.visible = true;
		statusText.visible = true;
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
				if (i == 0)
					startZipImport();
				else
				{
					// 重新检测：数据根可能已被外部解压/填充
					phase = CheckMigrate;
					showProgressUI('检测数据...');
					new FlxTimer().start(0.05, function(_)
					{
						runCheck();
					});
				}
				return;
			}
		}
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
	CheckMigrate;
	Migrating;
	Missing;
	PickingZip;
	Extracting;
	Finish;
}
#end
