package;

import debug.FPSCounter;
import backend.Highscore;
import flixel.FlxGame;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;
import states.TitleState;
#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import psychlua.HScript.HScriptInfos;
#end
import mobile.backend.MobileScaleMode;
import openfl.events.KeyboardEvent;
import lime.system.System as LimeSystem;

#if (linux || mac)
import lime.graphics.Image;
#end
#if COPYSTATE_ALLOWED
import states.CopyState;
#end
import backend.Highscore;

// NATIVE API STUFF, YOU CAN IGNORE THIS AND SCROLL //
#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end

class Main extends Sprite
{
	public static final game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: TitleState, // initial game state
		zoom: -1.0, // 添加 zoom 字段用于自动缩放计算
		framerate: 60, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPSCounter;

	public static final platform:String = #if mobile "Phones" #else "PCs" #end;

	public static function main():Void
	{
		Lib.current.addChild(new Main());
		#if cpp
		cpp.NativeGc.enable(true);
		#elseif hl
		hl.Gc.enable(true);
		#end
	}

	public function new()
	{
		super();
		
		#if mobile
		#if android
		StorageUtil.requestPermissions();
		#end
		Sys.setCwd(StorageUtil.getStorageDirectory());
		#end
		backend.CrashHandler.init();

		#if (cpp && windows)
		backend.Native.fixScaling();
		#end

		// 延迟初始化，确保 stage 已准备好
		if (stage != null)
		{
			init();
		}
		else
		{
			addEventListener(Event.ADDED_TO_STAGE, init);
		}
	}

	private function init(?E:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
		{
			removeEventListener(Event.ADDED_TO_STAGE, init);
		}

		setupGame();
	}

	private function setupGame():Void
	{
		// 从 1.0.1 保留的自动缩放计算
		var stageWidth:Int = Lib.current.stage.stageWidth;
		var stageHeight:Int = Lib.current.stage.stageHeight;

		// 加载保存的数据
		FlxG.save.bind('funkin', CoolUtil.getSavePath());

		var renderResIdx:Int = 0;
		var wideScreen:Bool = false;

		if (FlxG.save.data != null)
		{
			if (Reflect.hasField(FlxG.save.data, 'wideScreen'))
				wideScreen = cast FlxG.save.data.wideScreen;
			if (Reflect.hasField(FlxG.save.data, 'renderResolution'))
				renderResIdx = getRenderResolutionIndex(FlxG.save.data.renderResolution, wideScreen);
		}

		// 根据宽屏模式设置游戏舞台尺寸
		game.width = wideScreen ? Math.round(720 * 21.0 / 9.0) : 1280;
		game.height = 720;

		if (game.zoom == -1.0)
		{
			var ratioX:Float = stageWidth / game.width;
			var ratioY:Float = stageHeight / game.height;
			game.zoom = Math.min(ratioX, ratioY);
			game.width = Math.ceil(stageWidth / game.zoom);
			game.height = Math.ceil(stageHeight / game.zoom);
		}

		// 从 1.0.4 保留的初始化代码（但移到 setupGame 中）
		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0")  ['--no-lua'] #end);
		#end

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		Highscore.load();


		#if HSCRIPT_ALLOWED
		Iris.warn = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(WARN, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('WARNING: $msgInfo', FlxColor.YELLOW);
		}
		Iris.error = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(ERROR, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('ERROR: $msgInfo', FlxColor.RED);
		}
		Iris.fatal = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(FATAL, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '')  + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) {
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('FATAL: $msgInfo', 0xFFBB0000);
		}
		#end

		#if LUA_ALLOWED Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call)); #end
		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
		
		#if mobile
		FlxG.signals.postGameStart.addOnce(() -> {
			FlxG.scaleMode = new MobileScaleMode();
		});
		#end
		
