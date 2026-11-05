/*
 * Copyright (C) 2025 Mobile Porting Team
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package states;

#if COPYSTATE_ALLOWED
import states.TitleState;
import lime.utils.Assets as LimeAssets;
import openfl.utils.Assets as OpenFLAssets;
import openfl.utils.ByteArray;
import haxe.io.Path;
import flixel.ui.FlxBar;
import flixel.ui.FlxBar.FlxBarFillDirection;
import lime.system.ThreadPool;
import objects.MessageBox;

/**
 * ...
 * @author: Karim Akra
 */
class CopyState extends MusicBeatState
{
	private static final textFilesExtensions:Array<String> = ['ini', 'txt', 'xml', 'hxs', 'hx', 'lua', 'json', 'frag', 'vert'];
	public static final IGNORE_FOLDER_FILE_NAME:String = "CopyState-Ignore.txt";
	/** 数据根资产版本标记：与 APK version 不一致 → 全量重拷（升级覆盖，防新旧资产混搭炸 TouchPad/xml 成对读取） */
	public static final VERSION_FILE:String = 'assets/.fe-version';
	public static var forceRecopy:Bool = false;
	public static var currentVersion:String = '';
	private static var directoriesToIgnore:Array<String> = [];
	public static var locatedFiles:Array<String> = [];
	public static var maxLoopTimes:Int = 0;

	public var loadingImage:FlxSprite;
	public var loadingBar:FlxBar;
	public var loadedText:FlxText;
	public var thread:ThreadPool;

	var failedFilesStack:Array<String> = [];
	var failedFiles:Array<String> = [];
	var shouldCopy:Bool = false;
	var canUpdate:Bool = true;
	var loopTimes:Int = 0;

	override function create()
	{
		locatedFiles = [];
		maxLoopTimes = 0;
		checkExistingFiles();
		if (maxLoopTimes <= 0)
		{
			MusicBeatState.switchState(new TitleState());
			return;
		}

		#if ios
		// iOS: 直接开始复制，不显示弹窗
		shouldCopy = true;
		#else
		// 其他平台: 显示弹窗询问
		CoolUtil.showPopUp("Seems like you have some missing files that are necessary to run the game\nPress OK to begin the copy process", Language.getPhrase('mobile_notice', 'Notice!'));
		shouldCopy = true;
		#end

		add(new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xffcaff4d));

		loadingImage = new FlxSprite(0, 0, Paths.image('funkay'));
		loadingImage.setGraphicSize(0, FlxG.height);
		loadingImage.updateHitbox();
		loadingImage.screenCenter();
		add(loadingImage);

		loadingBar = new FlxBar(0, FlxG.height - 26, FlxBarFillDirection.LEFT_TO_RIGHT, FlxG.width, 26);
		loadingBar.setRange(0, maxLoopTimes);
		add(loadingBar);

