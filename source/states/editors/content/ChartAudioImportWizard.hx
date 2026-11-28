package states.editors.content;

import flash.net.FileFilter;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * 分步向导式音频导入底座（Open Chart / Import Chart / New Song 共用）。
 *
 * 只负责：弹「Inst → Player Vocals → Opponent Vocals」三步文件选择框，
 * 把用户选到的音频复制成目标目录里的 inst.<ext> / voices-player.<ext> / voices-opponent.<ext>，
 * 然后通过 onDone 回报落地结果。
 *
 * 【判定口径】只有「谱面自己声明的音轨」（osu AudioFilename / osz 解包结果）和「引擎管理的
 * 谱面目录（content/CustomCharts、assets、mods）」里的音频会被自动认。外部散落目录
 * （下载目录这种混杂了多首歌的地方）一律要求手动选 Inst / Player / Opponent ——
 * 按名字猜只会命中别的歌的 Inst.ogg。
 *
 * 【重要】用户在选择框里明确选中的文件一定算数：目标名空闲就直接落成规范名；同名文件已存在
 * 且内容不是同一份时，外部目录不覆盖，改落成 <名>-imported.<ext> 并通过调用方的显式路径播放。
 * 绝不静默丢弃，否则调用方会判成「没导入」并要求再导一次。
 *
 * 【重要】本类不写任何 Paths.current* 全局字段，也不碰调用方的 FileDialogHandler。
 * 调用方须在 onDone 里自行登记目录（setChartDirectoryFromPath / Paths.setChartContext）
 * 再 loadChart / prepareReload，才不会覆盖调用方自己的 category/variant 上下文。
 *
 * 自带一个私有 FileDialogHandler 实例，与 ChartingState.fileDialog 隔离。
 * onDone 保证恰好回调一次（含全跳过 / 复制失败 / 非 sys 平台降级）。
 */
typedef ChartAudioImportResult = {
	/** 规范化后的落地目录（结尾带 '/'） */
	var targetDir:String;
	/** 落地后的 inst 文件绝对路径；未导入为 null */
	var instPath:Null<String>;
	/** 落地后的 player vocals 文件；未导入为 null */
	var playerVocalPath:Null<String>;
	/** 落地后的 opponent vocals 文件；未导入为 null */
	var opponentVocalPath:Null<String>;
	/** 三者至少一个成功 */
	var anyImported:Bool;
	/** 目标目录里最终是否有可用 Inst（含 osz 已自动落地的情况）；false 时调用方应拦截打开 */
	var hasInst:Bool;
	/** 过程中值得让用户知道的事（替换/改存 *-imported、复制失败、格式不支持），调用方负责输出 */
	var warnings:Array<String>;
	/** 本次落地用的人声 postfix —— 调用方登记显式人声路径时必须用同一把键 */
	var playerPostfix:String;
	var opponentPostfix:String;
}

class ChartAudioImportWizard
{
	/**
	 * 是否弹 Player / Opponent 两步人声选择框。默认 true；调用方目前一律开着 ——
	 * 要不要人声由玩家在向导里决定（取消这两步就按没人声导入），不看谱面 needsVoices。
	 */
	public var importVocals:Bool = true;
	/**
	 * 目标文件已存在时是否用选中的文件替换。默认 false：外部目录可能和别的歌共用，
	 * 覆盖就等于毁掉别人的音轨。false 时改落成「名-imported.ext」，由调用方的
	 * 显式路径播放（不静默丢弃，也不会误报「没导入」）。
	 * 引擎管理的谱面目录 / 新建谱面 / 转换后保存的输出目录可以设 true。
	 */
	public var overwrite:Bool = false;
	/** 人声落地文件名 postfix，须与 characterData.vocalsP1/vocalsP2 对齐。默认 Player/Opponent。 */
	public var playerPostfix:String = 'Player';
	public var opponentPostfix:String = 'Opponent';
	/**
	 * 谱面自己声明的音轨文件绝对路径（如 .osu 的 AudioFilename 解析结果）。
	 * 设了之后只认这一条，不按通用文件名在目标目录里找 —— 谱面散落在下载目录时，
	 * 通用名会命中上一次导入留下的无关音轨。声明文件缺失时返回 null，由调用方弹选择框。
	 */
	public var declaredAudioPath:Null<String> = null;
	/**
	 * 是否自动认目标目录里已有的音频。
	 * 引擎管理的谱面目录（content/CustomCharts、assets、mods）设 true：音频与谱面同放，可信。
	 * 外部散落目录设 false：下载目录这类地方混杂着多首歌，按名字命中别人的 Inst.ogg 毫无意义，
	 * 一律要求手动选 Inst / Player / Opponent。谱面自己声明了音轨（declaredAudioPath）时不受此开关影响。
	 */
	public var allowFolderScan:Bool = true;

