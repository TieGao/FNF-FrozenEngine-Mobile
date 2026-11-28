package backend;

import backend.Mods;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * content/ 目录下的可管理条目（一个包 / 一个自定义谱面分类）。
 * path 是相对 content/ 的路径（如 VanillaSongs/Erect），也是 contentList.txt 里的键。
 */
typedef ContentPackInfo = {
	var path:String;
	var group:String;
	var name:String;
	/** 包根 pack.json 里声明的显示名；没声明时为 null（菜单退回目录名）。 */
	var displayName:String;
	/** 包自身版本号（pack.json 的 version）；没声明时为 null。 */
	var version:String;
	/** 包要求的最低引擎版本（pack.json 的 minEngineVersion）；没声明时为 null。 */
	var minEngineVersion:String;
	/** 该包下扫到的曲目目录数；0 = 没扫到（自定义谱面分类常为空）。 */
	var songs:Int;
}

/**
 * Content 体系（content/<大类>/<包>）的启用状态管理 —— mods 那套的平行实现。
 *
 * 与 mods/ 的区别：
 *  - mods 靠 modsList.txt 的**顺序**决定覆盖优先级，改完必须重启游戏（资源已缓存进内存）；
 *  - content 包只影响「扫描发现」：Freeplay / Story 每次进入都会重新扫盘
 *    （WeekData.reloadWeekFiles / CustomChartData.load），所以开关**不需要重启**。
 *
 * 落盘文件 contentList.txt 与 modsList.txt 同级，格式同为 `路径|1(启用)/0(禁用)`；
 * 首次运行自动扫盘补全（新包默认启用），目录被删掉的条目自动剔除。
 */
class ContentPacks
{
	public static final LIST_FILE:String = 'contentList.txt';
	/**
	 * 内容包自描述文件（包根下，与 mods/ 的 pack.json 同名同格式）。
	 * 关心的字段：name / description / version / minEngineVersion / color / iconFramerate / restart。
	 * version + minEngineVersion 是给玩家看版本用的，见 ModsMenu 的 CONTENT 页。
	 */
	public static final MANIFEST_FILE:String = 'pack.json';

	static var cachedDisabled:Map<String, Bool> = null;
	static var cachedPacks:Array<ContentPackInfo> = null;
	static var cachedManifests:Map<String, Dynamic> = null;

	/** 清掉内存缓存（改完配置 / 外部改动过目录后调用）。 */
	public static function invalidate():Void
	{
		cachedDisabled = null;
		cachedPacks = null;
		cachedManifests = null;
	}

	/** 扫盘列出所有 content/<大类>/<子目录>，顺序与磁盘一致。 */
	public static function listPacks():Array<ContentPackInfo>
	{
		if (cachedPacks != null) return cachedPacks;

		var result:Array<ContentPackInfo> = [];
		#if sys
		var root:String = Paths.CONTENT_ROOT;
		if (FileSystem.exists(root) && FileSystem.isDirectory(root))
		{
			for (group in Paths.readDirectory(root))
			{
				if (group.startsWith('.')) continue;
				var groupPath:String = '$root/$group';
				if (!FileSystem.isDirectory(groupPath)) continue;

				for (name in Paths.readDirectory(groupPath))
				{
					if (name.startsWith('.')) continue;
					var path:String = '$groupPath/$name';
					if (!FileSystem.isDirectory(path)) continue;
					if (!isPackDirectory(path)) continue;
					var manifest:Dynamic = readManifest(path);
					result.push({
						path: '$group/$name',
						group: group,
						name: name,
						displayName: manifestString(manifest, 'name'),
						version: manifestString(manifest, 'version'),
						minEngineVersion: manifestString(manifest, 'minEngineVersion'),
						songs: countSongs(path)
					});
				}
			}
		}
		#end
		cachedPacks = result;
		return result;
	}

	/** 取单个条目的扫描信息（找不到返回 null）。 */
	public static function getInfo(path:String):ContentPackInfo
	{
		if (path == null || path.length == 0) return null;
		for (info in listPacks())
			if (info.path == path) return info;
		return null;
	}

	// ============================================================
	//  包清单（pack.json）与版本号
	// ============================================================

