package objects;

import flixel.FlxG;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import backend.Song.SwagSong;
import states.PlayState;

/**
 * Chart Helper：NPS / BPM / Section / Step 四行谱面信息。
 * 每行一个开关（ClientPrefs），整组永远以屏幕中心为基准居中，偏移在 NoteOffsetState 里拖拽调整。
 */
class ChartHelper
{
	public static inline var LINE_HEIGHT:Float = 24;
	public static inline var TEXT_SIZE:Int = 20;

	// NPS 窗口（毫秒）：Conductor.songPosition 就是毫秒，别写成 1.0
	static inline var NPS_WINDOW:Float = 1000;

	public var rows:Array<{key:String, text:FlxText}> = [];

	var state:PlayState;
	var preview:Bool = false;
	var font:String = 'vcr.ttf';

	var bpmMin:Float = 0;
	var bpmMax:Float = 0;

	// 命中时间戳（毫秒）。NPS = 最近 1 秒内的条数，同 Kade / NovaFlare 的 notesHitArray 做法
	var hitTimes:Array<Float> = [];
	var maxNps:Int = 0;

	var lastLayoutSig:String = '';

	// 每帧刷新：把译文模板缓存下来，避免每帧 formatKey + Map 查找
	var phraseNps:String = '';
	var phraseBpm:String = '';
	var phraseSection:String = '';
	var phraseStep:String = '';

	/**
	 * @param state   游戏内用 PlayState；传 null 进预览模式（NoteOffsetState）
	 * @param preview 预览模式不读运行时数据，用固定样例值
	 */
	public function new(?state:PlayState, ?preview:Bool = false)
	{
		this.state = state;
		this.preview = preview;
		if (state == null && !preview) return;

		font = GameFont.resolve('vcr.ttf');
		bpmMin = bpmMax = 0;
		if (state != null && PlayState.SONG != null) computeBpmRange(PlayState.SONG);

		phraseNps = Language.getPhrase('chart_helper_nps', 'NPS: {1} ({2})');
		phraseBpm = Language.getPhrase('chart_helper_bpm', 'BPM: {1}');
		phraseSection = Language.getPhrase('chart_helper_section', 'Section: {1}');
		phraseStep = Language.getPhrase('chart_helper_step', 'Step: {1}');

		build();
		refresh();
	}

	/** 四行的静态定义（顺序即显示顺序）。 */
	public static function specs():Array<{key:String, label:String}>
	{
		return [
			{key: 'nps', label: 'NPS'},
			{key: 'bpm', label: 'BPM'},
			{key: 'section', label: 'Section'},
			{key: 'step', label: 'Step'},
		];
	}

	public static function isRowEnabled(key:String):Bool
	{
		switch (key)
		{
			case 'nps': return ClientPrefs.data.showNPS;
			case 'bpm': return ClientPrefs.data.showBPM;
			case 'section': return ClientPrefs.data.showSection;
			case 'step': return ClientPrefs.data.showStep;
		}
		return false;
	}

	public static function hasAnyEnabled():Bool
	{
		for (spec in specs())
			if (isRowEnabled(spec.key)) return true;
		return false;
	}

