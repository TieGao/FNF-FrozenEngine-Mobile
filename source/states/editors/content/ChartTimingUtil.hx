package states.editors.content;

typedef BpmSegment =
{
	var time:Float;
	var bpm:Float;
	@:optional var meter:Int;
}

typedef ChartSectionSpan =
{
	var start:Float;
	var end:Float;
	var beats:Float;
	var bpm:Float;
}

/**
 * 谱面时间轴 → 小节区间（FE 的 section 模型）。
 *
 * FE 的每条 section 只带一个 BPM，时长按 sectionBeats 拍算，所以时间轴的唯一真相必须是
 * 源谱的 BPM 段；不能先按小节线递推、再回头猜变速点落在哪个小节。
 *
 * 反推的典型崩法（osu 最常见）：源文件时间戳只精确到整毫秒，一个本该压在小节线上的
 * 变速点会落在递推边界之后 0.3ms，被当成"小节内变速"，于是这一小节按新 BPM 算长度、
 * 多出或少掉整整一拍到一小节，后面每个 section 的时间轴全部错位。编辑器
 * ChartingState._cacheSections() 又会把超出本节时长的 note 夹到 section 末端，
 * 表现就是"每个 section 末尾一堆 note 挤在几毫秒内"（note 总数不变）。
 *
 * 这里按段推进：段内凑满拍号拍数才收小节；变速点贴着小节末（EPS_BEATS 内）视为
 * 同一条线，边界直接对齐变速点。
 */
class ChartTimingUtil
{
	/** 变速点与"小节末/段末"的距离在这个拍数内视为同一条线（吸收源时间戳的整毫秒取整） */
	public static inline var EPS_BEATS:Float = 0.02;

	public static function buildSections(bpmChanges:Array<BpmSegment>, endTime:Float, ?defaultMeter:Int = 4):Array<ChartSectionSpan>
	{
		var sections:Array<ChartSectionSpan> = [];
		var segments:Array<BpmSegment> = normalize(bpmChanges, defaultMeter);
		if (segments.length <= 0) return sections;

		var pos:Float = 0;
		var beatInMeasure:Float = 0;
		var segIndex:Int = 0;
		var guard:Int = 0;

		while (pos < endTime && guard++ < 100000)
		{
			while (segIndex + 1 < segments.length && segments[segIndex + 1].time <= pos + 0.001)
				segIndex++;

			var seg:BpmSegment = segments[segIndex];
			var nextTime:Float = (segIndex + 1 < segments.length) ? segments[segIndex + 1].time : Math.POSITIVE_INFINITY;
			var meter:Int = (seg.meter != null && seg.meter > 0) ? seg.meter : defaultMeter;
			var crochet:Float = 60000 / seg.bpm;
			if (crochet <= 0 || Math.isNaN(crochet)) break;

			var beatsLeft:Float = meter - beatInMeasure;
			if (beatsLeft <= EPS_BEATS)
			{
				// 拍号变小 / 上个小节已满：直接开新小节，别切出负拍或 0 拍 section
				beatInMeasure = 0;
				beatsLeft = meter;
			}
			var measureEnd:Float = pos + beatsLeft * crochet;
			var beats:Float;
			var sectionEnd:Float;

			if (nextTime == Math.POSITIVE_INFINITY || measureEnd < nextTime - EPS_BEATS * crochet)
			{
				// 段内还有余量，正常收一小节
				beats = beatsLeft;
				sectionEnd = measureEnd;
			}
			else if (measureEnd <= nextTime + EPS_BEATS * crochet)
			{
				// 变速点正好压在（或紧贴）小节线上：边界对齐变速点，别让 ±1ms 的取整误差累积
				beats = beatsLeft;
				sectionEnd = nextTime;
			}
			else
			{
				// 变速点在小节中间：切一个不足小节的部分
				beats = (nextTime - pos) / crochet;
				sectionEnd = nextTime;
				if (beats < 0.001)
				{
					pos = nextTime;
					beatInMeasure += beats;
					continue;
				}
			}

			// 4.0004 这种零头来自源时间戳取整：吸附回 0.25 拍，避免 Conductor 的 round(beats*4) 抖动
			var snapped:Float = Math.round(beats * 4) / 4;
			if (snapped > 0 && Math.abs(beats - snapped) < 0.01) beats = snapped;

			// 至少 1/16 拍：编辑器按 round(beats*4) 推进时间轴，不足 0.125 拍会被算成 0 步，
			// 本节 note 全被夹到同一时刻，直接堆成一坨
			if (beats * 4 < 1) beats = 0.25;

			sections.push({start: pos, end: sectionEnd, beats: beats, bpm: seg.bpm});
			pos = sectionEnd;
			beatInMeasure += beats;
			if (beatInMeasure >= meter - EPS_BEATS) beatInMeasure = 0;
		}

		return sections;
	}

	/** 排序、丢掉非法项、合并同时间点（后者生效）、把负时间点归到 0 */
	static function normalize(bpmChanges:Array<BpmSegment>, defaultMeter:Int):Array<BpmSegment>
	{
		var list:Array<BpmSegment> = [];
		if (bpmChanges != null)
		{
			for (change in bpmChanges)
			{
				if (change == null || change.bpm <= 0 || Math.isNaN(change.bpm)) continue;
				list.push({time: change.time, bpm: change.bpm, meter: change.meter});
			}
		}
		if (list.length <= 0) list.push({time: 0, bpm: 120, meter: defaultMeter});
		list.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));

		var normalized:Array<BpmSegment> = [];
		for (change in list)
		{
			var time:Float = (change.time < 0) ? 0 : change.time;
			if (normalized.length > 0 && Math.abs(time - normalized[normalized.length - 1].time) < 0.01)
				normalized[normalized.length - 1] = {time: time, bpm: change.bpm, meter: change.meter};
			else
				normalized.push({time: time, bpm: change.bpm, meter: change.meter});
		}

		// 首个变速点在 0 之后：0 到它之间沿用它的 BPM（源谱之前没有节奏信息）
		if (normalized[0].time > 0.01) normalized.unshift({time: 0, bpm: normalized[0].bpm, meter: normalized[0].meter});

		return normalized;
	}
}
