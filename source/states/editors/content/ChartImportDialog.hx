package states.editors.content;

import flixel.util.FlxColor;
import flixel.text.FlxText;
import backend.ui.PsychUIButton;
import backend.ui.PsychUICheckBox;
import backend.ui.PsychUIDropDownMenu;
import backend.ui.PsychUIEventHandler;
import backend.Language;

/**
 * 转换结果，由 onConfirm 回传。
 * 导入用 action/diff/convertKeys/targetKeys/extractAudio，导出只用 action/format/diff。
 */
typedef ChartConvertOptions =
{
	var action:Int;
	var format:Null<String>; // 导出目标格式；导入时为 null
	var diff:String;
	var convertKeys:Bool;
	var targetKeys:Int;
	var extractAudio:Bool;
}

/**
 * 通用谱面导入/导出对话框（双向共用一个界面）。
 * 导入：StepMania(.sm/.ssc)、osu!mania(.osu/.osz)、Quaver(.qua/.qp)、MIDI(.mid)、Malody(.mc)
 *   难度选择（多难度时）+ 目标键数转换 + .osz 音频提取 + 载入编辑器/保存 JSON 两种去向
 * 导出：StepMania(.sm/.ssc)、osu!mania(.osu)、Quaver(.qua)
 */
class ChartImportDialog extends MusicBeatSubstate implements PsychUIEventHandler.PsychUIEvent
{
	// 对话框模式
	public static inline var MODE_IMPORT:Int = 0;
	public static inline var MODE_EXPORT:Int = 1;

	// options.action 的取值
	public static inline var ACTION_LOAD:Int = 0;   // 导入：载入编辑器
	public static inline var ACTION_SAVE:Int = 1;   // 导入：保存为 Psych JSON
	public static inline var ACTION_EXPORT:Int = 2; // 导出模式固定回传

	public var onConfirm:Null<ChartConvertOptions->Void> = null;
	public var onCancel:Null<Void->Void> = null;

	// UI 元素
	private var bg:FlxSprite;
	private var titleText:FlxText;
	private var infoText:FlxText;
	private var mode:Int;

	// 导入相关
	private var convertKeysCheck:PsychUICheckBox;
	private var targetKeysDropDown:PsychUIDropDownMenu;
	private var diffDropDown:PsychUIDropDownMenu;
	private var extractAudioCheck:PsychUICheckBox;
	private var diffs:Array<String>;
	private var formatLabel:String;
	private var sourceFormat:String;

	// 导出相关
	private var formatDropDown:PsychUIDropDownMenu;
	private var difficultyDropDown:PsychUIDropDownMenu;
	private var exportFormats:Array<String>;

	private var cancelBtn:PsychUIButton;

	// 检测到的键数（导入时）
	private var detectedKeys:Int;
	// 当前歌曲的键数（导出时）
	private var currentKeys:Int;

	// 对话框尺寸
	private static inline var DIALOG_WIDTH:Int = 540;
	private static inline var PADDING:Int = 24;
	private static inline var BUTTON_WIDTH:Int = 170;
	private static inline var BUTTON_HEIGHT:Int = 32;
	private static inline var CANCEL_HEIGHT:Int = 28;
	private static var EXPORT_DIFFS:Array<String> = ['Beginner', 'Easy', 'Medium', 'Hard', 'Challenge', 'Edit'];

	/**
	 * @param mode MODE_IMPORT 或 MODE_EXPORT
	 * @param detectedKeys 导入时检测到的源键数
	 * @param currentKeys 导出时当前歌曲的键数
	 * @param diffs 导入时源文件的难度列表
	 * @param formatLabel 导入时源格式显示名（如 'osu!mania (.osu)'）
	 * @param sourceFormat 导入时源格式 tag（如 'osz'），用于决定是否显示音频提取选项
	 */
	public function new(mode:Int, ?detectedKeys:Int = 4, ?currentKeys:Int = 4, ?diffs:Array<String> = null, ?formatLabel:String = '',
			?sourceFormat:String = '')
	{
		super();
		this.mode = mode;
		this.detectedKeys = detectedKeys;
		this.currentKeys = currentKeys;
		this.diffs = (diffs != null && diffs.length > 0) ? diffs : ['default'];
		this.formatLabel = formatLabel;
		this.sourceFormat = sourceFormat;
		this.exportFormats = ChartConvertCore.EXPORT_FORMATS;
	}