	function build():Void
	{
		for (spec in specs())
		{
			var text:FlxText = new FlxText(0, 0, 0, '', TEXT_SIZE);
			text.setFormat(font, TEXT_SIZE, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
			text.borderSize = 2;
			text.antialiasing = ClientPrefs.data.antialiasing;
			text.scrollFactor.set(0, 0);
			text.visible = false;

			rows.push({key: spec.key, text: text});
			if (state != null) state.uiGroup.add(text);
		}
	}

	public function refresh():Void
	{
		if (rows.length < 1) return;

		var shown:Bool = preview || !ClientPrefs.data.hideHud;
		// 预览里四项全关时仍然铺出来，否则界面上没有可拖的东西
		var fallbackAll:Bool = preview && !hasAnyEnabled();
		var dirty:Bool = false;

		for (row in rows)
		{
			var on:Bool = fallbackAll || isRowEnabled(row.key);
			var vis:Bool = shown && on;
			if (row.text.visible != vis)
			{
				row.text.visible = vis;
				dirty = true;
			}
			if (!vis) continue;

			var value:String = formatValue(row.key);
			if (row.text.text != value)
			{
				row.text.text = value;
				dirty = true;
			}
		}

		// 可见行集合或偏移变了也要重新摆位（居中位置取决于行数和文字宽度）
		var sig:String = ClientPrefs.data.chartHelperOffsetX + '|' + ClientPrefs.data.chartHelperOffsetY + '|';
		for (row in rows)
			if (row.text.visible) sig += row.key + ',';

		if (dirty || sig != lastLayoutSig)
		{
			lastLayoutSig = sig;
			layout(rows);
		}
	}

	/** 整组按可见行居中；preview 时用固定样例值。 */
	function formatValue(key:String):String
	{
		switch (key)
		{
			case 'nps':
				if (preview) return phraseNps.replace('{1}', '8').replace('{2}', '21');
				return phraseNps.replace('{1}', Std.string(countNps())).replace('{2}', Std.string(maxNps));

			case 'bpm':
				var cur:Float = preview ? 128 : Conductor.bpm;
				return phraseBpm.replace('{1}', formatBpmText(cur, bpmMin, bpmMax));

			case 'section':
				return phraseSection.replace('{1}', Std.string(preview ? 12 : state.getSectionIndex()));

			case 'step':
				return phraseStep.replace('{1}', Std.string(preview ? 48 : state.getStepIndex()));
		}
		return '';
	}

	/** PlayState 每次玩家命中（`songHits++` 那一处）调一次。 */
	public function registerHit():Void
	{
		if (state == null) return;

		var now:Float = Conductor.songPosition;
		// 重开 / 回退：时间戳比上一条还早 → 整表作废，别让旧记录算进窗口
		if (hitTimes.length > 0 && now < hitTimes[hitTimes.length - 1]) hitTimes = [];
		hitTimes.push(now);

		countNps();
	}

	/** 丢掉 1 秒前的记录，返回当前 NPS，并顺手更新 Max。 */
	function countNps():Int
	{
		var cutoff:Float = Conductor.songPosition - NPS_WINDOW;
		var drop:Int = 0;
		while (drop < hitTimes.length && hitTimes[drop] <= cutoff) drop++;
		if (drop > 0) hitTimes.splice(0, drop);

		if (hitTimes.length > maxNps) maxNps = hitTimes.length;
		return hitTimes.length;
	}

	/** 谱面 BPM 范围：主 BPM + 所有带变速的分节。 */
	function computeBpmRange(song:SwagSong):Void
	{
		var base:Float = song.bpm;
		if (base <= 0) base = 0;
		bpmMin = base;
		bpmMax = base;

		for (section in song.notes)
		{
			if (section == null || section.changeBPM != true || section.bpm == null || section.bpm <= 0) continue;
			if (bpmMin <= 0 || section.bpm < bpmMin) bpmMin = section.bpm;
			if (section.bpm > bpmMax) bpmMax = section.bpm;
		}

		if (bpmMax <= 0) bpmMax = base;
		if (bpmMin <= 0) bpmMin = bpmMax;
	}

	/** `128` / `128 (100~180)`，与 Freeplay 的 BPM 行同口径。 */
	public static function formatBpmText(cur:Float, min:Float, max:Float):String
	{
		var high:Float = (max > 0) ? max : cur;
		var low:Float = (min > 0) ? min : high;
		// 少数谱面主 BPM 写 0、只在分节里给变速
		var value:Float = (cur > 0) ? cur : high;
		if (value <= 0) return '--';

		var out:String = formatBpmValue(value);
		if (Math.abs(high - low) >= 0.05) out += ' (' + formatBpmValue(low) + '~' + formatBpmValue(high) + ')';
		return out;
	}

	static function formatBpmValue(bpm:Float):String
	{
		return (Math.round(bpm) == bpm) ? Std.string(Math.round(bpm)) : Std.string(FlxMath.roundDecimal(bpm, 1));
	}

	/**
	 * 按可见行居中摆放：整块水平居中，纵向以屏幕中心为基准，再加 chartHelperOffsetX/Y。
	 * 行数一变整块会重新居中（这是"永远居中"的关键）。
	 */
	public static function layout(rows:Array<{key:String, text:FlxText}>, useOffset:Bool = true):Void
	{
		var visible:Array<FlxText> = [];
		for (row in rows)
			if (row.text.visible) visible.push(row.text);
		if (visible.length < 1) return;

		for (text in visible)
		{
			text.fieldWidth = 0; // autoSize：框宽跟随文字
			text.updateHitbox();
		}

		var offX:Float = useOffset ? ClientPrefs.data.chartHelperOffsetX : 0;
		var offY:Float = useOffset ? ClientPrefs.data.chartHelperOffsetY : 0;

		var startY:Float = FlxG.height / 2 - visible.length * LINE_HEIGHT / 2 + offY;
		for (i in 0...visible.length)
		{
			var text:FlxText = visible[i];
			text.x = (FlxG.width - text.width) / 2 + offX;
			text.y = startY + i * LINE_HEIGHT;
		}
	}

	public function destroy():Void
	{
		rows = [];
		hitTimes = [];
		state = null;
	}
}