	/**
	 * 读某个包根目录下的 pack.json（带内存缓存，改包后 invalidate()）。
	 * 解析失败 / 文件不存在返回 null —— 菜单会退回目录名与默认配色。
	 * @param root 包根目录（绝对路径或相对工作目录，如 content/VanillaSongs/Erect）
	 */
	public static function readManifest(root:String):Dynamic
	{
		if (root == null || root.length < 1) return null;
		if (cachedManifests == null) cachedManifests = new Map<String, Dynamic>();
		if (cachedManifests.exists(root)) return cachedManifests.get(root);

		var data:Dynamic = null;
		#if sys
		var path:String = '$root/$MANIFEST_FILE';
		if (FileSystem.exists(path))
		{
			try
			{
				var raw:String = File.getContent(path);
				if (raw != null && raw.trim().length > 0) data = tjson.TJSON.parse(raw);
			}
			catch (e:Dynamic) trace('Failed to parse $path: $e');
		}
		#end
		cachedManifests.set(root, data);
		return data;
	}

	/** 从清单里取一个非空字符串字段；没有 / 类型不对 / 空串都返回 null。 */
	public static function manifestString(data:Dynamic, key:String):String
	{
		if (data == null) return null;
		var value:Dynamic = Reflect.field(data, key);
		if (value == null || !Std.isOfType(value, String)) return null;
		var str:String = (cast value:String).trim();
		return str.length > 0 ? str : null;
	}

	/** 引擎自身版本（Project.xml 的 app version）；读不到时返回 '0.0.0'。 */
	public static function engineVersion():String
	{
		try
		{
			var value:Dynamic = lime.app.Application.current.meta.get('version');
			if (value != null && Std.string(value).length > 0) return Std.string(value);
		}
		catch (e:Dynamic) {}
		return '0.0.0';
	}

	/**
	 * 比较两个版本号，返回 -1（a 比 b 旧）/ 0（相等）/ 1（a 比 b 新）。
	 * 只比数字段：'v1.2.3'、'1.2'、'1.2.3-beta' 都认，短的一边缺位按 0 补齐。
	 */
	public static function compareVersions(a:String, b:String):Int
	{
		var pa:Array<Int> = versionParts(a);
		var pb:Array<Int> = versionParts(b);
		var len:Int = Std.int(Math.max(pa.length, pb.length));
		for (i in 0...len)
		{
			var na:Int = i < pa.length ? pa[i] : 0;
			var nb:Int = i < pb.length ? pb[i] : 0;
			if (na != nb) return na < nb ? -1 : 1;
		}
		return 0;
	}

	/** 'v1.2.3-beta' → [1,2,3]（遇到第一个非数字非点的字符就截断）。 */
	static function versionParts(version:String):Array<Int>
	{
		var result:Array<Int> = [];
		if (version == null) return result;

		var str:String = version.trim();
		if (str.startsWith('v') || str.startsWith('V')) str = str.substr(1);

		var digits:StringBuf = new StringBuf();
		for (i in 0...str.length)
		{
			var ch:String = str.charAt(i);
			if ((ch >= '0' && ch <= '9') || ch == '.') digits.add(ch);
			else if (digits.length > 0) break;
		}

		for (part in digits.toString().split('.'))
		{
			var num:Null<Int> = Std.parseInt(part);
			result.push(num == null ? 0 : num);
		}
		return result;
	}

	/** 包声明的 minEngineVersion 是否被当前引擎满足；没声明视为满足。 */
	public static function isEngineCompatible(info:ContentPackInfo):Bool
	{
		if (info == null || info.minEngineVersion == null) return true;
		return compareVersions(engineVersion(), info.minEngineVersion) >= 0;
	}