	override function create()
	{
		persistentUpdate = false;
		persistentDraw = true;

		var showAudioOption:Bool = (mode == MODE_IMPORT && sourceFormat == 'osz');
		var showDiffOption:Bool = (mode == MODE_IMPORT) ? (diffs.length > 1) : true;
		var dialogHeight:Int = contentHeight(showDiffOption, showAudioOption);

		// 背景半透明遮罩
		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.6;
		bg.scrollFactor.set();
		add(bg);

		// 对话框背景
		var boxBg:FlxSprite = new FlxSprite().makeGraphic(DIALOG_WIDTH, dialogHeight, FlxColor.fromString('0xFF2A2A2A'));
		boxBg.screenCenter();
		boxBg.scrollFactor.set();

		// 边框
		var border:FlxSprite = new FlxSprite(boxBg.x - 2, boxBg.y - 2).makeGraphic(DIALOG_WIDTH + 4, dialogHeight + 4, FlxColor.fromString('0xFF444444'));
		border.scrollFactor.set();
		add(border);
		add(boxBg);

		var centerX:Float = boxBg.x + DIALOG_WIDTH / 2;
		var currentY:Float = boxBg.y + PADDING;

		// 标题
		var titleTextStr:String = (mode == MODE_IMPORT)
			? Language.getPhrase('chart_import_title', 'Import Chart')
			: Language.getPhrase('chart_export_title', 'Export Chart');

		titleText = makeText(0, currentY, DIALOG_WIDTH, titleTextStr, 28, FlxColor.WHITE, CENTER);
		titleText.screenCenter(X);
		currentY += 44;

		// 分隔线
		var divider1:FlxSprite = new FlxSprite(boxBg.x + 40, currentY).makeGraphic(DIALOG_WIDTH - 80, 1, FlxColor.fromString('0xFF555555'));
		divider1.scrollFactor.set();
		add(divider1);
		currentY += 16;

		if(mode == MODE_IMPORT)
			createImportUI(boxBg, centerX, currentY, showDiffOption, showAudioOption);
		else
			createExportUI(boxBg, centerX, currentY);

		// 取消按钮 - 底部居中
		var cancelLabel:String = Language.getPhrase('chart_convert_cancel', 'Cancel');
		cancelBtn = new PsychUIButton(0, boxBg.y + dialogHeight - PADDING - CANCEL_HEIGHT, cancelLabel, function()
		{
			if(onCancel != null) onCancel();
			close();
		});
		cancelBtn.normalStyle.bgColor = FlxColor.fromString('0xFFEF4444');
		cancelBtn.text.font = Paths.font('vcr.ttf');
		cancelBtn.normalStyle.textColor = FlxColor.WHITE;
		cancelBtn.resize(120, CANCEL_HEIGHT);
		cancelBtn.x = centerX - cancelBtn.width / 2;
		cancelBtn.scrollFactor.set();
		add(cancelBtn);

		super.create();
	}

	/**
	 * 统一创建 vcr.ttf 文本：抗锯齿跟随 ClientPrefs.data.antialiasing。
	 * 不设的话走 flixel 默认的 ADVANCED + sharpness 400 锐利档，等宽字体小字号下边缘毛刺明显。
	 */
	private function makeText(x:Float, y:Float, width:Float, content:String, size:Int, color:FlxColor, align:FlxTextAlign):FlxText
	{
		var text:FlxText = new FlxText(x, y, width, content, size);
		text.setFormat(Paths.font('vcr.ttf'), size, color, align);
		text.antialiasing = ClientPrefs.data.antialiasing;
		text.scrollFactor.set();
		add(text);
		return text;
	}

	/** 内容区高度，决定对话框整体高度（避免选项多时按钮和取消键重叠） */
	private function contentHeight(showDiffOption:Bool, showAudioOption:Bool):Int
	{
		var content:Int = 0;
		if(mode == MODE_IMPORT)
		{
			content = 66; // 信息文本
			if(showDiffOption) content += 44;
			content += 36 + 48; // 键数复选框 + 目标键数
			if(showAudioOption) content += 36;
			content += 38; // 提示
		}
		else
		{
			content = 62; // 信息文本
			content += 44 + 48; // 格式 + 难度名
			content += 38; // 提示
		}
		content += 18; // 分隔线
		return PADDING + 44 + 16 + content + BUTTON_HEIGHT + 12 + CANCEL_HEIGHT + PADDING;
	}

