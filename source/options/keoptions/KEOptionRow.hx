package options.keoptions;

import flixel.FlxObject;
import shapeEx.Rect;
import options.objects.backend.StringSelect;

/**
 * KEOptionsMenu 的一行：选项名在左、值/控件在右。
 *
 * 刻意不继承 FlxSpriteGroup —— flixel 6.2.0 组级 clipToWorldBounds 必崩（animation=null），
 * 裁剪要逐叶子做。叶子由宿主菜单统一 add 进绘制组，行只持有引用与几何。
 *
 * 行右侧按类型分派：
 * - string / color → StringSelect（win10 下拉，弹层挂菜单 overlay 不参与裁剪）
 * - 其余 → 右对齐值文本（bool 双态、数值、分组 ">" 标记）
 */
class KEOptionRow
{
	public var option:KEOption;
	public var index:Int = 0;

	public var nameText:FlxText;
	public var valueText:FlxText;      // 非 widget 行的右侧文本；widget 行为 null
	public var widget:StringSelect;    // string/color 行的下拉条；其余为 null
	public var indicator:Rect;         // 左侧选中指示条
	public var hitbox:FlxObject;       // 整行命中区（滚出视口时不响应）

	/** 参与裁剪/显隐的叶子（widget 自己裁自己的叶子） */
	var leaves:Array<FlxSprite> = [];

	public var rowVisible:Bool = true;
	public var selected:Bool = false;

	/** 右侧值/控件的对齐右缘（值文本右对齐到这里，控件左缘 = 右缘 - 宽） */
	public var valueRightX:Float;

	public function new(option:KEOption, index:Int, widgetW:Float, accent:FlxColor, overlay:FlxSpriteGroup)
	{
		this.option = option;
		this.index = index;
		valueRightX = KEOptionsMenu.SCREEN_WIDTH - KEOptionsMenu.OPTION_LEFT_MARGIN - 20;

		var rowH:Float = KEOptionsMenu.ROW_H;

		indicator = new Rect(KEOptionsMenu.OPTION_LEFT_MARGIN - 16, 0, 4, 28, 2, 2, accent, 0);
		indicator.antialiasing = ClientPrefs.data.antialiasing;
		indicator.scrollFactor.set();
		leaves.push(indicator);

		nameText = new FlxText(KEOptionsMenu.OPTION_LEFT_MARGIN, 0, 0, "", 32);
		nameText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		nameText.borderSize = 2;
		nameText.borderQuality = 1;
		nameText.scrollFactor.set();
		leaves.push(nameText);

		if ((option.type == "string" && option.options.length > 0) || option.type == "color")
		{
			// win10 下拉条：名左 select 右（color 项的 options 已在 create() 里填 COLOR_NAMES）
			widget = new StringSelect(valueRightX - widgetW, 0, widgetW, 32, option, overlay);
			widget.scrollFactor.set();
		}
		else
		{
			valueText = new FlxText(0, 0, 0, "", 32);
			valueText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
			valueText.borderSize = 2;
			valueText.borderQuality = 1;
			valueText.scrollFactor.set();
			leaves.push(valueText);
		}

		hitbox = new FlxObject(KEOptionsMenu.OPTION_LEFT_MARGIN - 10, 0,
			KEOptionsMenu.SCREEN_WIDTH - (KEOptionsMenu.OPTION_LEFT_MARGIN - 10) * 2, rowH);
		hitbox.scrollFactor.set();
	}

	/** 行顶部 y（内容坐标）：所有叶子按各自高度垂直居中 */
	public function setY(rowY:Float):Void
	{
		var rowH:Float = KEOptionsMenu.ROW_H;
		hitbox.y = rowY;
		for (leaf in leaves)
			leaf.y = rowY + (rowH - leaf.height) * 0.5;
		if (widget != null)
			widget.y = rowY + (rowH - 32) * 0.5;
	}

	/** 右侧值文本右对齐到 valueRightX（文本宽度变化后要重跑） */
	function alignValueText():Void
	{
		if (valueText != null)
			valueText.x = valueRightX - valueText.width;
	}

	public function refreshTexts(valueProvider:KEOption->String):Void
	{
		nameText.text = option.getDisplayName();
		if (widget != null)
		{
			widget.refreshValue();
		}
		else if (valueText != null)
		{
			valueText.text = valueProvider(option);
			alignValueText();
		}
	}

	/** 数值直接输入的预览文本（不落盘，仅改显示） */
	public function setPreviewValue(text:String):Void
	{
		if (valueText == null) return;
		valueText.text = text;
		alignValueText();
	}

	public function setSelected(v:Bool):Void
	{
		selected = v;
		if (indicator != null) indicator.alpha = v ? 1.0 : 0.0;
		nameText.alpha = v ? 1.0 : KEOptionsMenu.OPTION_ALPHA;
		if (valueText != null)
			valueText.alpha = v ? 1.0 : KEOptionsMenu.OPTION_ALPHA;
	}

	/** 三态裁剪之一：整行完全在视口内，清掉全部裁剪 */
	public function clearClip():Void
	{
		for (leaf in leaves)
			leaf.clipRect = null;
		if (widget != null) widget.clearClipRect();
	}

	/** 三态裁剪之二：露出一截，逐叶子按视图坐标裁（widget 的弹层不受影响） */
	public function applyClip(l:Float, t:Float, r:Float, b:Float, cam:flixel.FlxCamera):Void
	{
		for (leaf in leaves)
			leaf.clipToViewBounds(l, t, r, b, cam);
		if (widget != null) widget.applyClipRect(l, t, r, b, cam);
	}

	/** 三态裁剪之三：整行滚出视口，隐藏（含命中区失效） */
	public function setVisible(v:Bool):Void
	{
		rowVisible = v;
		for (leaf in leaves)
			leaf.visible = v;
		if (widget != null) widget.visible = v;
		hitbox.visible = v;
	}

	public function destroyAll():Void
	{
		for (leaf in leaves)
			leaf.destroy();
		leaves = [];
		if (widget != null)
		{
			widget.destroy();
			widget = null;
		}
		if (hitbox != null)
		{
			hitbox.destroy();
			hitbox = null;
		}
	}
}