	var _dlg:FileDialogHandler;
	var _dir:String;
	var _result:ChartAudioImportResult;
	var _onDone:ChartAudioImportResult->Void;
	var _steps:Array<String>;
	var _idx:Int = 0;
	var _finished:Bool = true;

	public function new() {}

	/**
	 * 启动向导。targetDir = 谱面 JSON 所在目录（或将要保存到的目录），结尾斜杠有无均可。
	 * 异步：onDone 可能在多帧之后（等原生对话框）才触发。
	 */
	public function start(targetDir:String, onDone:ChartAudioImportResult->Void):Void
	{
		if (!_finished) return; // 上一轮未结束，忽略重复启动

		_dir = StringTools.replace(targetDir == null ? '' : targetDir, '\\', '/');
		if (_dir.length > 0 && !_dir.endsWith('/')) _dir += '/';

		_onDone = onDone;
		_idx = 0;
		_finished = false;
		_result = {
			targetDir: _dir,
			instPath: null,
			playerVocalPath: null,
			opponentVocalPath: null,
			anyImported: false,
			hasInst: false,
			warnings: [],
			playerPostfix: playerPostfix,
			opponentPostfix: opponentPostfix
		};

		#if sys
		// 引擎管理的谱面目录（allowFolderScan）先探测已有音频，只为「缺失」的步骤弹框；
		// 外部散落目录不探测，Inst / 人声都要用户手选。谱面声明了音轨时只认那一条。
		var existingInst:Null<String> = findExistingAudio('inst');
		if (existingInst != null)
		{
			_result.instPath = existingInst;
			_result.hasInst = true;
			ensurePlayableInst(existingInst);
		}
		var existingP:Null<String> = importVocals ? findExistingAudio('player') : null;
		if (existingP != null) _result.playerVocalPath = existingP;
		var existingO:Null<String> = importVocals ? findExistingAudio('opponent') : null;
		if (existingO != null) _result.opponentVocalPath = existingO;

		_steps = [];
		if (existingInst == null) _steps.push('inst');
		if (importVocals)
		{
			if (existingP == null) _steps.push('player');
			if (existingO == null) _steps.push('opponent');
		}

		if (_steps.length > 0)
		{
			_dlg = new FileDialogHandler();
			// 音频是二进制：不要让 FileDialogHandler 把整首曲子当 UTF-8 文本读一遍
			// （白占内存，个别文件还会在解码时抛异常，回调断掉就成了「选了没反应」）。
			_dlg.readData = false;
			nextStep();
		}
		else finish();
		#else
		// 非 sys 平台（HTML5）：FileDialogHandler.path 只有文件名、无 sys.io.File
		finish();
		#end
	}

	/** 外部中止（立即以当前已落地结果回调 onDone）。 */
	public function cancel():Void
	{
		finish();
	}

	function stepTitle(step:String):String
	{
		var n:Int = _idx + 1;
		var total:Int = _steps.length;
		return switch (step)
		{
			case 'inst': 'Step $n/$total: Open Instrumental (Inst) - Cancel to skip';
			case 'player': 'Step $n/$total: Open PLAYER Vocals - Cancel to skip';
			case 'opponent': 'Step $n/$total: Open OPPONENT Vocals - Cancel to skip';
			default: 'Step $n/$total: Open Audio - Cancel to skip';
		};
	}

