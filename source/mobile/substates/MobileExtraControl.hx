package mobile.substates;

import flixel.effects.FlxFlicker;
import flixel.addons.display.FlxBackdrop;
import flixel.addons.display.FlxGridOverlay;

class MobileExtraControl extends MusicBeatSubstate
{
	// 键盘布局数据（保持不变）
	var returnArray:Array<Array<String>> = [
		['Esc', '', 'F1', 'F2', 'F3', 'F4', '', 'F5', 'F6', 'F7', 'F8', '', 'F9', 'F10', 'F11', 'F12', '', 'PrtScrn', 'ScrLk', 'Break'],
		['`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '+', 'BckSpc', '', 'Ins', 'Home', 'PgUp', '', 'NumLk', '#/', '#*', '#-'],
		['Tab', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', '\\', '', 'Del', 'End', 'PgDown', '', '#7', '#8', '#9', '#+'],
		['Caps', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', "'", 'Enter', '', '', '', '', '', '#4', '#5', '#6', ''],
		['Shift', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/', 'Shift', '', '', 'Up', '', '', '#1', '#2', '#3', ''],
		['Ctrl', 'Win', 'Alt', 'Space', 'Alt', 'Win', 'Menu', 'Ctrl', '', 'Left', 'Down', 'Right', '', '#0', '#.', ''],
	];

	var displayArray:Array<Array<String>> = [
		['Esc', '', 'F1', 'F2', 'F3', 'F4', '', 'F5', 'F6', 'F7', 'F8', '', 'F9', 'F10', 'F11', 'F12', '', 'Prt\nScrn', 'Scr\nLk', 'Break'],
		['`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '+', 'Back\nSpace', '', 'Ins', 'Home', 'Pg\nUp', '', 'Num\nLk', '#/', '#*', '#-'],
		['Tab', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', '\\', '', 'Del', 'End', 'Pg\nDown', '', '#7', '#8', '#9', '#+'],
		['Caps', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', "'", 'Enter', '', '', '', '', '', '#4', '#5', '#6', ''],
		['Shift', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/', 'Shift', '', '', 'Up', '', '', '#1', '#2', '#3', ''],
		['Ctrl', 'Win', 'Alt', 'Space', 'Alt', 'Win', 'Menu', 'Ctrl', '', 'Left', 'Down', 'Right', '', '#0', '#.', ''],
	];

	var widthUnits:Array<Array<Float>> = [
		[1, 1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5, 1.25, 1.25, 1.25],
		[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1.5, 1, 1, 1, 1.5, 1, 1, 1, 1],
		[1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5, 1.5, 1, 1, 1, 1.5, 1, 1, 1, 1],
		[1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.37, 1.5, 1, 1, 1, 1.5, 1, 1, 1, 1],
		[2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.96, 1.5, 1, 1, 1, 1.5, 1, 1, 1, 1],
		[1.25, 1.25, 1.25, 6.25, 1.25, 1.25, 1.25, 2, 1.5, 1, 1, 1, 1.5, 2.2, 1, 1],
	];

	var titleTeam:FlxTypedGroup<ChooseButton>;
	var optionTeam:FlxTypedGroup<ChooseButton>;

	var isMain:Bool = true;

	var titleNum:Int = 0;
	var typeNum:Int = 0;
	var chooseNum:Int = 0;

	var rowSelectableIndices:Array<Array<Int>> = [];
	var selectableButtons:Array<ChooseButton> = [];
	var selectableReturnKeys:Array<String> = [];

	var titleWidth:Int = 200;
	var titleHeight:Int = 100;

	var optionWidth:Int = 80;
	var optionHeight:Int = 30;

	var lastHoverTitle:ChooseButton = null;
	var lastHoverKey:ChooseButton = null;
	
	override function create()
	{
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, FlxColor.WHITE);
		bg.scrollFactor.set();
		bg.alpha = 0.5;
		add(bg);

		titleTeam = new FlxTypedGroup<ChooseButton>();
		add(titleTeam);

		// 只创建两个标题：Extra 1 和 Extra 2
		var titles:Array<String> = ["Extra 1", "Extra 2"];
		var totalWidth = titles.length * titleWidth + (titles.length - 1) * 50; // 总宽度
		var startX = (FlxG.width - totalWidth) / 2; // 起始X坐标

		for (i in 0...titles.length)
		{
			var data:String = Reflect.field(ClientPrefs.data, "extraKeyReturn" + (i + 1));
			var _x = startX + i * (titleWidth + 50); // 每个按钮的X坐标
			var titleObject = new ChooseButton(_x, 150, titleWidth, titleHeight, data, titles[i]);
			titleTeam.add(titleObject);
		}

		var grid:FlxBackdrop = new FlxBackdrop(FlxGridOverlay.createGrid(80, 80, 160, 160, true, 0x33FFFFFF, 0x0));
		grid.velocity.set(40, 40);
		grid.alpha = 0;
		FlxTween.tween(grid, {alpha: 1}, 0.5, {ease: FlxEase.quadOut});
		add(grid);

		optionTeam = new FlxTypedGroup<ChooseButton>();
		add(optionTeam);

		// 键盘按钮布局计算（保持不变）
		var gap:Float = 6;
		var margin:Float = 20;
		var unit:Float = 99999;
		for (row in 0...widthUnits.length)
		{
			var totalUnits:Float = 0;
			for (u in widthUnits[row])
				totalUnits += u;
			var available:Float = FlxG.width - margin * 2 - gap * (widthUnits[row].length - 1);
			unit = Math.min(unit, available / totalUnits);
		}
		unit = Math.max(18, Math.min(60, unit));
		var maxRowWidth:Float = 0;
		for (row in 0...widthUnits.length)
		{
			var totalUnits:Float = 0;
			for (u in widthUnits[row])
				totalUnits += u;
			var rowWidth:Float = totalUnits * unit + gap * (widthUnits[row].length - 1);
			maxRowWidth = Math.max(maxRowWidth, rowWidth);
		}
		var keyHeight:Int = Std.int(Math.max(24, Math.min(44, unit * 0.85)));
		var rowGap:Float = 8;
		var startY:Float = 285;
		var startX:Float = (FlxG.width - maxRowWidth) / 2;

		rowSelectableIndices = [];
		selectableButtons = [];
		selectableReturnKeys = [];

		for (row in 0...returnArray.length)
		{
			rowSelectableIndices.push([]);
			var x:Float = startX;
			var y:Float = startY + (keyHeight + rowGap) * row;

			for (col in 0...returnArray[row].length)
			{
				var w:Int = Std.int(unit * widthUnits[row][col]);
				var returnKey:String = returnArray[row][col];
				if (returnKey != null && returnKey != '')
				{
					var h:Int = keyHeight;
					if (returnKey == '#+')
						h = keyHeight * 2 + Std.int(rowGap);
					var titleObject = new ChooseButton(x, y, w, h, displayArray[row][col]);
					optionTeam.add(titleObject);
					rowSelectableIndices[row].push(selectableButtons.length);
					selectableButtons.push(titleObject);
					selectableReturnKeys.push(returnKey);
				}
				x += w + gap;
			}
		}

		updateTitle(titleNum + 1, true, 0);

		addTouchPad("NONE","A_B_C");

		super.create();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		var accept = controls.ACCEPT;
		var right = controls.UI_RIGHT_P;
		var left = controls.UI_LEFT_P;
		var up = controls.UI_UP_P;
		var down = controls.UI_DOWN_P;
		var back = controls.BACK;
		var reset = controls.RESET || touchPad.buttonC.justPressed;

		if (left || right)
		{
			if (isMain)
			{
				titleNum += left ? -1 : 1;
				if (titleNum > 1) titleNum = 0;
				if (titleNum < 0) titleNum = 1;
				updateTitle(titleNum + 1, true, 1);
			}
			else
			{
				chooseNum += left ? -1 : 1;
				var rowLen = rowSelectableIndices[typeNum].length;
				if (rowLen <= 0)
					chooseNum = 0;
				else
				{
					if (chooseNum > rowLen - 1)
						chooseNum = 0;
					if (chooseNum < 0)
						chooseNum = rowLen - 1;
				}
				updateChoose();
			}
		}

		if (up || down)
		{
			if (!isMain)
			{
				var curRow = typeNum;
				var curPos = chooseNum;
				var curIndex:Int = 0;
				if (rowSelectableIndices[curRow].length > 0)
					curIndex = rowSelectableIndices[curRow][curPos];

				var curX:Float = 0;
				if (selectableButtons.length > 0 && curIndex >= 0 && curIndex < selectableButtons.length)
				{
					var btn = selectableButtons[curIndex];
					curX = btn.x + btn.bg.width / 2;
				}

				typeNum += up ? -1 : 1;
				if (typeNum > rowSelectableIndices.length - 1)
					typeNum = 0;
				if (typeNum < 0)
					typeNum = rowSelectableIndices.length - 1;

				var safety:Int = 0;
				while (rowSelectableIndices[typeNum].length <= 0 && safety < rowSelectableIndices.length + 1)
				{
					typeNum += up ? -1 : 1;
					if (typeNum > rowSelectableIndices.length - 1)
						typeNum = 0;
					if (typeNum < 0)
						typeNum = rowSelectableIndices.length - 1;
					safety++;
				}

				var best:Int = 0;
				var bestDist:Float = 999999;
				for (i in 0...rowSelectableIndices[typeNum].length)
				{
					var idx = rowSelectableIndices[typeNum][i];
					var b = selectableButtons[idx];
					var bx = b.x + b.bg.width / 2;
					var d = Math.abs(bx - curX);
					if (d < bestDist)
					{
						bestDist = d;
						best = i;
					}
				}
				chooseNum = best;
				updateChoose();
			}
		}

		if (accept)
		{
			if (isMain)
			{
				isMain = false;
				updateChoose();
			}
			else
			{
				var rowLen = rowSelectableIndices[typeNum].length;
				if (rowLen <= 0)
					return;
				if (chooseNum < 0)
					chooseNum = 0;
				if (chooseNum > rowLen - 1)
					chooseNum = rowLen - 1;
				var realIndex = rowSelectableIndices[typeNum][chooseNum];
				var chosenKey = selectableReturnKeys[realIndex];
				var keyNum = titleNum + 1;
				if (keyNum >= 1 && keyNum <= 2)
				{
					Reflect.setField(ClientPrefs.data, "extraKeyReturn" + keyNum, chosenKey);
				}
				ClientPrefs.saveSettings();
				updateTitle(keyNum, false, 2, true);
			}
		}

		if (back)
		{
			if (isMain)
			{
				ClientPrefs.saveSettings();
				close();
			}
			else
			{
				isMain = true;
				chooseNum = typeNum = 0;
				updateChoose();
			}
		}
		if (reset)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			// 重置两个Extra键位为默认值（例如 'None' 或 'Space'，这里用 'None'）
			ClientPrefs.data.extraKeyReturn1 = ClientPrefs.defaultData.extraKeyReturn1;
			ClientPrefs.data.extraKeyReturn2 = ClientPrefs.defaultData.extraKeyReturn2;
			resetTitle();
		}
		    // ========== 新增：鼠标点击支持 ==========
		if (FlxG.mouse.justPressed)
		{
			// 检测点击标题
			for (i in 0...titleTeam.length)
			{
				var title:ChooseButton = titleTeam.members[i];
				if (FlxG.mouse.overlaps(title.bg))
				{
					titleNum = i;
					isMain = false;
					chooseNum = 0;
					updateTitle(titleNum + 1, true, 1);
					updateChoose();
					return;
				}
			}

			// 检测点击键盘按钮
			for (idx in 0...selectableButtons.length)
			{
				var btn:ChooseButton = selectableButtons[idx];
				if (FlxG.mouse.overlaps(btn.bg))
				{
					var chosenKey:String = selectableReturnKeys[idx];
					var keyNum:Int = titleNum + 1;
					if (keyNum >= 1 && keyNum <= 2)
					{
						Reflect.setField(ClientPrefs.data, "extraKeyReturn" + keyNum, chosenKey);
					}
					ClientPrefs.saveSettings();
					updateTitle(keyNum, false, 2, true);
					return;
				}
			}
		}

		
		// ===== 新增：鼠标悬浮支持 =====
		var mouseX:Float = FlxG.mouse.screenX;
		var mouseY:Float = FlxG.mouse.screenY;
		var hoveredTitle:ChooseButton = null;
		var hoveredKey:ChooseButton = null;

		// 1. 检测标题悬浮
		for (i in 0...titleTeam.length)
		{
			var title:ChooseButton = titleTeam.members[i];
			if (FlxG.mouse.overlaps(title.bg))
			{
				hoveredTitle = title;
				// 更新标题选择（但不改变 isMain）
				if (titleNum != i)
				{
					titleNum = i;
					// 播放滚动音效（与键盘切换一致）
					FlxG.sound.play(Paths.sound('scrollMenu'));
					// 刷新标题高亮（只改变高亮，不闪烁）
					updateTitle(titleNum + 1, true, 0); // 0 表示不额外播放声音
				}
				break; // 只处理一个标题
			}
		}

		for (idx in 0...selectableButtons.length)
		{
			var btn:ChooseButton = selectableButtons[idx];
			if (FlxG.mouse.overlaps(btn.bg))
			{
				hoveredKey = btn;
				var foundRow = -1;
				var foundCol = -1;
				for (row in 0...rowSelectableIndices.length)
				{
					for (col in 0...rowSelectableIndices[row].length)
					{
						if (rowSelectableIndices[row][col] == idx)
						{
							foundRow = row;
							foundCol = col;
							break;
						}
					}
					if (foundRow != -1) break;
				}
				if (foundRow != -1 && (typeNum != foundRow || chooseNum != foundCol))
				{
					typeNum = foundRow;
					chooseNum = foundCol;
					//FlxG.sound.play(Paths.sound('scrollMenu'));
					updateChoose(true); 
					for (btn2 in selectableButtons) btn2.changeColor(FlxColor.BLACK);
					selectableButtons[idx].changeColor(FlxColor.WHITE);
				}
				break; // 只处理一个键盘按钮
			}
		}

	}

	function updateChoose(?isMouse:Bool = false,soundsType:Int = 0)
	{
		if(!isMouse)FlxG.sound.play(Paths.sound('scrollMenu'));
		for (i in 0...selectableButtons.length)
			selectableButtons[i].changeColor(FlxColor.BLACK);

		if (isMain)
			return;

		if (typeNum < 0 || typeNum > rowSelectableIndices.length - 1)
			return;
		if (rowSelectableIndices[typeNum].length <= 0)
			return;
		if (chooseNum < 0)
			chooseNum = 0;
		if (chooseNum > rowSelectableIndices[typeNum].length - 1)
			chooseNum = rowSelectableIndices[typeNum].length - 1;

		var idx = rowSelectableIndices[typeNum][chooseNum];
		selectableButtons[idx].changeColor(FlxColor.WHITE);
	}

	function updateTitle(number:Int = 0, changeBG:Bool = false, soundsType:Int = 0, needFlicker:Bool = false)
	{
		switch (soundsType)
		{
			case 0: // nothing
			case 1:
				FlxG.sound.play(Paths.sound('scrollMenu'));
			case 2:
				FlxG.sound.play(Paths.sound('confirmMenu'));
		}

		for (i in 0...titleTeam.length)
		{
			var title:ChooseButton = titleTeam.members[i];

			if (i == titleNum)
			{
				title.changeExtraText(Reflect.field(ClientPrefs.data, "extraKeyReturn" + number));
				if (needFlicker)
					FlxFlicker.flicker(title, 0.6, 0.075, true, true);
				if (changeBG)
					title.changeColor(FlxColor.WHITE);
			}
			else
			{
				if (changeBG)
					title.changeColor(FlxColor.BLACK);
			}
		}
	}

	function resetTitle()
	{
		for (i in 0...titleTeam.length)
		{
			var title:ChooseButton = titleTeam.members[i];
			var number = i + 1;
			title.changeExtraText(Reflect.field(ClientPrefs.data, "extraKeyReturn" + number));
		}
	}
}

// 辅助类 ChooseButton 保持不变
class ChooseButton extends FlxSpriteGroup
{
	public var bg:FlxSprite;
	public var titleObject:FlxText;
	public var extendTitleObject:FlxText;

	public function new(x:Float, y:Float, width:Int, height:Int, title:String, ?extendTitle:String = null)
	{
		super(x, y);

		bg = new FlxSprite(0, 0).makeGraphic(width, height, FlxColor.WHITE);
		bg.color = FlxColor.BLACK;
		bg.alpha = 0.4;
		bg.scrollFactor.set();
		add(bg);

		titleObject = new FlxText(0, 0, width, title);
		titleObject.setFormat("VCR OSD Mono", 20, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleObject.antialiasing = ClientPrefs.data.antialiasing;
		titleObject.borderSize = 2;
		titleObject.x = bg.width / 2 - titleObject.width / 2;
		titleObject.y = bg.height / 2 - titleObject.height / 2;
		add(titleObject);

		if (extendTitle != null)
		{
			extendTitleObject = new FlxText(0, 0, width, extendTitle);
			extendTitleObject.setFormat("VCR OSD Mono", 30, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			extendTitleObject.antialiasing = ClientPrefs.data.antialiasing;
			extendTitleObject.borderSize = 2;
			extendTitleObject.x = bg.width / 2 - extendTitleObject.width / 2;
			extendTitleObject.y = 30;
			add(extendTitleObject);

			titleObject.y = extendTitleObject.y + 30;
		}
	}

	public function changeColor(color:FlxColor)
	{
		bg.color = color;
		bg.alpha = 0.4;
	}

	public function changeExtraText(text:String)
	{
		titleObject.text = text;
	}
}