		loadedText = new FlxText(loadingBar.x, loadingBar.y + 4, FlxG.width, '', 16);
		loadedText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER);
		add(loadedText);

		thread = new ThreadPool(0, CoolUtil.getCPUThreadsCount());
		thread.doWork.add(function(poop)
		{
			for (file in locatedFiles)
			{
				loopTimes++;
				copyAsset(file);
			}
		});
		new FlxTimer().start(0.5, (tmr) ->
		{
			thread.queue({});
		});

		super.create();
	}

	override function update(elapsed:Float)
	{
		if (shouldCopy)
		{
			if (loopTimes >= maxLoopTimes && canUpdate)
			{
				if (failedFiles.length > 0)
				{
					// 不走原生弹窗（iOS 部分 system version 上 window.alert 的 OK 点不动会永久卡死），
					// 改非阻塞 toast；完整失败清单仍落盘 logs/
					final folder:String = #if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'logs/';
					if (!FileSystem.exists(folder))
						FileSystem.createDirectory(folder);
					final logFile:String = folder + Date.now().toString().replace(' ', '-').replace(':', "'") + '-CopyState' + '.txt';
					File.saveContent(logFile, failedFilesStack.join('\n'));
					MessageBox.show('Failed To Copy ${failedFiles.length} File.',
						'See ${Path.withoutDirectory(logFile)} in the logs folder.', MessageBoxType.MESSAGE, null, 8.0);
				}

				// 拷贝完成：写版本标记（防升级混搭机制的写端——此前只有读端，每次启动都会全量重拷）
				try File.saveContent(VERSION_FILE, currentVersion != null ? currentVersion : '')
				catch (e:Dynamic) trace('[CopyState] 写 $VERSION_FILE 失败: $e');

				FlxG.sound.play(Paths.sound('confirmMenu')).onComplete = () ->
				{
					MusicBeatState.switchState(new TitleState());
				};
		
				canUpdate = false;
			}

			if (loopTimes >= maxLoopTimes)
				loadedText.text = "Completed!";
			else
				loadedText.text = '$loopTimes/$maxLoopTimes';

			loadingBar.percent = Math.min((loopTimes / maxLoopTimes) * 100, 100);
		}
		super.update(elapsed);
	}

	public function copyAsset(file:String)
	{
		if (forceRecopy || !FileSystem.exists(file))
		{
			var directory = Path.directory(file);
			if (!FileSystem.exists(directory))
				FileSystem.createDirectory(directory);
			try
			{
				if (OpenFLAssets.exists(getFile(file)))
				{
					if (textFilesExtensions.contains(Path.extension(file)))
						createContentFromInternal(file);
					else
					{
						var path:String = '';
						#if android
						if (file.startsWith('mods/'))
							path = StorageUtil.getExternalStorageDirectory() + file;
						else
						#end
							path = file;
						// 先删后写：覆盖旧安装（不同 uid）的遗留文件时，删+建能拿到当前 uid 的属主
						if (FileSystem.exists(path))
							try FileSystem.deleteFile(path) catch (e:Dynamic) {}
						File.saveBytes(path, getFileBytes(getFile(file)));
					}		
				}
				else
				{
					failedFiles.push(getFile(file) + " (File Dosen't Exist)");
					failedFilesStack.push('Asset ${getFile(file)} does not exist.');
				}
			}
			catch (e:haxe.Exception)
			{
				failedFiles.push('${getFile(file)} (${e.message})');
				failedFilesStack.push('${getFile(file)} (${e.stack})');
			}
		}
	}

	public function createContentFromInternal(file:String)
	{
		var fileName = Path.withoutDirectory(file);
		var directory = Path.directory(file);
		#if android
		if (fileName.startsWith('mods/'))
			directory = StorageUtil.getExternalStorageDirectory() + directory;
		#end
		try
		{
			var fileData:String = OpenFLAssets.getText(getFile(file));
			if (fileData == null)
				fileData = '';
			if (!FileSystem.exists(directory))
				FileSystem.createDirectory(directory);
			// 先删后写：同 copyAsset，保证重装后文件属主回到当前 uid
			var target:String = Path.join([directory, fileName]);
			if (FileSystem.exists(target))
				try FileSystem.deleteFile(target) catch (e:Dynamic) {}
			File.saveContent(target, fileData);
		}
		catch (e:haxe.Exception)
		{
			failedFiles.push('${getFile(file)} (${e.message})');
			failedFilesStack.push('${getFile(file)} (${e.stack})');
		}
	}

	public function getFileBytes(file:String):ByteArray
	{
		switch (Path.extension(file).toLowerCase())
		{
			case 'otf' | 'ttf':
				// 字体没有字节内嵌（生成代码里项目字体是 __fontPath 路径引用，@:font 内嵌只有 haxelib 库字体有），
				// 包里是散文件：android/desktop 走 lime C++ 文件层 fromFile 能读到；
				// iOS 上相对路径解析不到 bundle → fromFile 返回 null → saveBytes(null) 抛异常
				// → 7 个字体每次必进失败清单。失败时用 bundle 绝对路径直读兜底。
				var bytes:ByteArray = ByteArray.fromFile(file);
				if (bytes == null || bytes.length <= 0)
				{
					try
					{
						var dir:String = lime.system.System.applicationDirectory;
						if (dir != null && dir.length > 0 && !StringTools.endsWith(dir, '/'))
							dir += '/';
						bytes = ByteArray.fromBytes(File.getBytes(dir + file));
					}
					catch (e:Dynamic)
						bytes = null;
				}
				return bytes;
			default:
				return OpenFLAssets.getBytes(file);
		}
	}

	public static function getFile(file:String):String
	{
		if (OpenFLAssets.exists(file))
			return file;

		@:privateAccess
		for (library in LimeAssets.libraries.keys())
		{
			if (OpenFLAssets.exists('$library:$file') && library != 'default')
				return '$library:$file';
		}

		return file;
	}

	public static function checkExistingFiles():Bool
	{
		locatedFiles = OpenFLAssets.list();

		// 方案B'：数据根记录的资产版本与 APK 不一致 → 忽略"已存在"检查全量重拷。
		// 否则覆盖安装后旧版拷下的基础资产不会被新版覆盖，新旧混搭（PsychUI/xml 成对读取错版本）会炸。
		forceRecopy = false;
		try
		{
			currentVersion = openfl.Lib.application.meta.get('version');
			if (currentVersion == null) currentVersion = '';
		}
		catch (e:Dynamic)
			currentVersion = '';
		if (FileSystem.exists(VERSION_FILE))
		{
			var storedVersion:String = '';
			var versionReadable:Bool = true;
			try storedVersion = File.getContent(VERSION_FILE).trim()
			catch (e:Dynamic)
			{
				// stat 命中但读不出：重装换 uid / 坏拷贝 —— 视为版本失配强制重拷（新 uid 重写）
				versionReadable = false;
				forceRecopy = true;
				trace('[CopyState] $VERSION_FILE 不可读（$e），数据根资产对当前安装已失效 → 强制重拷');
			}
			if (versionReadable && storedVersion != currentVersion)
				forceRecopy = true;
		}
		else
			forceRecopy = true;

		// removes unwanted assets
		var assets = locatedFiles.filter(folder -> folder.startsWith('assets/'));
		var mods = locatedFiles.filter(folder -> folder.startsWith('mods/'));
		locatedFiles = assets.concat(mods);
		if (!forceRecopy)
			locatedFiles = locatedFiles.filter(file -> !FileSystem.exists(file));
		#if android
		for (file in locatedFiles)
			if (file.startsWith('mods/'))
				locatedFiles = locatedFiles.filter(file -> !FileSystem.exists(StorageUtil.getExternalStorageDirectory() + file));
		#end

		var filesToRemove:Array<String> = [];

		for (file in locatedFiles)
		{
			if (filesToRemove.contains(file))
				continue;

			if(file.endsWith(IGNORE_FOLDER_FILE_NAME) && !directoriesToIgnore.contains(Path.directory(file)))
				directoriesToIgnore.push(Path.directory(file));

			if (directoriesToIgnore.length > 0)
			{
				for (directory in directoriesToIgnore)
				{
					if (file.startsWith(directory))
						filesToRemove.push(file);
				}
			}
		}

		locatedFiles = locatedFiles.filter(file -> !filesToRemove.contains(file));

		maxLoopTimes = locatedFiles.length;

		return (maxLoopTimes <= 0);
	}
}
#end