	#if sys
	function nextStep():Void
	{
		if (_finished) return;
		if (_idx >= _steps.length)
		{
			finish();
			return;
		}

		var step:String = _steps[_idx];

		// FileDialogHandler.onCancelFn 的实现是 `if(onCancel != null) onError();`
		// （检查 onCancel 却调 onError），所以 onCancel 和 onError 必须都传非 null，
		// 取消 / IO 错误才会可靠地走到 skip。
		var skip:Void->Void = function()
		{
			_idx++;
			nextStep();
		};

		_dlg.open(null, stepTitle(step), [new FileFilter('Audio (ogg/mp3)', '*.ogg;*.mp3')],
			function()
			{
				try
				{
					var src:String = _dlg.path;
					if (src != null && src.length > 0)
						copyAudio(step, StringTools.replace(src, '\\', '/'));
				}
				catch (e:Dynamic)
				{
					trace('[ChartAudioImportWizard] read failed: $e');
				}
				_idx++;
				nextStep(); // 此刻 completed 已为 true，可安全开下一步
			},
			skip, // onCancel
			skip  // onError
		);
	}

	/**
	 * 落地用户选中（或已存在）的一条音轨。
	 *
	 * 历史 bug：目标名已存在时直接 return，结果里什么都不记 —— 调用方拿到 hasInst=false，
	 * 弹「没选中 Inst」再要求导一次，而用户其实刚导完（文件就在那儿），形成死循环。
	 * 现在三条路都会把结果写进 _result：
	 *   选中的就是目标文件 → 直接采纳；
	 *   目标空闲 → 复制成规范名；
	 *   目标被别的文件占着 → 允许覆盖的目录直接替换，否则落成 <名>-imported.<ext>（绝不静默丢弃）。
	 */
	function copyAudio(step:String, src:String):Void
	{
		if (_dir.length < 1)
		{
			warn('No target folder for the $step audio, skipped.');
			return;
		}

		var ext:Null<String> = audioExtension(src);
		if (ext == null)
		{
			// 老代码会把任何后缀（wav/flac…）硬写成 .ogg，产出播不了的文件还报成功
			warn('Unsupported audio format, skipped: ${fileNameOf(src)} (only .ogg / .mp3).');
			return;
		}

		var name:String = switch (step)
		{
			case 'inst': 'inst' + ext;
			case 'player': 'voices-' + playerPostfix.toLowerCase() + ext;
			case 'opponent': 'voices-' + opponentPostfix.toLowerCase() + ext;
			default: return;
		};

		var dst:String = _dir + name;
		if (hasUsableFile(dst))
		{
			// 用户挑中的就是目标文件本身（重复打开同一个谱面目录时最常见），别 copy 自己
			if (isSameFile(src, dst))
			{
				accept(step, dst);
				return;
			}
			if (!overwrite)
			{
				// 这个槽位已经被别的文件占着（外部混装目录里很可能是另一首歌的音轨）：
				// 不覆盖别人的文件，改落成 <名>-imported.<ext>，由调用方的显式路径播放。
				var fallback:String = _dir + importedName(step, ext);
				try
				{
					File.copy(src, fallback);
					accept(step, fallback);
					_result.anyImported = true;
					warn('$name is already used by another file; imported as ${fileNameOf(fallback)} instead.');
				}
				catch (e:Dynamic)
				{
					warn('Could not import ${fileNameOf(src)} ($e).');
				}
				return;
			}
		}

		var existed:Bool = hasUsableFile(dst);
		try
		{
			File.copy(src, dst);
			accept(step, dst);
			_result.anyImported = true;
			if (existed) warn('$name was replaced with ${fileNameOf(src)}.');
		}
		catch (e:Dynamic)
		{
			if (hasUsableFile(dst))
			{
				// 覆盖失败（占用/只读）但目标位置本来就是可用音频：沿用它，总比判成「没导入」好
				accept(step, dst);
				warn('Could not replace $name ($e), kept the existing file.');
			}
			else warn('Copy failed: ${fileNameOf(src)} -> $name ($e).');
		}
	}

