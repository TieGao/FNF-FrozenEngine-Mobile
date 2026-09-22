package options.groupData;

import options.objects.OptionCategory;
import options.Option;
import options.Option.OptionType;

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

        // Mobile Settings 二级菜单
        var mobileSettings = new Option('Mobile Settings', 'Configure mobile-specific settings', '', ACTION);
        mobileSettings.actionLabel = 'Open';
        mobileSettings.action = function() {
            if (OptionsPageState.instance != null)
                OptionsPageState.instance.openSubState(new mobile.options.MobileOptionsSubState());
            else if (options.keoptions.KEOptionsMenu.instance != null)
                options.keoptions.KEOptionsMenu.instance.openSubState(new mobile.options.MobileOptionsSubState());
        };
        mobileCat.add(mobileSettings);

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