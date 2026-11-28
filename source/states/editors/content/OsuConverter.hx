package states.editors.content;

import backend.Song;
import haxe.Json;
import sys.io.File;
import sys.FileSystem;
import haxe.ds.StringMap;
import states.editors.content.ChartTimingUtil.ChartSectionSpan;

using StringTools;

typedef BpmChange =
{
	var time:Float;
	var bpm:Float;
	var ?meter:Int;
}

typedef OsuNote =
{
	var time:Float;
	var lane:Int;
	var length:Float;
}

/**
 * 读取 osu!mania (.osu) 谱面并转成 SwagSong。导出方向走 ChartConvertCore（moonchart）。
 */
class OsuConverter
{
	// ============ OSU → Psych ============

	/**
	 * 从 .osu 文件读取并转换为 SwagSong，返回解析后的歌曲数据。
	 * @param filePath .osu 文件路径
	 */
	public static function convertOsuToPsych(filePath:String, ?chartCategory:String, ?chartSongDir:String):SwagSong
	{
		if (!FileSystem.exists(filePath))
		{
			trace('【错误】文件不存在: $filePath');
			return null;
		}

		var content:String = File.getContent(filePath);
		var sections:Map<String, Array<String>> = parseOsuSections(content);

		var metadata:Map<String, String> = parseKeyValues(sections["Metadata"]);
		var difficulty:Map<String, String> = parseKeyValues(sections["Difficulty"]);
		var timingLines:Array<String> = sections["TimingPoints"] ?? [];
		var hitLines:Array<String> = sections["HitObjects"] ?? [];

		// ===== BPM 段（uninherited 才有意义，beatLength 是每拍毫秒） =====
		var bpmChanges:Array<BpmChange> = [];
		for (line in timingLines)
		{
			var parts = line.split(",");
			if (parts.length < 8) continue;
			var time:Float = Std.parseFloat(parts[0]);
			var beatLength:Float = Std.parseFloat(parts[1]);
			var meter:Int = Std.parseInt(parts[2]);
			var uninherited:Int = Std.parseInt(parts[6]);
			if (uninherited != 1 || beatLength <= 0) continue;
			bpmChanges.push({time: time, bpm: 60000.0 / beatLength, meter: meter});
		}
		bpmChanges.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));

		// 同一时间点的多条只留最后一条；相邻且 BPM/拍号相同的重复定义也合并，
		// 免得在段边界切出一个多余的小节。负时间点 / 0 点补段交给 ChartTimingUtil
		var dedup:Array<BpmChange> = [];
		for (change in bpmChanges)
		{
			if (dedup.length > 0)
			{
				var prev:BpmChange = dedup[dedup.length - 1];
				if (Math.abs(change.time - prev.time) < 0.01)
				{
					dedup[dedup.length - 1] = change;
					continue;
				}
				if (Math.abs(change.bpm - prev.bpm) < 0.001 && (change.meter ?? 4) == (prev.meter ?? 4))
					continue;
			}
			dedup.push(change);
		}
		bpmChanges = dedup;
		if (bpmChanges.length == 0) bpmChanges.push({time: 0, bpm: 120, meter: 4});

		// ===== 音符 =====
		var keys:Int = Std.parseInt(difficulty.get("CircleSize"));
		if (keys < 1) keys = 4;
		if (keys > 18) keys = 18;

		var notes:Array<OsuNote> = [];
		for (line in hitLines)
		{
			var parts = line.split(",");
			if (parts.length < 6) continue;
			var x:Float = Std.parseFloat(parts[0]);
			var time:Float = Std.parseFloat(parts[2]);
			var type:Int = Std.parseInt(parts[3]);
			var lane:Int = Math.floor((x / 512) * keys);
			if (lane < 0) lane = 0;
			if (lane >= keys) lane = keys - 1; // x 正好压在 512 上时别越到对手侧

			var length:Float = 0;
			// hold 的 type 是位标志（128 / 129 / 132…），不能用 == 128 判
			if ((type & 128) != 0)
			{
				var endTime:Float = Std.parseFloat(parts[5].split(":")[0]);
				if (endTime > time) length = endTime - time;
			}
			notes.push({time: time, lane: lane, length: length});
		}
		notes.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));

		var endTime:Float = 1600;
		if (notes.length > 0)
		{
			var lastNote:OsuNote = notes[notes.length - 1];
			// 只到最后一个 note 的起点：hold 尾巴不需要额外小节，末尾的空 BPM 段也不用铺满
			// （+1 是开区间判断：单点 note 的 time 正好等于 endTime 会掉出最后一节）
			endTime = lastNote.time + 1;
		}
		if (endTime <= 0) endTime = 1600;

		// ===== 时间轴 → section =====
		// 必须按 BPM 段切（见 ChartTimingUtil）：osu 的 timing 时间戳只到整毫秒，
		// 之前"从小节线反推变速点"会把贴着小节线的变速推到下一小节，整条时间轴偏一拍。
		var spans:Array<ChartSectionSpan> = ChartTimingUtil.buildSections([for (change in bpmChanges) {
			time: change.time,
			bpm: change.bpm,
			meter: change.meter
		}], endTime);

		var swagSections:Array<SwagSection> = [];
		var songBpm:Float = (spans.length > 0) ? spans[0].bpm : bpmChanges[0].bpm;
		var lastBpm:Float = songBpm;
		var noteIndex:Int = 0;

		for (span in spans)
		{
			var sectionNotes:Array<Dynamic> = [];
			while (noteIndex < notes.length && notes[noteIndex].time < span.end)
			{
				var note:OsuNote = notes[noteIndex++];
				sectionNotes.push([note.time, note.lane, note.length]);
			}

			var change:Bool = span.bpm != lastBpm;
			var sec:SwagSection = {
				sectionNotes: sectionNotes,
				sectionBeats: span.beats,
				mustHitSection: true,
				changeBPM: change,
				altAnim: false,
				gfSection: false
			};
			if (change) sec.bpm = span.bpm;
			swagSections.push(sec);
			lastBpm = span.bpm;
		}

		if (swagSections.length <= 0)
		{
			swagSections.push({
				sectionNotes: [for (note in notes) [note.time, note.lane, note.length]],
				sectionBeats: 4,
				mustHitSection: true,
				changeBPM: false,
				altAnim: false,
				gfSection: false
			});
		}

		// ===== 元数据 =====
		var sourceInfo:Array<String> = getChartSourceInfo(filePath);
		if (chartCategory == null) chartCategory = sourceInfo[0];
		if (chartSongDir == null) chartSongDir = sourceInfo[1];
		var songName:String = (chartSongDir != null && chartSongDir.length > 0)
			? chartSongDir
			: (metadata.get("Title") ?? "Untitled");

		var song:SwagSong = {
			song: songName,
			notes: swagSections,
			events: [],
			bpm: songBpm,
			needsVoices: true,
			speed: 1.0,
			offset: 0,
			player1: "bf",
			player2: "dad",
			gfVersion: "gf",
			stage: "stage",
			format: "psych_v1",
			mania: keys - 1,
			keyCount: keys,
			keycount: keys
		};

		Reflect.setField(song, 'mania', keys - 1);
		Reflect.setField(song, 'keyCount', keys);
		Reflect.setField(song, 'keycount', keys);

		return song;
	}

	private static function getChartSourceInfo(filePath:String):Array<String>
	{
		var normalized:String = filePath.replace('\\', '/');
		var marker:String = '/customcharts/';
		var markerIndex:Int = normalized.toLowerCase().indexOf(marker);
		if (markerIndex == -1) return [null, null];

		var parts:Array<String> = normalized.substr(markerIndex + marker.length).split('/');
		if (parts.length < 3) return [null, null];
		return [parts[0], parts[1]];
	}

	public static function parseOsuSections(content:String):Map<String, Array<String>>
	{
		var sections:Map<String, Array<String>> = new Map();
		var lines = content.split("\n");
		var currentSection:String = null;
		var currentLines:Array<String> = [];
		for (line in lines)
		{
			line = line.trim();
			if (line.startsWith("[") && line.endsWith("]"))
			{
				if (currentSection != null)
					sections.set(currentSection, currentLines);
				currentSection = line.substr(1, line.length - 2);
				currentLines = [];
			}
			else if (line.length > 0)
			{
				currentLines.push(line);
			}
		}
		if (currentSection != null)
			sections.set(currentSection, currentLines);
		return sections;
	}

	public static function parseKeyValues(lines:Array<String>):Map<String, String>
	{
		var map:Map<String, String> = new Map();
		if (lines == null) return map;
		for (line in lines)
		{
			var idx = line.indexOf(":");
			if (idx == -1) continue;
			var key = line.substr(0, idx).trim();
			var value = line.substr(idx + 1).trim();
			map.set(key, value);
		}
		return map;
	}
}