	/** 规范名被占用时的落盘名：-imported 后缀，明确属于「本次导入」。 */
	function importedName(step:String, ext:String):String
	{
		return switch (step)
		{
			case 'player': 'voices-' + playerPostfix.toLowerCase() + '-imported' + ext;
			case 'opponent': 'voices-' + opponentPostfix.toLowerCase() + '-imported' + ext;
			default: 'inst-imported' + ext;
		}
	}

	/** 把某一步的结果登记进 _result（Inst 顺带置 hasInst）。 */
	function accept(step:String, path:String):Void
	{
		switch (step)
		{
			case 'inst':
				_result.instPath = path;
				_result.hasInst = true;
			case 'player':
				_result.playerVocalPath = path;
			case 'opponent':
				_result.opponentVocalPath = path;
			default:
		}
	}

	function warn(message:String):Void
	{
		trace('[ChartAudioImportWizard] $message');
		if (_result != null && _result.warnings != null) _result.warnings.push(message);
	}

	/**
	 * 声明的音轨文件名可能不是 Paths.inst() 认识的候选名（例如 osu 用 track.ogg），
	 * 此时复制成目标目录的 inst.<ext>，否则谱面能载入却只会播 beep。
	 * 音轨本来就在目标目录里时不做这件事：复制没有意义，还会往多首混放的目录里多造文件，
	 * 调用方已经用显式路径指向它了。
	 */
	function ensurePlayableInst(src:String):Void
	{
		if (_dir.length < 1) return;
		if (isUnderDir(src, _dir)) return;

		var name:String = src.substring(src.lastIndexOf('/') + 1).toLowerCase();
		if (name == 'inst.ogg' || name == 'inst.mp3' || name == 'audio.ogg' || name == 'audio.mp3') return;

		var ext:Null<String> = audioExtension(src);
		if (ext == null) return;

		var dst:String = _dir + 'inst' + ext;
		try
		{
			// 目标名已被别处音轨占用时保留声明的原始文件，交给调用方的显式音轨路径使用
			if (!hasUsableFile(dst))
			{
				File.copy(src, dst);
				accept('inst', dst);
			}
		}
		catch (e:Dynamic)
		{
			warn('Declared audio copy failed: ${fileNameOf(src)} -> inst$ext ($e).');
		}
	}

	/**
	 * 探测已有音轨。谱面声明了音轨就只认那一条文件；否则仅在 allowFolderScan（引擎管理的
	 * 谱面目录）时按 Paths.inst()/voices() 的候选口径找目录里的音频。命中返回完整路径，否则 null。
	 */
	function findExistingAudio(step:String):Null<String>
	{
		if (declaredAudioPath != null && declaredAudioPath.length > 0)
		{
			if (step == 'inst') return hasUsableFile(declaredAudioPath) ? declaredAudioPath : null;
			return null;
		}
		// 外部散落目录不猜：混杂目录里按名字命中别人的音轨，比什么都不认更糟
		if (!allowFolderScan) return null;
		if (_dir.length < 1) return null;

		return findFirstExisting(audioNames(step));
	}

	function findFirstExisting(names:Array<String>):Null<String>
	{
		for (name in names)
		{
			var p:String = _dir + name;
			if (hasUsableFile(p)) return p;
		}
		return null;
	}

	/** 各步的候选文件名，口径与 Paths.inst() / voices() 的目录分支一致。 */
	function audioNames(step:String):Array<String>
	{
		switch (step)
		{
			case 'inst':
				return ['inst.ogg', 'inst.mp3', 'Inst.ogg', 'Inst.mp3',
					'audio.ogg', 'audio.mp3', 'Audio.ogg', 'Audio.mp3',
					'song/inst.ogg', 'song/inst.mp3', 'song/Inst.ogg', 'song/Inst.mp3',
					'song/audio.ogg', 'song/audio.mp3', 'song/Audio.ogg', 'song/Audio.mp3'];
			case 'player':
				return voiceNames(playerPostfix);
			case 'opponent':
				return voiceNames(opponentPostfix);
			default:
				return [];
		}
	}

