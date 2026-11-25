package mobile.backend;

import debug.LogFile;
import flixel.FlxG;
import lime.system.JNI;
import openfl.Lib;

/**
 * Android ADPF（Dynamic Performance Framework）接入：把「这一帧实际花了多少 CPU 时间」
 * 每帧告诉系统，让 CPU governor 提前升降频，而不是等掉帧了才反应。
 *
 * 链路：preUpdate 记 t0 → postDraw 记 t1 → JNI → Adpf.java 的 Session.reportActualWorkDuration。
 * 只算 update + draw 的 CPU 时间，不含 present/vsync 等待——把等待算进去会永远「达标」，
 * 系统反而给你降频。
 *
 * target（帧预算）= 当前帧率上限：ClientPrefs.applyFrameTiming 里同步；
 * 无限帧率（fps<=0）用设备首选刷新间隔 PerformanceHintManager.getPreferredUpdateRateNanos()。
 *
 * 平台：只在 android 生效，其余平台所有函数是空实现（调用点可以不加 #if）。
 * 关闭：构建时 -D ADPF_OFF（Main 里的 init 调用被编译掉）。
 * 依赖：android/java/org/frozenengine/adpf/Adpf.java，由 Project.xml 的 <java> 拷进 gradle 工程。
 */
class AndroidADPF
{
	/** 本机支持且会话已建立 */
	public static var supported(default, null):Bool = false;
	/** 正在每帧上报（= supported；保留给以后做临时挂起） */
	public static var active(default, null):Bool = false;

	static var inited:Bool = false;
	static var targetMicros:Int = 16667;
	static var t0:Float = -1;
	static var lastLogMs:Int = 0;

	/** 启动信息：LogFile 要等 TitleState.create 才 start()，所以延到开机 5 秒后再落盘 */
	static var bootInfo:String = null;

	// 30 秒窗口统计，给真机调参用（写进 crash/latest.log，仅当玩家开了会话日志）
	static var winCount:Int = 0;
	static var winSum:Float = 0;
	static var winMax:Float = 0;

	static var jniStart:Dynamic;
	static var jniFrame:Dynamic;
	static var jniSetTarget:Dynamic;
	static var jniStop:Dynamic;
	static var jniThermal:Dynamic;
	static var jniGameMode:Dynamic;
	static var jniPreferred:Dynamic;
	static var jniDescribe:Dynamic;

	/** 在 Main.setupGame 里调一次（stage 已就绪、且与渲染同线程）。 */
	public static function init():Void
	{
		#if android
		if (inited) return;
		inited = true;

		jniStart = create('start', '(I)Z');
		jniFrame = create('frame', '(I)V');
		jniSetTarget = create('setTarget', '(I)V');
		jniStop = create('stop', '()V');
		jniThermal = create('thermalStatus', '()I');
		jniGameMode = create('gameMode', '()I');
		jniPreferred = create('preferredUpdateNanos', '()I');
		jniDescribe = create('describe', '()Ljava/lang/String;');

		if (jniStart == null)
		{
			bootInfo = '[ADPF] Java helper 未打进 APK（检查 Project.xml 的 <java>）';
			trace(bootInfo);
			return;
		}

		// 此时 prefs 还没加载（TitleState 才 loadPrefs），先用 flixel 的默认帧率，
		// 等 applyFrameTiming() 跑起来会立刻校准。
		final fps:Int = FlxG.drawFramerate;
		targetMicros = (fps > 0 && fps <= 480) ? Std.int(1000000 / fps) : preferredMicros();

		supported = toBool(jniStart(targetMicros));
		active = supported;

		bootInfo = '[ADPF] ' + (supported ? 'on' : 'off') + ' ' + describe() + ' target=' + fmtMs(targetMicros) + 'ms';
		trace(bootInfo);

		// 建不起来也挂 postDraw：bootInfo 要等日志文件就绪后由 onFrameEnd 冲一次
		FlxG.signals.postDraw.add(onFrameEnd);
		if (supported) FlxG.signals.preUpdate.add(onFrameStart);
		#end
	}

	/** 帧率上限变了就改预算；fps <= 0 = 无限帧率，用设备首选刷新率。 */
	public static function setTargetFps(fps:Int):Void
	{
		#if android
		if (!supported) return;

		final us:Int = (fps > 0 && fps <= 480) ? Std.int(1000000 / fps) : preferredMicros();
		if (us == targetMicros) return;

		targetMicros = us;
		if (jniSetTarget != null) jniSetTarget(us);
		#end
	}

	/** 退出 / 彻底停用时调用（目前没人调，进程结束会一起回收）。 */
	public static function shutdown():Void
	{
		#if android
		if (!inited) return;
		FlxG.signals.preUpdate.remove(onFrameStart);
		FlxG.signals.postDraw.remove(onFrameEnd);
		if (jniStop != null) jniStop();
		supported = false;
		active = false;
		inited = false;
		#end
	}

	#if android
	static inline function create(method:String, signature:String):Dynamic
		return JNI.createStaticMethod('org/frozenengine/adpf/Adpf', method, signature, false, true);

	static inline function toBool(v:Dynamic):Bool
		return v == true;

	static function preferredMicros():Int
	{
		if (jniPreferred == null) return 8333;

		final v:Dynamic = jniPreferred();
		final ns:Int = (v == null) ? 0 : Std.int(v);
		return ns > 0 ? Std.int(ns / 1000) : 8333;
	}

	static function describe():String
	{
		if (jniDescribe == null) return '';

		final v:Dynamic = jniDescribe();
		return v == null ? '' : Std.string(v);
	}

	static function onFrameStart():Void
	{
		if (!active) return;
		t0 = haxe.Timer.stamp();
	}

	static function onFrameEnd():Void
	{
		final now:Int = Lib.getTimer();

		if (bootInfo != null && now - lastLogMs >= 5000 && LogFile.isOpen())
		{
			LogFile.append(bootInfo);
			bootInfo = null;
			lastLogMs = now;
		}

		if (!active || t0 < 0) return;

		final us:Int = Std.int((haxe.Timer.stamp() - t0) * 1000000.0);
		t0 = -1;
		if (us <= 0) return;

		jniFrame(us);

		winCount++;
		winSum += us;
		if (us > winMax) winMax = us;

		if (now - lastLogMs >= 30000) flushLog(now);
	}

	static function flushLog(now:Int):Void
	{
		lastLogMs = now;
		if (winCount == 0) return;

		if (!LogFile.isOpen())
		{
			// 玩家关了会话日志：不建字符串、不调 JNI，直接丢窗口
			winCount = 0;
			winSum = 0;
			winMax = 0;
			return;
		}

		final avg:Float = winSum / winCount;
		final thermal:Dynamic = jniThermal == null ? 0 : jniThermal();
		final mode:Dynamic = jniGameMode == null ? 0 : jniGameMode();

		LogFile.append('[ADPF] target=' + fmtMs(targetMicros) + 'ms avg=' + fmtMs(avg) + 'ms max=' + fmtMs(winMax) + 'ms'
			+ ' thermal=' + Std.string(thermal == null ? 0 : thermal) + ' mode=' + Std.string(mode == null ? 0 : mode) + ' n=' + winCount);

		winCount = 0;
		winSum = 0;
		winMax = 0;
	}

	static inline function fmtMs(micros:Float):String
		return Std.string(Math.round(micros / 100.0) / 10.0);
	#end
}
