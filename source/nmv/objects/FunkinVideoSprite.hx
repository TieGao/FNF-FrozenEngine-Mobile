package nmv.objects;

#if VIDEOS_ALLOWED
import hxvlc.flixel.FlxVideoSprite;
import hxvlc.openfl.Location;

/**
 * NMV funkin.video.FunkinVideoSprite 薄适配：hxvlc FlxVideoSprite 直包（FE pin hxvlc 2.3.1）。
 *
 * 语料用到的面：new(x, y, oneTimeUse)、onFormat、onEnd、load(Paths.video(...))、
 * delayAndStart()（legacy 的 videoCutscene / meltdown 都走这套）。
 * 2026-11-23 P2 补齐（78 号 §九）：time/length/playing/percent 属性 + captions 字段形状 +
 * forEach/forEachAlive 静态面（Legacy FunkinVideoSprite.hx:149-152/77/243/252；
 * dialogue.hx:573 `video.time` 在 inDevMode 分支会踩到）。字幕打字机/时间轴未搬，
 * captions 只是字段形状（不被 add、不驱动 update）。
 * tiedToGame 字段保留 API 形状；FE 的暂停联动未接（NMV 原版在 FunkinGame 挂
 * focus/pause 信号，语料视频不依赖该行为，后续需要再补）。
 */
@:access(hxvlc.openfl.Video)
class FunkinVideoSprite extends FlxVideoSprite
{
	/** 全部存活实例（NMV 同名面；forEach 系列消费）。 */
	public static final instances:Array<FunkinVideoSprite> = [];

	/** load 选项：循环播放。 */
	public static final looping:String = ':input-repeat=65535';

	/** load 选项：静音。 */
	public static final muted:String = ':no-audio';

	/** 手动初始化 LibVLC 实例（NMV 同名面）。 */
	public static function init():Void
	{
		hxvlc.util.Handle.init();
	}

	/** NMV 字幕容器（Legacy FunkinVideoSprite.hx:77）；打字机未移植，仅字段形状。 */
	public var captions:Null<FunkinCaptionGroup>;

	/** false = 不随游戏暂停（联动未接，仅保留 NMV 字段形状）。 */
	public var tiedToGame:Bool = true;

	/** 播放位置（秒；Legacy _time 语义：播放中逐帧累加 + 实际值校准）。 */
	public var time(get, set):Float;

	/** 视频总长（秒；未就绪 -1）。 */
	public var length(get, never):Float;

	/** 是否播放中。 */
	public var playing(get, never):Bool;

	/** 播放进度 0..1（hxvlc position 直通）。 */
	public var percent(get, never):Float;

	var _time:Float = -1;
	var _lastTime:Float = -1;

	/**
	 * @param x x 位置
	 * @param y y 位置
	 * @param oneTimeUse true = 视频放完自动 destroy
	 */
	public function new(x:Float = 0, y:Float = 0, oneTimeUse:Bool = true)
	{
		super(x, y);

		instances.push(this);
		captions = new FunkinCaptionGroup();

		if (oneTimeUse) bitmap.onEndReached.add(this.destroy, true, -10);
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (playing) _time += elapsed;

		// Legacy update：实际播放时间以 1/60 秒粒度校准回 _time（避免 seek 前的累计漂移）
		if (ready())
		{
			final secs:Float = int64ToFloat(bitmap.time) / 1000;
			if (Math.abs(secs - _lastTime) > 1 / 60) _time = secs;
			_lastTime = secs;
		}
		// Legacy 还会在 ClientPrefs.subtitles 时 captions.time = time; captions.update(elapsed)；
		// 打字机未移植，跳过（captions 不 add 不 update，无副作用）。
	}

	inline function ready():Bool
		return bitmap != null && bitmap.mediaPlayer != null;

	inline function get_time():Float
		return _time;

	inline function set_time(secs:Float):Float
	{
		if (!ready()) return secs;
		bitmap.time = haxe.Int64.fromFloat(secs * 1000);
		return secs;
	}

	inline function get_length():Float
		return ready() && bitmap.length > -1 ? int64ToFloat(bitmap.length) / 1000 : -1;

	inline function get_playing():Bool
		return ready() && bitmap.isPlaying;

	inline function get_percent():Float
		return ready() ? bitmap.position : 0;

	/** Legacy 同款手写 Int64→Float（"thanks stack overflow"；本 Haxe 的 Int64 无 toFloat）。 */
	inline function int64ToFloat(i:haxe.Int64):Float
		return (i.high * 4294967296. + (i.low >>> 0));

	/** NMV 同名静态面（Legacy FunkinVideoSprite.hx:243）。 */
	public static function forEach(func:FunkinVideoSprite->Void):Void
	{
		for (video in instances)
			if (video != null) func(video);
	}

	/** NMV 同名静态面（Legacy FunkinVideoSprite.hx:252）。 */
	public static function forEachAlive(func:FunkinVideoSprite->Void):Void
	{
		for (video in instances)
			if (video != null && video.exists && video.alive) func(video);
	}

	/** 延迟起播（NMV 推荐 over play()；默认下一帧）。 */
	public function delayAndStart(delay:Float = 0):Void
	{
		flixel.util.FlxTimer.wait(delay, play);
	}

	/** 视频播到结尾回调。 */
	public function onEnd(func:Void->Void, once:Bool = false, priority:Int = 0):Void
	{
		bitmap.onEndReached.add(func, once, priority);
	}

	/** 视频开始回调。 */
	public function onStart(func:Void->Void, once:Bool = false, priority:Int = 0):Void
	{
		bitmap.onOpening.add(func, once, priority);
	}

	/** 视频格式就绪回调（推荐在此绑相机/缩放）。 */
	public function onFormat(func:Void->Void, once:Bool = false, priority:Int = 0):Void
	{
		bitmap.onFormatSetup.add(func, once, priority);
	}

	override function destroy():Void
	{
		if (instances.contains(this)) instances.remove(this);

		if (bitmap != null)
		{
			bitmap.stop();

			bitmap.onEndReached.removeAll();
			bitmap.onFormatSetup.removeAll();
			bitmap.onOpening.removeAll();
		}

		super.destroy();
	}
}
#end
