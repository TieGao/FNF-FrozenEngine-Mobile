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

package mobile.objects;

import openfl.display.BitmapData;
import openfl.display.Shape;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxSignal.FlxTypedSignal;
import openfl.geom.Matrix;
import objects.Note;

/**
 * A zone with 4 hint's (A hitbox).
 * It's really easy to customize the layout.
 *
 * @author: Karim Akra and Homura Akemi (HomuHomu833)
 */
class Hitbox extends MobileInputManager implements IMobileControls
{
	// MobileInputID 里只定义到 16K，再往上没有可用的输入 ID
	static inline var MAX_COLUMNS:Int = 16;

	final offsetFir:Int = (ClientPrefs.data.hitboxPos ? Std.int(FlxG.height / 4) * 3 : 0);
	final offsetSec:Int = (ClientPrefs.data.hitboxPos ? 0 : Std.int(FlxG.height / 4));

	public var buttonLeft:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_LEFT, MobileInputID.NOTE_LEFT]);
	public var buttonDown:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_DOWN, MobileInputID.NOTE_DOWN]);
	public var buttonUp:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_UP, MobileInputID.NOTE_UP]);
	public var buttonRight:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_RIGHT, MobileInputID.NOTE_RIGHT]);
	public var buttonExtra:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_1]);
	public var buttonExtra2:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_2]);

	// 多 K（5K+）区域，下标即列号；4K 模式下为空
	public var multiKHints:Array<TouchButton> = [];

	public var instance:MobileInputManager;
	public var onButtonDown:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();
	public var onButtonUp:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();

	var storedButtonsIDs:Map<String, Array<MobileInputID>> = new Map<String, Array<MobileInputID>>();
	var currentExtraMode:ExtraActions = NONE;
	// 多 K 区域共用的位图，避免重排时反复新建 BitmapData 撑爆 FlxG.bitmap
	var multiKGraphic:FlxGraphic = null;
	var multiKLabelGraphic:FlxGraphic = null;
	var multiKGraphicWidth:Int = 0;
	var multiKGraphicHeight:Int = 0;

	/**
	 * Create the zone.
	 */
	public function new(?extraMode:ExtraActions = NONE)
	{
		super();

		currentExtraMode = (extraMode == null) ? NONE : extraMode;

		for (button in Reflect.fields(this))
		{
			var field = Reflect.field(this, button);
			if (Std.isOfType(field, TouchButton))
				storedButtonsIDs.set(button, Reflect.getProperty(field, 'IDs'));
		}

		if (getColumnCount() <= 4)
			createStandard4KHints(currentExtraMode);
		else
			createMultiKHints(currentExtraMode);

		for (button in Reflect.fields(this))
		{
			if (Std.isOfType(Reflect.field(this, button), TouchButton))
				Reflect.setProperty(Reflect.getProperty(this, button), 'IDs', storedButtonsIDs.get(button));
		}

		storedButtonsIDs.clear();
		scrollFactor.set();
		updateTrackedButtons();

		instance = this;
	}

	/**
	 * 创建标准 4K 区域（含 SINGLE/DOUBLE 的 extra 布局）。
	 */
	private function createStandard4KHints(extraMode:ExtraActions):Void
	{
		switch (extraMode)
		{
			case NONE:
				add(buttonLeft = createHint(0, 0, Std.int(FlxG.width / 4), FlxG.height, 0xFFC24B99));
				add(buttonDown = createHint(FlxG.width / 4, 0, Std.int(FlxG.width / 4), FlxG.height, 0xFF00FFFF));
				add(buttonUp = createHint(FlxG.width / 2, 0, Std.int(FlxG.width / 4), FlxG.height, 0xFF12FA05));
				add(buttonRight = createHint((FlxG.width / 2) + (FlxG.width / 4), 0, Std.int(FlxG.width / 4), FlxG.height, 0xFFF9393F));
			case SINGLE:
				add(buttonLeft = createHint(0, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3, 0xFFC24B99));
				add(buttonDown = createHint(FlxG.width / 4, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3, 0xFF00FFFF));
				add(buttonUp = createHint(FlxG.width / 2, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3, 0xFF12FA05));
				add(buttonRight = createHint((FlxG.width / 2) + (FlxG.width / 4), offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3,
					0xFFF9393F));
				add(buttonExtra = createHint(0, offsetFir, FlxG.width, Std.int(FlxG.height / 4), 0xFF0066FF));
			case DOUBLE:
				add(buttonLeft = createHint(0, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3, 0xFFC24B99));
				add(buttonDown = createHint(FlxG.width / 4, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3, 0xFF00FFFF));
				add(buttonUp = createHint(FlxG.width / 2, offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3, 0xFF12FA05));
				add(buttonRight = createHint((FlxG.width / 2) + (FlxG.width / 4), offsetSec, Std.int(FlxG.width / 4), Std.int(FlxG.height / 4) * 3,
					0xFFF9393F));
				add(buttonExtra2 = createHint(Std.int(FlxG.width / 2), offsetFir, Std.int(FlxG.width / 2), Std.int(FlxG.height / 4), 0xA6FF00));
				add(buttonExtra = createHint(0, offsetFir, Std.int(FlxG.width / 2), Std.int(FlxG.height / 4), 0xFF0066FF));
		}
	}

	/**
	 * 当前谱面每个玩家的键位数（4 表示标准 4K）。
	 */
	private function getColumnCount():Int
	{
		return (PlayState.SONG != null) ? Note.getColumnsPerPlayer(PlayState.SONG) : 4;
	}

	/**
	 * 按列数算出多 K 区域的宽高与起始 y。
	 */
	private function getMultiKLayout(totalColumns:Int):MultiKLayout
	{
		var hasExtra:Bool = (currentExtraMode != NONE);
		var height:Float = hasExtra ? FlxG.height * 0.75 : FlxG.height;
		return {
			width: Math.ceil(FlxG.width / totalColumns),
			height: Math.ceil(height),
			y: hasExtra ? offsetSec : 0
		};
	}

	/**
	 * 创建多 K（5K+）区域，每列一个 hint，列号就是它在 multiKHints 里的下标。
	 */
	private function createMultiKHints(extraMode:ExtraActions):Void
	{
		var totalColumns:Int = getColumnCount();
		if (totalColumns <= 4) return;

		// 超过 16K 没有对应的 MobileInputID，按 16 列摆放，避免出现整屏点不动的空 hitbox
		if (totalColumns > MAX_COLUMNS)
			totalColumns = MAX_COLUMNS;

		var ids:Array<MobileInputID> = getMultiKIDs(totalColumns);
		if (ids.length <= 0) return;

		var layout:MultiKLayout = getMultiKLayout(totalColumns);
		var colors:Array<FlxColor> = [0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F];
		var hintWidth:Float = FlxG.width / totalColumns;

		for (i in 0...totalColumns)
		{
			var id:MobileInputID = ids[i];
			if (id == NONE) continue;

			// IDs 必须在 updateTrackedButtons() 之前设好，否则这一列查不到任何输入
			var hint:TouchButton = createHint(i * hintWidth, layout.y, layout.width, layout.height, colors[i % colors.length], [id]);
			multiKHints.push(hint);
			add(hint);
		}

		createExtraHints(extraMode);
	}

	/**
	 * 多 K 模式下 extra 占顶部 1/4 屏，布局与 4K 的 SINGLE/DOUBLE 一致。
	 */
	private function createExtraHints(extraMode:ExtraActions):Void
	{
		var extraHeight:Int = Std.int(FlxG.height / 4);
		switch (extraMode)
		{
			case SINGLE:
				add(buttonExtra = createHint(0, offsetFir, FlxG.width, extraHeight, 0xFF0066FF, [MobileInputID.EXTRA_1]));
			case DOUBLE:
				add(buttonExtra2 = createHint(Std.int(FlxG.width / 2), offsetFir, Std.int(FlxG.width / 2), extraHeight, 0xA6FF00,
					[MobileInputID.EXTRA_2]));
				add(buttonExtra = createHint(0, offsetFir, Std.int(FlxG.width / 2), extraHeight, 0xFF0066FF, [MobileInputID.EXTRA_1]));
			default:
		}
	}

	/**
	 * 返回 hint 对应的列索引，不属于多 K 区域时返回 -1。
	 */
	public function getHintColumn(button:TouchButton):Int
	{
		return (button == null) ? -1 : multiKHints.indexOf(button);
	}

	/**
	 * 根据键位数获取对应的多K ID列表
	 */
	private function getMultiKIDs(k:Int):Array<MobileInputID>
	{
		switch(k)
		{
			case 5: return [NOTE_5K_1, NOTE_5K_2, NOTE_5K_3, NOTE_5K_4, NOTE_5K_5];
			case 6: return [NOTE_6K_1, NOTE_6K_2, NOTE_6K_3, NOTE_6K_4, NOTE_6K_5, NOTE_6K_6];
			case 7: return [NOTE_7K_1, NOTE_7K_2, NOTE_7K_3, NOTE_7K_4, NOTE_7K_5, NOTE_7K_6, NOTE_7K_7];
			case 8: return [NOTE_8K_1, NOTE_8K_2, NOTE_8K_3, NOTE_8K_4, NOTE_8K_5, NOTE_8K_6, NOTE_8K_7, NOTE_8K_8];
			case 9: return [NOTE_9K_1, NOTE_9K_2, NOTE_9K_3, NOTE_9K_4, NOTE_9K_5, NOTE_9K_6, NOTE_9K_7, NOTE_9K_8, NOTE_9K_9];
			case 10: return [NOTE_10K_1, NOTE_10K_2, NOTE_10K_3, NOTE_10K_4, NOTE_10K_5, NOTE_10K_6, NOTE_10K_7, NOTE_10K_8, NOTE_10K_9, NOTE_10K_10];
			case 11: return [NOTE_11K_1, NOTE_11K_2, NOTE_11K_3, NOTE_11K_4, NOTE_11K_5, NOTE_11K_6, NOTE_11K_7, NOTE_11K_8, NOTE_11K_9, NOTE_11K_10, NOTE_11K_11];
			case 12: return [NOTE_12K_1, NOTE_12K_2, NOTE_12K_3, NOTE_12K_4, NOTE_12K_5, NOTE_12K_6, NOTE_12K_7, NOTE_12K_8, NOTE_12K_9, NOTE_12K_10, NOTE_12K_11, NOTE_12K_12];
			case 13: return [NOTE_13K_1, NOTE_13K_2, NOTE_13K_3, NOTE_13K_4, NOTE_13K_5, NOTE_13K_6, NOTE_13K_7, NOTE_13K_8, NOTE_13K_9, NOTE_13K_10, NOTE_13K_11, NOTE_13K_12, NOTE_13K_13];
			case 14: return [NOTE_14K_1, NOTE_14K_2, NOTE_14K_3, NOTE_14K_4, NOTE_14K_5, NOTE_14K_6, NOTE_14K_7, NOTE_14K_8, NOTE_14K_9, NOTE_14K_10, NOTE_14K_11, NOTE_14K_12, NOTE_14K_13, NOTE_14K_14];
			case 15: return [NOTE_15K_1, NOTE_15K_2, NOTE_15K_3, NOTE_15K_4, NOTE_15K_5, NOTE_15K_6, NOTE_15K_7, NOTE_15K_8, NOTE_15K_9, NOTE_15K_10, NOTE_15K_11, NOTE_15K_12, NOTE_15K_13, NOTE_15K_14, NOTE_15K_15];
			case 16: return [NOTE_16K_1, NOTE_16K_2, NOTE_16K_3, NOTE_16K_4, NOTE_16K_5, NOTE_16K_6, NOTE_16K_7, NOTE_16K_8, NOTE_16K_9, NOTE_16K_10, NOTE_16K_11, NOTE_16K_12, NOTE_16K_13, NOTE_16K_14, NOTE_16K_15, NOTE_16K_16];
			default: return [];
		}
	}
	/**
	 * 按当前屏幕尺寸重排多 K 区域。
	 */
	public function updateMultiKPositions():Void
	{
		var totalColumns:Int = multiKHints.length;
		if (totalColumns <= 0) return;

		var layout:MultiKLayout = getMultiKLayout(totalColumns);
		var needsNewGraphic:Bool = (multiKGraphic == null
			|| multiKLabelGraphic == null
			|| multiKGraphicWidth != layout.width
			|| multiKGraphicHeight != layout.height);

		if (needsNewGraphic)
		{
			multiKGraphic = createHintGraphic(layout.width, layout.height);
			multiKLabelGraphic = createHintGraphic(layout.width, Math.floor(layout.height * 0.035), true);
			multiKGraphicWidth = layout.width;
			multiKGraphicHeight = layout.height;
		}

		var hintWidth:Float = FlxG.width / totalColumns;
		for (i in 0...totalColumns)
		{
			var hint:TouchButton = multiKHints[i];
			if (hint == null) continue;

			hint.x = i * hintWidth;
			hint.y = layout.y;

			if (needsNewGraphic)
			{
				hint.loadGraphic(multiKGraphic);
				hint.label.loadGraphic(multiKLabelGraphic);
				hint.label.offset.y = 0;
				if (ClientPrefs.data.hitboxPos)
					hint.label.offset.y -= (hint.height - hint.label.height) / 2;
				else
					hint.label.offset.y += (hint.height - hint.label.height) / 2;
				hint.updateHitbox();
			}
		}
	}

	/**
	 * Clean up memory.
	 */
	override function destroy()
	{
		super.destroy();
		onButtonUp.destroy();
		onButtonDown.destroy();

		// 多 K 区域本身在 members 里，已由 super.destroy() 处理
		multiKHints = [];
		multiKGraphic = null;
		multiKLabelGraphic = null;

		for (fieldName in Reflect.fields(this))
		{
			var field = Reflect.field(this, fieldName);
			if (Std.isOfType(field, TouchButton))
				Reflect.setField(this, fieldName, FlxDestroyUtil.destroy(field));
		}
	}

	private function createHint(X:Float, Y:Float, Width:Int, Height:Int, Color:Int = 0xFFFFFF, ?IDs:Array<MobileInputID> = null):TouchButton
	{
		var hint = new TouchButton(X, Y, IDs);
		hint.statusAlphas = [];
		hint.statusIndicatorType = NONE;
		hint.loadGraphic(createHintGraphic(Width, Height));

		hint.label = new FlxSprite();
		hint.labelStatusDiff = (ClientPrefs.data.hitboxType != "Hidden") ? ClientPrefs.data.controlsAlpha : 0.00001;
		hint.label.loadGraphic(createHintGraphic(Width, Math.floor(Height * 0.035), true));
		if (ClientPrefs.data.hitboxPos)
			hint.label.offset.y -= (hint.height - hint.label.height) / 2;
		else
			hint.label.offset.y += (hint.height - hint.label.height) / 2;

		if (ClientPrefs.data.hitboxType != "Hidden")
		{
			var hintTween:FlxTween = null;
			var hintLaneTween:FlxTween = null;

			hint.onDown.callback = function()
			{
				onButtonDown.dispatch(hint);

				if (hintTween != null)
					hintTween.cancel();

				if (hintLaneTween != null)
					hintLaneTween.cancel();

				hintTween = FlxTween.tween(hint, {alpha: ClientPrefs.data.controlsAlpha}, ClientPrefs.data.controlsAlpha / 100, {
					ease: FlxEase.circInOut,
					onComplete: (twn:FlxTween) -> hintTween = null
				});

				hintLaneTween = FlxTween.tween(hint.label, {alpha: 0.00001}, ClientPrefs.data.controlsAlpha / 10, {
					ease: FlxEase.circInOut,
					onComplete: (twn:FlxTween) -> hintTween = null
				});
			}

			hint.onOut.callback = hint.onUp.callback = function()
			{
				onButtonUp.dispatch(hint);

				if (hintTween != null)
					hintTween.cancel();

				if (hintLaneTween != null)
					hintLaneTween.cancel();

				hintTween = FlxTween.tween(hint, {alpha: 0.00001}, ClientPrefs.data.controlsAlpha / 10, {
					ease: FlxEase.circInOut,
					onComplete: (twn:FlxTween) -> hintTween = null
				});

				hintLaneTween = FlxTween.tween(hint.label, {alpha: ClientPrefs.data.controlsAlpha}, ClientPrefs.data.controlsAlpha / 100, {
					ease: FlxEase.circInOut,
					onComplete: (twn:FlxTween) -> hintTween = null
				});
			}
		}
		else
		{
			hint.onDown.callback = () -> onButtonDown.dispatch(hint);
			hint.onOut.callback = hint.onUp.callback = () -> onButtonUp.dispatch(hint);
		}

		hint.immovable = hint.multiTouch = true;
		hint.solid = hint.moves = false;
		hint.alpha = 0.00001;
		hint.label.alpha = (ClientPrefs.data.hitboxType != "Hidden") ? ClientPrefs.data.controlsAlpha : 0.00001;
		hint.canChangeLabelAlpha = false;
		hint.label.antialiasing = hint.antialiasing = ClientPrefs.data.antialiasing;
		hint.color = Color;
		#if FLX_DEBUG
		hint.ignoreDrawDebug = true;
		#end
		return hint;
	}

	function createHintGraphic(Width:Int, Height:Int, ?isLane:Bool = false):FlxGraphic
	{
		var shape:Shape = new Shape();
		shape.graphics.beginFill(0xFFFFFF);

		if (ClientPrefs.data.hitboxType == "No Gradient")
		{
			var matrix:Matrix = new Matrix();
			matrix.createGradientBox(Width, Height, 0, 0, 0);

			if (isLane)
				shape.graphics.beginFill(0xFFFFFF);
			else
				shape.graphics.beginGradientFill(RADIAL, [0xFFFFFF, 0xFFFFFF], [0, 1], [60, 255], matrix, PAD, RGB, 0);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.endFill();
		}
		else if (ClientPrefs.data.hitboxType == "No Gradient (Old)")
		{
			shape.graphics.lineStyle(10, 0xFFFFFF, 1);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.endFill();
		}
		else // if (ClientPrefs.data.hitboxType == 'Gradient')
		{
			shape.graphics.lineStyle(3, 0xFFFFFF, 1);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.lineStyle(0, 0, 0);
			shape.graphics.drawRect(3, 3, Width - 6, Height - 6);
			shape.graphics.endFill();
			if (isLane)
				shape.graphics.beginFill(0xFFFFFF);
			else
				shape.graphics.beginGradientFill(RADIAL, [0xFFFFFF, FlxColor.TRANSPARENT], [1, 0], [0, 255], null, null, null, 0.5);
			shape.graphics.drawRect(3, 3, Width - 6, Height - 6);
			shape.graphics.endFill();
		}

		var bitmap:BitmapData = new BitmapData(Width, Height, true, 0);
		bitmap.draw(shape);

		return FlxG.bitmap.add(bitmap);
	}
}

typedef MultiKLayout =
{
	width:Int,
	height:Int,
	y:Float
}