	/**
	 * 创建导入 UI
	 */
	private function createImportUI(boxBg:FlxSprite, centerX:Float, startY:Float, showDiffOption:Bool, showAudioOption:Bool):Void
	{
		var currentY:Float = startY;

		// 格式与键数信息
		var formatLine:String = (formatLabel != null && formatLabel.length > 0) ? formatLabel + '\n' : '';
		var infoMsg:String = Language.getPhrase('chart_import_detected',
			'{1}Detected: {2}K ({3} key mania)\nChoose difficulty and target key count.',
			[formatLine, Std.string(detectedKeys), Std.string(detectedKeys - 1)]);

		infoText = makeText(boxBg.x + PADDING, currentY, DIALOG_WIDTH - PADDING * 2, infoMsg, 16, FlxColor.fromString('0xFFCCCCCC'), CENTER);
		currentY += 66;

		// 难度选择（单难度文件不显示）
		if(showDiffOption)
		{
			makeText(centerX - 160, currentY + 4, 120,
				Language.getPhrase('chart_difficulty', 'Difficulty:'), 16, FlxColor.WHITE, LEFT);

			diffDropDown = new PsychUIDropDownMenu(centerX - 20, currentY, diffs.copy(), function(id:Int, val:String) {});
			diffDropDown.selectedIndex = 0;
			diffDropDown.textObj.font = Paths.font('vcr.ttf');
			diffDropDown.scrollFactor.set();
			add(diffDropDown);
			currentY += 44;
		}

		// 转换键数复选框
		convertKeysCheck = new PsychUICheckBox(centerX - 140, currentY,
			Language.getPhrase('chart_convert_keys', 'Convert to different key count'), 220);
		convertKeysCheck.checked = (detectedKeys >= 7);
		convertKeysCheck.text.font = Paths.font('vcr.ttf');
		convertKeysCheck.scrollFactor.set();
		add(convertKeysCheck);
		currentY += 36;

		// 目标键数下拉菜单
		makeText(centerX - 160, currentY + 4, 120,
			Language.getPhrase('chart_target_keys', 'Target Keys:'), 16, FlxColor.WHITE, LEFT);

		var keyOptions:Array<String> = [];
		for(i in 4...17) // 4-16K
		{
			var label:String = Std.string(i) + 'K (' + Std.string(i - 1) + ' key mania)';
			if(i == detectedKeys) label += ' (original)';
			keyOptions.push(label);
		}

		targetKeysDropDown = new PsychUIDropDownMenu(centerX - 20, currentY, keyOptions, function(id:Int, val:String) {});
		var defaultIndex:Int = detectedKeys - 4;
		if(detectedKeys < 4) defaultIndex = 0;
		if(detectedKeys > 16) defaultIndex = 12;
		targetKeysDropDown.selectedIndex = defaultIndex;
		targetKeysDropDown.textObj.font = Paths.font('vcr.ttf');
		targetKeysDropDown.scrollFactor.set();
		add(targetKeysDropDown);
		currentY += 48;

		// .osz 才有包内音频可提
		if(showAudioOption)
		{
			extractAudioCheck = new PsychUICheckBox(centerX - 170, currentY,
				Language.getPhrase('chart_import_extract_audio', 'Extract audio from pack (save mode)'), 300);
			extractAudioCheck.checked = true;
			extractAudioCheck.text.font = Paths.font('vcr.ttf');
			extractAudioCheck.scrollFactor.set();
			add(extractAudioCheck);
			currentY += 36;
		}

		// 转换提示
		makeText(boxBg.x + PADDING, currentY, DIALOG_WIDTH - PADDING * 2,
			Language.getPhrase('chart_import_hint',
				'Note: Converting key counts will remap notes to the nearest column.\nHold notes will be preserved when possible.'),
			13, FlxColor.fromString('0xFF888888'), CENTER);
		currentY += 38;

		// 分隔线
		var divider2:FlxSprite = new FlxSprite(boxBg.x + 40, currentY).makeGraphic(DIALOG_WIDTH - 80, 1, FlxColor.fromString('0xFF444444'));
		divider2.scrollFactor.set();
		add(divider2);
		currentY += 18;

		// 两个去向按钮：载入编辑器 / 保存 JSON
		var loadLabel:String = Language.getPhrase('chart_load_editor', 'Load to Editor');
		var loadBtn:PsychUIButton = new PsychUIButton(centerX - BUTTON_WIDTH - 10, currentY, loadLabel, function()
		{
			if(onConfirm != null) onConfirm(buildOptions(ACTION_LOAD));
			close();
		});
		loadBtn.normalStyle.bgColor = FlxColor.fromString('0xFF3B82F6');
		loadBtn.text.font = Paths.font('vcr.ttf');
		loadBtn.normalStyle.textColor = FlxColor.WHITE;
		loadBtn.resize(BUTTON_WIDTH, BUTTON_HEIGHT);
		loadBtn.scrollFactor.set();
		add(loadBtn);

		var saveLabel:String = Language.getPhrase('chart_save_json', 'Save JSON');
		var saveBtn:PsychUIButton = new PsychUIButton(centerX + 10, currentY, saveLabel, function()
		{
			if(onConfirm != null) onConfirm(buildOptions(ACTION_SAVE));
			close();
		});
		saveBtn.normalStyle.bgColor = FlxColor.fromString('0xFF22C55E');
		saveBtn.text.font = Paths.font('vcr.ttf');
		saveBtn.normalStyle.textColor = FlxColor.WHITE;
		saveBtn.resize(BUTTON_WIDTH, BUTTON_HEIGHT);
		saveBtn.scrollFactor.set();
		add(saveBtn);
	}

