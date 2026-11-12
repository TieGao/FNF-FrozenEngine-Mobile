package options.psychoptions;

import objects.Character;

class GraphicsSettingsSubState extends BaseOptionsMenu
{
	var antialiasingOption:Int;
	var boyfriend:Character = null;
	public function new()
	{
		title = Language.getPhrase('graphics_menu', 'Graphics Settings');
		rpcTitle = 'Graphics Settings Menu'; //for Discord Rich Presence

		boyfriend = new Character(840, 170, 'bf', true);
		boyfriend.setGraphicSize(Std.int(boyfriend.width * 0.75));
		boyfriend.updateHitbox();
		boyfriend.dance();
		boyfriend.animation.onFinish.add(function (name:String) boyfriend.dance());
		boyfriend.visible = false;

		//I'd suggest using "Low Quality" as an example for making your own option since it is the simplest here
		var option:Option = new Option('Low Quality', //Name
			'If checked, disables some background details,\ndecreases loading times and improves performance.', //Description
			'lowQuality', //Save data variable name
			BOOL); //Variable type
		addOption(option);

		var option:Option = new Option('Anti-Aliasing',
			'If unchecked, disables anti-aliasing, increases performance\nat the cost of sharper visuals.',
			'antialiasing',
			BOOL);
		option.onChange = onChangeAntiAliasing; //Changing onChange is only needed if you want to make a special interaction after it changes the value
		addOption(option);
		antialiasingOption = optionsArray.length-1;

		var option:Option = new Option('Shaders', //Name
			"If unchecked, disables shaders.\nIt's used for some visual effects, and also CPU intensive for weaker.", //Description
			'shaders',
			BOOL);
		addOption(option);

		var option:Option = new Option('GPU Caching',
			"Texture caching mode://ndisabled = RAM only\nauto = drop the CPU copy after the first draw\nfull = upload and drop the CPU copy at load (least RAM, risky on low VRAM)",
			'gpuCaching',
			STRING, ['disabled', 'auto', 'full']);
		addOption(option);

		var option:Option = new Option('Preload to VRAM',
			"Upload textures to VRAM during preload. auto = only when the GPU has 10GB+ dedicated memory; on = always; off = never (upload on first use). Only matters when GPU Caching is set to full",
			'preloadTextureToVRAM',
			STRING, ['auto', 'on', 'off']);
		addOption(option);

		var option:Option = new Option('Keep Song on Freeplay',
			"Keep textures of the last played song loaded when returning to Freeplay, so replaying the same song skips decoding entirely. They are freed when you pick a different song or leave the menu. Costs RAM while you sit in the menu",
			'keepSongAssetsOnFreeplay',
			BOOL);
		addOption(option);


		#if !html5
		var option:Option = new Option('Framerate',
			"Pretty self explanatory, isn't it?",
			'framerate',
			INT);
		addOption(option);

		final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
		option.minValue = 60;
		option.maxValue = 240;
		option.defaultValue = Std.int(FlxMath.bound(refreshRate, option.minValue, option.maxValue));
	option.displayFormat = '%v FPS';
	option.onChange = onChangeFramerate;

	var unlimitedOption:Option = new Option('Unlimited FPS',
		"Removes the framerate cap (lime UNCAPPED profile). Takes priority over FPS Rework.",
		'unlimitedFPS',
		BOOL);
	unlimitedOption.onChange = onChangeFramerate;
	addOption(unlimitedOption);
	#end

	var option:Option = new Option('FPS Rework',
		"If checked, this works around the game becoming \"slow\" and \"smooth\" when the current FPS is lower than the FPS cap.",
		'fpsRework',
		BOOL);
	option.onChange = onChangeFramerate;
	addOption(option);

		super();
		insert(1, boyfriend);
	}

	function onChangeAntiAliasing()
	{
		for (sprite in members)
		{
			var sprite:FlxSprite = cast sprite;
			if(sprite != null && (sprite is FlxSprite) && !(sprite is FlxText)) {
				sprite.antialiasing = ClientPrefs.data.antialiasing;
			}
		}
	}

	function onChangeFramerate()
	{
		ClientPrefs.applyFrameTiming();
	}

	override function changeSelection(change:Int = 0)
	{
		super.changeSelection(change);
		boyfriend.visible = (antialiasingOption == curSelected);
	}
}