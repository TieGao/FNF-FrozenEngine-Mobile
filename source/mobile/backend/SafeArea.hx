package mobile.backend;

import lime.system.System;

/**
 * 边缘安全区（刘海 / 灵动岛 / 挖孔 / 圆角 / Home 条）的画布像素内缩量。
 *
 * 数据源：lime 8.4 的 `System.getDisplay(0).safeArea`——
 *   Android 走 GameActivity JNI 的 DisplayCutout insets，
 *   iOS 走 `UIWindow.safeAreaInsets`（UIKit 原生值，灵动岛/刘海/圆角四边各自独立，
 *   系统报多少就是多少，不需要机型表）。
 * 单位换算：safeArea 是**物理屏幕像素**（display 坐标系），先对窗口求出四边物理内缩，
 * 再按 画布宽/窗口宽 的比例折算成画布 px。
 *
 * 只在 wideScreen 开启时非零：16:9 画布由 MobileScaleMode 居中留黑边，
 * 画布根本伸不到刘海里（黑边把刘海挡在外面），内缩反而白浪费操作区。
 *
 * 手动叠加：ClientPrefs.data.edgeSafeOffset（KE / Win10 Basic 页可调）。
 * 取值时机：TouchPad / Hitbox 构建时各查一次，改设置后下一个界面生效。
 */
class SafeArea
{
	public var left:Float = 0;
	public var top:Float = 0;
	public var right:Float = 0;
	public var bottom:Float = 0;

	public function new()
	{
	}

	public inline function hasAny():Bool
		return left > 0 || top > 0 || right > 0 || bottom > 0;

	public static function get():SafeArea
	{
		var out:SafeArea = new SafeArea();

		#if mobile
		// 16:9 画布伸不到刘海（黑边在外）——只有宽屏铺满时才需要内缩
		if (ClientPrefs.data == null || !ClientPrefs.data.wideScreen) return out;

		var win = FlxG.stage != null ? FlxG.stage.window : null;
		if (win == null || win.width <= 0 || win.height <= 0) return out;

		var display = System.getDisplay(0);
		var safe = display != null ? display.safeArea : null;
		if (safe == null || safe.width <= 0 || safe.height <= 0) return out; // 桌面/取不到 → 无遮挡

		// 物理像素四边内缩（display 坐标系 → 相对窗口）
		var physL:Float = safe.x - win.x;
		var physT:Float = safe.y - win.y;
		var physR:Float = (win.x + win.width) - (safe.x + safe.width);
		var physB:Float = (win.y + win.height) - (safe.y + safe.height);

		// 物理 px → 画布 px（画布按 RatioScaleMode 等比铺窗口，横向比例即统一比例）
		var f:Float = FlxG.width / win.width;

		var manual:Float = ClientPrefs.data.edgeSafeOffset;
		out.left = Math.max(0, physL * f) + manual;
		out.top = Math.max(0, physT * f) + manual;
		out.right = Math.max(0, physR * f) + manual;
		out.bottom = Math.max(0, physB * f) + manual;

		// 兜底：内缩总量吃掉半个屏幕以上必然是读数异常，直接不缩
		if (out.left + out.right >= FlxG.width * 0.5 || out.top + out.bottom >= FlxG.height * 0.5)
		{
			out.left = out.top = out.right = out.bottom = 0;
		}
		#end

		return out;
	}
}