	private function selectedDiff():String
	{
		if(diffDropDown != null)
			return diffs[diffDropDown.selectedIndex] ?? diffs[0];
		return diffs[0];
	}

	private function buildOptions(action:Int):ChartConvertOptions
	{
		var convertKeys:Bool = (convertKeysCheck != null && convertKeysCheck.checked);
		return {
			action: action,
			format: (mode == MODE_IMPORT) ? null : exportFormats[formatDropDown.selectedIndex],
			diff: (mode == MODE_IMPORT) ? selectedDiff() : EXPORT_DIFFS[difficultyDropDown.selectedIndex],
			convertKeys: convertKeys,
			targetKeys: (targetKeysDropDown != null) ? targetKeysDropDown.selectedIndex + 4 : detectedKeys,
			extractAudio: (extractAudioCheck != null && extractAudioCheck.checked)
		};
	}

	/**
	 * 创建导出 UI
	 */
	private function createExportUI(boxBg:FlxSprite, centerX:Float, startY:Float):Void
	{
		var currentY:Float = startY;

		// 信息文本
		var infoMsg:String = Language.getPhrase('chart_export_info',
			'Export current chart to an external format.\nCurrent key count: {1}K ({2} key mania)',
			[Std.string(currentKeys), Std.string(currentKeys - 1)]);

		infoText = makeText(boxBg.x + PADDING, currentY, DIALOG_WIDTH - PADDING * 2, infoMsg, 16, FlxColor.fromString('0xFFCCCCCC'), CENTER);
		currentY += 62;

		// 格式选择
		makeText(centerX - 160, currentY + 4, 100,
			Language.getPhrase('chart_export_format', 'Format:'), 16, FlxColor.WHITE, LEFT);

		var formatOptions:Array<String> = [for(fmt in exportFormats) ChartConvertCore.FORMAT_LABELS.get(fmt) ?? fmt];
		formatDropDown = new PsychUIDropDownMenu(centerX - 20, currentY, formatOptions, function(id:Int, val:String) {});
		formatDropDown.selectedIndex = 0;
		formatDropDown.textObj.font = Paths.font('vcr.ttf');
		formatDropDown.scrollFactor.set();
		add(formatDropDown);
		currentY += 44;

		// 难度选择
		makeText(centerX - 160, currentY + 4, 100,
			Language.getPhrase('chart_export_difficulty', 'Difficulty:'), 16, FlxColor.WHITE, LEFT);

		difficultyDropDown = new PsychUIDropDownMenu(centerX - 20, currentY, EXPORT_DIFFS.copy(), function(id:Int, val:String) {});
		difficultyDropDown.selectedIndex = 4; // 默认 Challenge
		difficultyDropDown.textObj.font = Paths.font('vcr.ttf');
		difficultyDropDown.scrollFactor.set();
		add(difficultyDropDown);
		currentY += 48;

		// 导出选项提示
		makeText(boxBg.x + PADDING, currentY, DIALOG_WIDTH - PADDING * 2,
			Language.getPhrase('chart_export_hint',
				'Note: .sm is widely compatible, .ssc keeps labels and BPM changes.\n.osu and .qua export the player side only.'),
			13, FlxColor.fromString('0xFF888888'), CENTER);
		currentY += 38;

		// 分隔线
		var divider2:FlxSprite = new FlxSprite(boxBg.x + 40, currentY).makeGraphic(DIALOG_WIDTH - 80, 1, FlxColor.fromString('0xFF444444'));
		divider2.scrollFactor.set();
		add(divider2);
		currentY += 18;

		// 导出按钮
		var exportLabel:String = Language.getPhrase('chart_export', 'Export');
		var exportBtn:PsychUIButton = new PsychUIButton(centerX - 90, currentY, exportLabel, function()
		{
			if(onConfirm != null) onConfirm(buildOptions(ACTION_EXPORT));
			close();
		});
		exportBtn.normalStyle.bgColor = FlxColor.fromString('0xFF22C55E');
		exportBtn.text.font = Paths.font('vcr.ttf');
		exportBtn.normalStyle.textColor = FlxColor.WHITE;
		exportBtn.resize(180, BUTTON_HEIGHT);
		exportBtn.scrollFactor.set();
		add(exportBtn);
	}

	public function UIEvent(id:String, sender:Dynamic)
	{
		// 处理 UI 事件
	}
}
