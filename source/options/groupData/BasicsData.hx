package options.groupData;

import options.objects.OptionCategory;
import options.Option;
import options.Option.OptionType;
import mobile.backend.MobileScaleMode;

class BasicsData
{
    public static function build():OptionCategory
    {
        var cat = new OptionCategory('Basics', 'Basics', 'specIcon');

        var openControls = new Option('Open Controls', 'Customize key bindings', '', ACTION);
        openControls.actionLabel = 'Open';
        openControls.action = function() {
            if (OptionsPageState.instance != null)
                OptionsPageState.instance.openSubState(new options.psychoptions.ControlsSubState());
            else if (options.keoptions.KEOptionsMenu.instance != null)
                options.keoptions.KEOptionsMenu.instance.openSubState(new options.psychoptions.ControlsSubState());
        };
        cat.add(openControls);

        var openEKControls = new Option('Open EK Controls', 'Customize key bindings for EK mode', '', ACTION);
        openEKControls.actionLabel = 'Open';
        openEKControls.action = function() {
            if (OptionsPageState.instance != null)
                OptionsPageState.instance.openSubState(new options.psychoptions.ExtraKeybindSubState());
            else if (options.keoptions.KEOptionsMenu.instance != null)
                options.keoptions.KEOptionsMenu.instance.openSubState(new options.psychoptions.ExtraKeybindSubState());
        };
        cat.add(openEKControls);

        var adjustDelay = new Option('Adjust Delay and Combo', 'Customize ingame experience', '', ACTION);
        adjustDelay.actionLabel = 'Open';
        adjustDelay.action = function() {
            MusicBeatState.switchState(new options.psychoptions.NoteOffsetState());
        };
        cat.add(adjustDelay);

        // Mobile 相关设置单独一页。id 不能和父分类的 'Basics' 重复，否则页头标题会印两遍。
        var mobileCat = cat.section('Mobile', 'Mobile');

        // Mobile Settings 的选项直接铺在本页
        mobileCat.add(new Option('Extra Controls',
            'Select how many extra buttons you prefer to have?\nThey can be used for mechanics with LUA or HScript.',
            'extraButtons', STRING, ['NONE', 'SINGLE', 'DOUBLE']));

        var controlsAlpha = new Option('Mobile Controls Opacity',
            'Selects the opacity for the mobile buttons (careful not to put it at 0 and lose track of your buttons).',
            'controlsAlpha', PERCENT);
        controlsAlpha.scrollSpeed = 1;
        controlsAlpha.minValue = 0.001;
        controlsAlpha.maxValue = 1;
        controlsAlpha.changeValue = 0.1;
        controlsAlpha.decimals = 1;
        // 本页没有触屏预览控件，改值后要等下次重建移动控件才生效；这里只做音量键刷新
        controlsAlpha.onChange = function() {
            ClientPrefs.toggleVolumeKeys();
        };
        mobileCat.add(controlsAlpha);

        #if mobile
        var screensaver = new Option('Allow Phone Screensaver',
            'If checked, the phone will sleep after going inactive for few seconds.\n(The time depends on your phone\'s options)',
            'screensaver', BOOL);
        screensaver.onChange = function() {
            lime.system.System.allowScreenTimeout = screensaver.getValue();
        };
        mobileCat.add(screensaver);

        var wideScreen = new Option('Wide Screen Mode',
            'If checked, The game will stetch to fill your whole screen. (WARNING: Can result in bad visuals & break some mods that resizes the game/cameras)',
            'wideScreen', BOOL);
        wideScreen.onChange = function() {
            FlxG.scaleMode = new MobileScaleMode();
        };
        mobileCat.add(wideScreen);
        #end

        mobileCat.add(new Option('Hitbox Design', 'Choose how your hitbox should look like.',
           'hitboxType', STRING, ['No Gradient', 'No Gradient (Old)', 'Gradient', 'Hidden']));

        mobileCat.add(new Option('Hitbox Position',
            'If checked, the hitbox will be put at the bottom of the screen, otherwise will stay at the top.',
            'hitboxPos', BOOL));

        mobileCat.add(new Option('Dynamic Controls Color',
            'If checked, the mobile controls color will be set to the notes color in your settings.\n(have effect during gameplay only)',
            'dynamicColors', BOOL));

        var customizeMobileControls = new Option('Customize Mobile Controls', 'Customize mobile controls layout and appearance', '', ACTION);
        customizeMobileControls.actionLabel = 'Open';
        customizeMobileControls.action = function() {
            if (OptionsPageState.instance != null)
                OptionsPageState.instance.openSubState(new mobile.substates.MobileControlSelectSubState());
            else if (options.keoptions.KEOptionsMenu.instance != null)
                options.keoptions.KEOptionsMenu.instance.openSubState(new mobile.substates.MobileControlSelectSubState());
        };
        mobileCat.add(customizeMobileControls);

        var customizeMobileExtraControls = new Option('Customize Mobile Extra Controls', 'Customize extra keys you required', '', ACTION);
        customizeMobileExtraControls.actionLabel = 'Open';
        customizeMobileExtraControls.action = function() {
            if (OptionsPageState.instance != null)
                OptionsPageState.instance.openSubState(new mobile.substates.MobileExtraControl());
            else if (options.keoptions.KEOptionsMenu.instance != null)
                options.keoptions.KEOptionsMenu.instance.openSubState(new mobile.substates.MobileExtraControl());
        };
        mobileCat.add(customizeMobileExtraControls);

        cat.add(new Option('Language', 'Change the game\'s language', 'language', STRING, ['en-US', 'pt-BR', 'zh-CN', 'zh-TW']));
        cat.add(new Option('Color Mode', 'Switch between dark and white mode', 'colorMode', STRING, ['dark', 'white']));
        cat.add(new Option('Control Theme', 'Choose the button style: auto (each UI uses its own style), win10 or win8',
            'controlTheme', STRING, ['auto', 'win10', 'win8']));

        var resetKeyBinds = new Option('Reset KeyBinds', 'Reset key bindings', 'keybinds', ACTION);
        resetKeyBinds.actionLabel = 'Reset';
        resetKeyBinds.action = function() {
            ClientPrefs.resetKeys();
            ClientPrefs.saveSettings();
        };
        cat.add(resetKeyBinds);

        return cat;
    }
}