		// 使用计算后的 width/height 和 zoom
		addChild(new FlxGame(game.width, game.height, #if COPYSTATE_ALLOWED !CopyState.checkExistingFiles() ? CopyState : #end game.initialState, #if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, game.skipSplash, game.startFullscreen));

		// 应用保存的渲染分辨率（如果设置）并尝试改善字体清晰度
		#if !mobile
		#if (cpp || hl)
		// 启动时：如果 useDpiSettings 为 true，则不 resize 物理窗口
		var startupResize:Bool = !ClientPrefs.data.useDpiSettings;
		applyRenderResolution(renderResIdx, wideScreen, startupResize);
		#end
		#end

		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if(fpsVar != null) {
			fpsVar.visible = ClientPrefs.data.showFPS;
		}

		#if (linux || mac)
		var icon = Image.fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = #if mobile 30 #else 60 #end;
		#if web
		FlxG.keys.preventDefaultKeys.push(TAB);
		#else
		FlxG.keys.preventDefaultKeys = [TAB];
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end
		
		#if desktop FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, toggleFullScreen); #end

		#if mobile
		#if android FlxG.android.preventDefaultKeys = [BACK]; #end
		LimeSystem.allowScreenTimeout = ClientPrefs.data.screensaver;
		#end

		// shader coords fix
		FlxG.signals.gameResized.add(function (w, h) {
			if(fpsVar != null)
				fpsVar.positionFPS(10, 3, Math.min(w / FlxG.width, h / FlxG.height));
		     if (FlxG.cameras != null) {
			   for (cam in FlxG.cameras.list) {
				if (cam != null && cam.filters != null)
					resetSpriteCache(cam.flashSprite);
			   }
			}

			if (FlxG.game != null)
			resetSpriteCache(FlxG.game);
		});

        ClientPrefs.data.sessionStartTime = Date.now().getTime();

        var currentApp = Application.current;
        if (currentApp != null)
        {
            currentApp.onExit.add(function(code:Int) {
                saveSessionPlaytime();
            });
        }

        #if (cpp || hl)
        Lib.current.stage.window.onClose.add(function() {
            saveSessionPlaytime();
            return true;
        });
        #end
	}

	public static function getResolutionNames(?wideScreen:Bool = null):Array<String>
	{
		if (wideScreen == null)
		{
			wideScreen = ClientPrefs.data != null && Reflect.hasField(ClientPrefs.data, 'wideScreen') && cast ClientPrefs.data.wideScreen;
		}

		if (wideScreen)
		{
			return [
				"1680x720",
				"2520x1080",
				"3360x1440",
				"5040x2160"
			];
		}

		return [
			"1280x720",
			"1600x900",
			"1920x1080",
			"2560x1440",
			"3840x2160"
		];
	}

	public static function getRenderResolutionIndex(value:Dynamic, ?wideScreen:Bool = null, ?fallback:Int = 0):Int
	{
		var names:Array<String> = getResolutionNames(wideScreen);
		if (value == null) return fallback;

		if (Std.isOfType(value, String))
		{
			var label:String = StringTools.trim(cast value);
			var idx:Int = names.indexOf(label);
			if (idx >= 0) return idx;

			var parsed:Null<Int> = Std.parseInt(label);
			if (parsed != null) return parsed;

			return fallback;
		}

		try
		{
			return Std.int(value);
		}
		catch (e:Dynamic)
		{
			return fallback;
		}
	}

	// 分辨率预设 - 宽屏模式下直接返回21:9比例
	public static function getResolutionPreset(resIdx:Int, ?wideScreen:Bool = null):Array<Int>
	{
		var presets:Array<Array<Int>> = [
			[1280, 720],
			[1600, 900],
			[1920, 1080],
			[2560, 1440],
			[3840, 2160]
		];

		if (wideScreen == null)
		{
			wideScreen = ClientPrefs.data != null && Reflect.hasField(ClientPrefs.data, 'wideScreen') && cast ClientPrefs.data.wideScreen;
		}

		// 宽屏模式：返回21:9比例的分辨率
		if (wideScreen)
		{
			var widePresets:Array<Array<Int>> = [
				[Math.round(720 * 21.0 / 9.0), 720],   // 1680x720
				[Math.round(1080 * 21.0 / 9.0), 1080], // 2520x1080
				[Math.round(1440 * 21.0 / 9.0), 1440], // 3360x1440
				[Math.round(2160 * 21.0 / 9.0), 2160]  // 5040x2160
			];
			if (resIdx >= 0 && resIdx < widePresets.length)
				return widePresets[resIdx];
			return widePresets[0];
		}

		// 普通模式
		if (resIdx >= 0 && resIdx < presets.length)
			return presets[resIdx];
		return presets[0];
	}

	#if (cpp || hl)
	/**
	 * 应用渲染分辨率。
	 * @param resIdx       可以是标签字符串 / 整数索引；-1 或 null 表示从 ClientPrefs 读取
	 * @param wideScreen   null 表示从 ClientPrefs 读取
	 * @param resizeWindow 是否调整物理窗口大小（DPI 模式下应当为 false）
	 *
	 * 关键修复：不再内部重复判断 useDpiSettings，完全由调用方通过 resizeWindow 决定。
	 */
	public static function applyRenderResolution(?resIdx:Dynamic = -1, ?wideScreen:Bool = null, ?resizeWindow:Bool = true):Void
	{
		if (ClientPrefs.data == null) return;

		if (resIdx == null || (Std.isOfType(resIdx, Int) && (cast resIdx:Int) == -1))
			resIdx = ClientPrefs.data.renderResolution;

		if (wideScreen == null)
			wideScreen = Reflect.hasField(ClientPrefs.data, 'wideScreen')
				&& cast Reflect.field(ClientPrefs.data, 'wideScreen');

		var resolvedIndex:Int = getRenderResolutionIndex(resIdx, wideScreen, 0);
		var resolved:Array<Int> = getResolutionPreset(resolvedIndex, wideScreen);

		var stageW:Int = resolved[0];
		var stageH:Int = resolved[1];

		// ---- 1. 窗口物理尺寸（仅由 resizeWindow 决定，不再叠加 useDpi 判断）----
		if (resizeWindow)
		{
			try
			{
				var window = Lib.current.stage.window;
				window.resize(stageW, stageH);
				var b = window.display.bounds;
				window.x = Std.int(b.x + (b.width  - stageW) / 2);
				window.y = Std.int(b.y + (b.height - stageH) / 2);
				Lib.current.stage.quality = openfl.display.StageQuality.BEST;
			}
			catch (e:Dynamic) {}
		}

		// ---- 2. OpenFL stage 逻辑尺寸 ----
		var logicalOK:Bool = false;
		try
		{
			@:privateAccess Lib.current.stage.__setLogicalSize(stageW, stageH);
			logicalOK = true;
		}
		catch (e:Dynamic) {}

		// ---- 3. Flixel 逻辑画布尺寸（这一步失败必须让上层知道）----
		FlxG.resizeGame(stageW, stageH);

		// ---- 4. 缩放模式 ----
		FlxG.scaleMode = new flixel.system.scaleModes.RatioScaleMode(false);

		// ---- 5. 清理渲染缓存 ----
		try
		{
			if (FlxG.cameras != null)
				for (cam in FlxG.cameras.list)
					try { resetSpriteCache(cam.flashSprite); } catch (e:Dynamic) {}
			resetSpriteCache(FlxG.game);
		}
		catch (e:Dynamic) {}
	}
	#end

	static function resetSpriteCache(sprite:Sprite):Void {
		@:privateAccess {
		        sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

	function toggleFullScreen(event:KeyboardEvent) {
		if (Controls.instance.justReleased('fullscreen'))
			FlxG.fullscreen = !FlxG.fullscreen;
	}
	
	public static function saveSessionPlaytime():Void
	{
		if (ClientPrefs.data.sessionStartTime > 0)
		{
			var currentTime:Float = Date.now().getTime();
			var sessionSeconds:Float = (currentTime - ClientPrefs.data.sessionStartTime) / 1000;
			ClientPrefs.data.totalPlaytime += sessionSeconds;
			ClientPrefs.saveSettings();
			ClientPrefs.data.sessionStartTime = 0;
		}
	}
}