	/**
	 * 配置 + 磁盘合并后的列表（与 Mods.parseList() 同构，方便 Mods 菜单共用一套逻辑）。
	 * 发现新包时自动写回磁盘。
	 */
	public static function parseList():ModsList
	{
		var list:ModsList = {enabled: [], disabled: [], all: []};
		#if sys
		var discovered:Array<ContentPackInfo> = listPacks();
		var states:Map<String, Bool> = new Map<String, Bool>();
		var ordered:Array<String> = [];

		if (FileSystem.exists(LIST_FILE))
		{
			try
			{
				// 不用 CoolUtil.coolTextFile：它在非 MODS_ALLOWED 构建下走 Assets，读不到运行时写的文本
				var raw:String = File.getContent(LIST_FILE);
				for (line in raw.split('\n'))
				{
					if (line == null) continue;
					var trimmed:String = line.split('\r').join('').trim();
					if (trimmed.length < 1) continue;
					var dat:Array<String> = trimmed.split('|');
					var path:String = dat[0].trim();
					if (path.length < 1 || states.exists(path)) continue;
					states.set(path, dat.length > 1 && dat[1] == '1');
					ordered.push(path);
				}
			}
			catch (e:Dynamic) trace(e);
		}

		var dirty:Bool = false;

		// 1. 按配置顺序收拢还存在的条目
		for (path in ordered)
		{
			var exists:Bool = false;
			for (info in discovered)
			{
				if (info.path == path)
				{
					exists = true;
					break;
				}
			}
			if (!exists)
			{
				dirty = true; // 目录被删了
				continue;
			}

			list.all.push(path);
			if (states.get(path)) list.enabled.push(path);
			else list.disabled.push(path);
		}

		// 2. 新包默认启用
		for (info in discovered)
		{
			if (list.all.indexOf(info.path) != -1) continue;
			dirty = true;
			list.all.push(info.path);
			list.enabled.push(info.path);
		}

		if (dirty) save(list);
		#end
		return list;
	}

	/** 是否被禁用（缓存，未配置的包一律视为启用）。 */
	public static function isDisabled(path:String):Bool
	{
		if (path == null || path.length < 1) return false;
		if (cachedDisabled == null)
		{
			cachedDisabled = new Map<String, Bool>();
			for (disabled in parseList().disabled)
				cachedDisabled.set(disabled, true);
		}
		return cachedDisabled.exists(path);
	}

	/** 改单个条目的开关并落盘（不需要重启）。 */
	public static function setDisabled(path:String, on:Bool):Void
	{
		var list:ModsList = parseList();
		if (on)
		{
			list.enabled.remove(path);
			if (!list.disabled.contains(path)) list.disabled.push(path);
		}
		else
		{
			list.disabled.remove(path);
			if (!list.enabled.contains(path)) list.enabled.push(path);
		}
		save(list);
		invalidate();
	}

	/** 整表落盘。 */
	public static function save(list:ModsList):Void
	{
		#if sys
		var fileStr:String = '';
		for (path in list.all)
		{
			if (path == null || path.trim().length < 1) continue;
			if (fileStr.length > 0) fileStr += '\n';
			fileStr += '$path|' + (list.disabled.contains(path) ? '0' : '1');
		}
		try
		{
			File.saveContent(LIST_FILE, fileStr);
		}
		catch (e:Dynamic) trace('Failed to save $LIST_FILE: $e'); // 只读目录 / 权限问题别把游戏带崩
		#end
	}

	/**
	 * 一个 content 子目录算不算"包"：里面得有引擎认的东西（shared/ 或谱面/json），
	 * 免得把 readme 那种杂物目录也列进菜单。
	 */
	static function isPackDirectory(path:String):Bool
	{
		#if sys
		if (FileSystem.exists('$path/shared')) return true;
		for (item in FileSystem.readDirectory(path))
		{
			if (item.startsWith('.')) continue;
			if (FileSystem.isDirectory('$path/$item')) return true;
			var lower:String = item.toLowerCase();
			if (lower.endsWith('.json') || lower.endsWith('.txt') || lower.endsWith('.md')) continue;
			return true;
		}
		#end
		return false;
	}

	/** 粗略统计包内曲目数，只用于菜单描述（失败不报错）。 */
	static function countSongs(path:String):Int
	{
		#if sys
		var dataPath:String = '$path/shared/data';
		if (!FileSystem.exists(dataPath) || !FileSystem.isDirectory(dataPath)) dataPath = path;

		var count:Int = 0;
		try
		{
			for (item in FileSystem.readDirectory(dataPath))
			{
				if (item.startsWith('.')) continue;
				var sub:String = '$dataPath/$item';
				if (!FileSystem.isDirectory(sub)) continue;
				if (hasChartFile(sub)) count++;
			}
		}
		catch (e:Dynamic) {}
		return count;
		#else
		return 0;
		#end
	}

	static function hasChartFile(directory:String):Bool
	{
		#if sys
		try
		{
			for (item in FileSystem.readDirectory(directory))
			{
				var lower:String = item.toLowerCase();
				if (lower.endsWith('.json') || lower.endsWith('.osu')) return true;
			}
		}
		catch (e:Dynamic) {}
		#end
		return false;
	}
}
