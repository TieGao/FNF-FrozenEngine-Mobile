package options.objects.win8;

import backend.UIControlTheme;
import openfl.display.BitmapData;
import openfl.display.Shape;

/**
 * 数值条两侧的 "-" / "+" 步进按钮（Win8 描边风格）
 *
 * 真实的 Windows 8 没有这种控件（Metro 的数值只有滑块），所以这是照 Metro 的方角
 * 语言自创的：2px 空心方框 + 居中符号，**不填充任何底色**；悬停 / 按下靠描边转强调色
 * 表达，值触底 / 触顶时整枚转灰。
 *
 * 输入不自己跑：宿主（NumButton）每帧调 processInput()，好跟它自己的"列表滚动惯性
 * 期间挂起输入"走同一个门 —— 否则惯性滑动时还能点到按钮。
 */
class Win8StepButton extends FlxSprite
{
	/** 指针按下并在按钮上松开时触发 */
	public var onClick:Void->Void = null;

	/** false = 当前值已顶到该方向的边界：变灰且不响应点击 */
	public var enabled:Bool = true;

	var plusSign:Bool;
	var hover:Bool = false;
	var pressing:Bool = false;
	var kbHighlight:Bool = false;

	/** 上次套用的颜色（-1 = 还没套过）。每写一次 color 都要重建 colorTransform，别每帧硬写 */
	var lastColor:Int = -1;

	public function new(x:Float, y:Float, size:Float, plusSign:Bool, ?onClick:Void->Void)
	{
		super(x, y);

		this.plusSign = plusSign;
		this.onClick = onClick;

		antialiasing = ClientPrefs.data.antialiasing;
		buildGraphic(Std.int(Math.max(12, size)));

		applyColor();
	}

	// ---------------------------------------------------------
	// 绘制
	// ---------------------------------------------------------
	/** 整张图都是纯白，颜色交给 color 染色 —— 这样换色不用重建 BitmapData */
	function buildGraphic(s:Int):Void
	{
		var t:Int = 2; // Metro 的粗描边
		var shape:Shape = new Shape();

		shape.graphics.beginFill(0xFFFFFFFF);
		// 方框四条边。不用 lineStyle：它沿路径居中画，边框会被裁掉半个线宽
		shape.graphics.drawRect(0, 0, s, t);
		shape.graphics.drawRect(0, s - t, s, t);
		shape.graphics.drawRect(0, t, t, s - t * 2);
		shape.graphics.drawRect(s - t, t, t, s - t * 2);

		// 符号取偶数长度，2px 线宽才正好压在整像素上（22px 按钮 → 10px 臂长）
		var arm:Int = Std.int(s * 0.44);
		if (arm < 6) arm = 6;
		if (arm % 2 == 1) arm++;

		var lo:Int = Std.int((s - arm) * 0.5);
		var mid:Int = Std.int(s * 0.5) - 1;

		shape.graphics.drawRect(lo, mid, arm, t);
		if (plusSign) shape.graphics.drawRect(mid, lo, t, arm);
		shape.graphics.endFill();

		var bmd:BitmapData = new BitmapData(s, s, true, 0x00000000);
		bmd.draw(shape);

		pixels = bmd;
		offset.set(0, 0);
		origin.set(0, 0);
	}

	// ---------------------------------------------------------
	// 输入 / 配色
	// ---------------------------------------------------------
	/**
	 * @param allow     宿主是否允许交互（选项禁用 / 列表滚动惯性时传 false）
	 * @param highlight 键盘是否选中宿主那一行（只影响配色，不能并进 hover —— 那是点击门控）
	 */
	public function processInput(allow:Bool, highlight:Bool = false):Void
	{
		kbHighlight = highlight;

		if (!allow || !enabled)
		{
			hover = false;
			pressing = false;
			OptionInput.releasePointer(this);
			applyColor();
			return;
		}

		var mouse = FlxG.mouse;
		hover = OptionInput.overlaps(this);

		if (hover && mouse.justPressed)
		{
			pressing = true;
			// 和滑块一样独占指针：按住按钮上下拖时别让列表跟着滚
			OptionInput.capturePointer(this);
		}

		if (mouse.justReleased && pressing)
		{
			pressing = false;
			OptionInput.releasePointer(this);
			if (hover && onClick != null) onClick();
		}

		applyColor();
	}

	inline function currentColor():Int
	{
		if (!enabled) return UIControlTheme.off();
		if (pressing) return UIControlTheme.accentPress();
		if (hover || kbHighlight) return UIControlTheme.accentHover();
		return UIControlTheme.border();
	}

	function applyColor():Void
	{
		// 这张白图是 new BitmapData 出来的，会被 Paths.clearStoredMemory() 整片 dispose
		// （FlxG.bitmap 按像素 key 记账，见陷阱 23），所以每帧判活、没了就重画。
		if (graphic == null || graphic.isDestroyed) buildGraphic(Std.int(width));

		var c:Int = currentColor();
		if (c == lastColor) return;
		lastColor = c;
		color = c;
	}

	/** 主题 / 控件风格切换后重新套色 */
	public function refreshTheme():Void
	{
		lastColor = -1;
		applyColor();
	}
}