	function voiceNames(postfix:String):Array<String>
	{
		var lower:String = postfix.toLowerCase();
		var names:Array<String> = [];
		for (ext in ['.ogg', '.mp3'])
		{
			names.push('voices-$lower$ext');
			names.push('Voices-$postfix$ext');
			names.push('song/voices-$lower$ext');
			names.push('song/Voices-$postfix$ext');
			// 无后缀的共用名：同一份文件会被 P1/P2 各播一遍，管理目录里通常也是这么放的，认了更省事
			names.push('voices$ext');
			names.push('Voices$ext');
			names.push('vocals$ext');
			names.push('Vocals$ext');
			names.push('song/voices$ext');
			names.push('song/vocals$ext');
		}
		return names;
	}

	/** 文件存在且非空（0 字节多半是上次复制失败的残骸，不能当作「已有音频」）。 */
	function hasUsableFile(path:String):Bool
	{
		if (path == null || path.length < 1) return false;
		try
		{
			if (!FileSystem.exists(path) || FileSystem.isDirectory(path)) return false;
			return FileSystem.stat(path).size > 0;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	static function audioExtension(src:String):Null<String>
	{
		if (src == null || src.length < 1) return null;
		var slash:Int = src.lastIndexOf('/');
		var backslash:Int = src.lastIndexOf('\\');
		if (backslash > slash) slash = backslash;
		var dot:Int = src.lastIndexOf('.');
		if (dot < slash) return null;
		return switch (src.substr(dot + 1).toLowerCase())
		{
			case 'ogg': '.ogg';
			case 'mp3': '.mp3';
			default: null;
		}
	}

	static function fileNameOf(src:String):String
	{
		if (src == null) return '(null)';
		var slash:Int = src.lastIndexOf('/');
		var backslash:Int = src.lastIndexOf('\\');
		if (backslash > slash) slash = backslash;
		return src.substr(slash + 1);
	}

	/** 同一个文件？Windows 上大小写不敏感，否则 Inst.ogg 与 inst.ogg 会被当成两个文件。 */
	static function isSameFile(a:String, b:String):Bool
	{
		if (a == null || b == null) return false;
		var na:String = normalizePath(a);
		var nb:String = normalizePath(b);
		#if windows
		return na.toLowerCase() == nb.toLowerCase();
		#else
		return na == nb;
		#end
	}

	/** src 是否已经在 dir 目录里（Windows 大小写不敏感）。 */
	static function isUnderDir(src:String, dir:String):Bool
	{
		if (src == null || dir == null || dir.length < 1) return false;
		var np:String = normalizePath(src);
		var nd:String = normalizePath(dir);
		if (!nd.endsWith('/')) nd += '/';
		#if windows
		return np.toLowerCase().indexOf(nd.toLowerCase()) == 0;
		#else
		return np.indexOf(nd) == 0;
		#end
	}

	static function normalizePath(path:String):String
	{
		var s:String = StringTools.replace(path, '\\', '/');
		while (s.indexOf('//') >= 0) s = StringTools.replace(s, '//', '/');
		while (s.indexOf('./') == 0) s = s.substr(2);
		return s;
	}
	#end

	function finish():Void
	{
		if (_finished) return;
		_finished = true;

		#if sys
		if (_dlg != null)
		{
			_dlg.destroy();
			_dlg = null;
		}
		// Inst 可用 = 本次复制成功，或目标目录本来就有（audio.mp3 / inst.ogg / osz 解包落地）
		if (!_result.hasInst && findExistingAudio('inst') != null)
			_result.hasInst = true;
		#end
		if (_result.instPath != null) _result.hasInst = true;

		if (_onDone != null)
		{
			var cb = _onDone;
			_onDone = null;
			try
			{
				cb(_result);
			}
			catch (e:Dynamic)
			{
				trace('[ChartAudioImportWizard] onDone error: $e');
			}
		}
	}
}
