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
	final offsetFir:Int = (ClientPrefs.data.hitboxPos ? Std.int(FlxG.height / 4) * 3 : 0);
	final offsetSec:Int = (ClientPrefs.data.hitboxPos ? 0 : Std.int(FlxG.height / 4));

	public var buttonLeft:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_LEFT, MobileInputID.NOTE_LEFT]);
	public var buttonDown:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_DOWN, MobileInputID.NOTE_DOWN]);
	public var buttonUp:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_UP, MobileInputID.NOTE_UP]);
	public var buttonRight:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_RIGHT, MobileInputID.NOTE_RIGHT]);
	public var buttonExtra:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_1]);
	public var buttonExtra2:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_2]);

	// ============================================
	// 新增：多K区域列表
	// ============================================
	public var multiKHints:Array<TouchButton> = [];

	public var instance:MobileInputManager;
	public var onButtonDown:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();
	public var onButtonUp:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();

	var storedButtonsIDs:Map<String, Array<MobileInputID>> = new Map<String, Array<MobileInputID>>();

	/**
	 * Create the zone.
	 */
	public function new(?extraMode:ExtraActions = NONE)
	{
		super();

		for (button in Reflect.fields(this))
		{
			var field = Reflect.field(this, button);
			if (Std.isOfType(field, TouchButton))
				storedButtonsIDs.set(button, Reflect.getProperty(field, 'IDs'));
		}

		// ============================================
		// 修改：根据键位数决定创建4K还是多K
		// ============================================
		var totalColumns:Int = 4;
		if (PlayState.SONG != null)
		{
			totalColumns = Note.getColumnsPerPlayer(PlayState.SONG);
		}

		if (totalColumns <= 4)
		{
			// 创建标准的4K Hitbox
			createStandard4KHints(extraMode);
		}
		else
		{
			// 创建多K Hitbox
			createMultiKHints(extraMode);
		}

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

	// ============================================
	// 新增：创建标准4K Hitbox
	// ============================================
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

	// ============================================
	// 新增：创建多K Hitbox
	// ============================================
	private function createMultiKHints(extraMode:ExtraActions):Void
	{
		var totalColumns:Int = 4;
		if (PlayState.SONG != null)
		{
			totalColumns = Note.getColumnsPerPlayer(PlayState.SONG);
		}

		if (totalColumns <= 4) return;

		// 清除之前的多K区域
		for (hint in multiKHints)
		{
			if (hint != null && members.contains(hint))
			{
				remove(hint);
				hint.destroy();
			}
		}
		multiKHints = [];

		var hintWidth:Float = FlxG.width / totalColumns;
		var hintHeight:Float = FlxG.height;
		if (extraMode != NONE)
		{
			hintHeight = FlxG.height * 0.75;
		}

		var colors:Array<FlxColor> = [
			0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F
		];

		var ids:Array<MobileInputID> = getMultiKIDs(totalColumns);

		for (i in 0...totalColumns)
		{
			if (i >= ids.length) break;
			
			var x:Float = i * hintWidth;
			var y:Float = 0;
			if (extraMode != NONE)
			{
				y = offsetSec;
			}

			var id:MobileInputID = ids[i];
			if (id == NONE) continue;

			var hint:TouchButton = createHint(x, y, Math.ceil(hintWidth), Math.ceil(hintHeight), colors[i % 4]);
			multiKHints.push(hint);
			add(hint);
		}
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
	// ============================================
	// 新增：更新多K区域位置
	// ============================================
	public function updateMultiKPositions():Void
	{
		var totalColumns:Int = multiKHints.length;
		if (totalColumns == 0) return;

		var hintWidth:Float = FlxG.width / totalColumns;
		var hintHeight:Float = FlxG.height;

		for (i in 0...totalColumns)
		{
			var hint:TouchButton = multiKHints[i];
			if (hint != null)
			{
				hint.x = i * hintWidth;
				hint.y = 0;
				var newGraphic:FlxGraphic = createHintGraphic(Math.ceil(hintWidth), Math.ceil(hintHeight));
				hint.loadGraphic(newGraphic);
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

		for (hint in multiKHints)
		{
			if (hint != null) FlxDestroyUtil.destroy(hint);
		}
		multiKHints = [];

		for (fieldName in Reflect.fields(this))
		{
			var field = Reflect.field(this, fieldName);
			if (Std.isOfType(field, TouchButton))
				Reflect.setField(this, fieldName, FlxDestroyUtil.destroy(field));
		}
	}

	private function createHint(X:Float, Y:Float, Width:Int, Height:Int, Color:Int = 0xFFFFFF):TouchButton
	{
		var hint = new TouchButton(X, Y);
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