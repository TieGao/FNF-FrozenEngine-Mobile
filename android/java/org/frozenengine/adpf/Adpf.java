package org.frozenengine.adpf;

import android.content.Context;
import android.os.Build;
import android.os.PowerManager;
import android.os.Process;
import android.util.Log;

import org.haxe.extension.Extension;

/**
 * Android ADPF（Dynamic Performance Framework）最小封装。
 *
 * 只做三件事：
 *   1. 在游戏主线程建 PerformanceHintManager.Session —— tid 用 Process.myTid()，
 *      取的是「调用线程」的 tid，所以 start() 必须由渲染线程调用，不能从 UI 线程调；
 *   2. 每帧上报实际 CPU 耗时（外部传微秒、这里换成纳秒，避免 Haxe Int 传 jlong）；
 *   3. 帧率变化时改 target。
 *
 * 为什么必须写 Java：createHintSession(int[] tids, long) 要 int 数组，lime 的 JNI
 * 参数转换只支持标量和 jobject，构造不出 int[]。
 *
 * 兼容性：API < 31 时不加载 Api31 内部类（字段/参数全用 Object 存），
 * 避免老机器在类加载阶段就 NoClassDefFoundError。
 */
public final class Adpf
{
	private static final String TAG = "FrozenADPF";

	private static final String SERVICE_PERFORMANCE_HINT = "performance_hint";
	private static final String SERVICE_GAME = "game";
	private static final String SERVICE_POWER = "power";

	/** PerformanceHintManager.Session，API 31 才有；用 Object 存以兼容老系统 */
	private static Object session;
	private static long targetNanos;
	private static int preferredNanos;
	private static int tid = -1;
	private static String lastError = "";

	private Adpf() {}

	/** 建会话；返回 false = 本机不支持 / 没有权限 / 已在后台。可重复调用。 */
	public static boolean start(int targetMicros)
	{
		if (session != null) return true;
		if (Build.VERSION.SDK_INT < 31)
		{
			lastError = "sdk<31";
			return false;
		}

		if (targetMicros <= 0) targetMicros = 16667;

		try
		{
			return Api31.start(targetMicros * 1000L);
		}
		catch (Throwable t)
		{
			lastError = t.getClass().getSimpleName() + ": " + t.getMessage();
			Log.w(TAG, "start failed", t);
			return false;
		}
	}

	/** 每帧结束上报一次实际耗时（微秒）。 */
	public static void frame(int actualMicros)
	{
		if (session == null || actualMicros <= 0) return;

		long ns = actualMicros * 1000L;
		// 切歌 / 回前台的首帧会异常大，夹到 3 倍预算，别让系统以为一直在超时
		long cap = targetNanos > 0 ? targetNanos * 3 : 50_000_000L;
		if (ns > cap) ns = cap;

		try
		{
			Api31.report(session, ns);
		}
		catch (Throwable t)
		{
			lastError = t.getClass().getSimpleName() + ": " + t.getMessage();
		}
	}

	/** 帧率变了同步改预算（微秒）。 */
	public static void setTarget(int targetMicros)
	{
		if (session == null || targetMicros <= 0) return;

		long ns = targetMicros * 1000L;
		if (ns == targetNanos) return;

		try
		{
			Api31.setTarget(session, ns);
			targetNanos = ns;
		}
		catch (Throwable t)
		{
			lastError = t.getClass().getSimpleName() + ": " + t.getMessage();
		}
	}

	public static void stop()
	{
		if (session == null) return;

		try
		{
			Api31.close(session);
		}
		catch (Throwable ignored)
		{
		}

		session = null;
		targetNanos = 0L;
		tid = -1;
	}

	/** PowerManager.THERMAL_STATUS_*（0 = 正常），API 29 以下恒为 0。 */
	public static int thermalStatus()
	{
		if (Build.VERSION.SDK_INT < 29) return 0;

		try
		{
			return Api29.thermalStatus();
		}
		catch (Throwable t)
		{
			return 0;
		}
	}

	/** GameManager.GAME_MODE_*（0 = 不支持），API 31 以下恒为 0。 */
	public static int gameMode()
	{
		if (Build.VERSION.SDK_INT < 31) return 0;

		try
		{
			return Api31.gameMode();
		}
		catch (Throwable t)
		{
			return 0;
		}
	}

	public static int preferredUpdateNanos()
	{
		return preferredNanos;
	}

	public static int threadId()
	{
		return tid;
	}

	public static String lastError()
	{
		return lastError;
	}

	/** 给 Haxe 写日志用：sdk / 是否成功 / tid / 设备首选刷新间隔 / 失败原因 */
	public static String describe()
	{
		return "sdk=" + Build.VERSION.SDK_INT
			+ " active=" + (session != null)
			+ " tid=" + tid
			+ " preferred=" + preferredNanos
			+ (lastError.length() > 0 ? " err=" + lastError : "");
	}

	private static final class Api29
	{
		static int thermalStatus()
		{
			Context ctx = Extension.mainContext;
			if (ctx == null) return 0;

			PowerManager pm = (PowerManager) ctx.getSystemService(SERVICE_POWER);
			return pm != null ? pm.getCurrentThermalStatus() : 0;
		}
	}

	private static final class Api31
	{
		static boolean start(long target)
		{
			Context ctx = Extension.mainContext;
			if (ctx == null)
			{
				lastError = "no context";
				return false;
			}

			android.os.PerformanceHintManager mgr =
				(android.os.PerformanceHintManager) ctx.getSystemService(SERVICE_PERFORMANCE_HINT);
			if (mgr == null)
			{
				lastError = "no service";
				return false;
			}

			int myTid = Process.myTid();
			android.os.PerformanceHintManager.Session s =
				mgr.createHintSession(new int[]{myTid}, target);
			if (s == null)
			{
				lastError = "session null";
				return false;
			}

			session = s;
			targetNanos = target;
			tid = myTid;

			long preferred = mgr.getPreferredUpdateRateNanos();
			preferredNanos = (int) Math.min(preferred, 2_000_000_000L);
			return true;
		}

		static void report(Object s, long ns)
		{
			((android.os.PerformanceHintManager.Session) s).reportActualWorkDuration(ns);
		}

		static void setTarget(Object s, long ns)
		{
			((android.os.PerformanceHintManager.Session) s).updateTargetWorkDuration(ns);
		}

		static void close(Object s)
		{
			((android.os.PerformanceHintManager.Session) s).close();
		}

		static int gameMode()
		{
			Context ctx = Extension.mainContext;
			if (ctx == null) return 0;

			android.app.GameManager gm = (android.app.GameManager) ctx.getSystemService(SERVICE_GAME);
			return gm != null ? gm.getGameMode() : 0;
		}
	}
}
