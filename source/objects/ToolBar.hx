package objects;

import flixel.graphics.FlxGraphic;
import flixel.group.FlxSpriteGroup;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxG;
import flixel.util.FlxDestroyUtil;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.ui.FlxButton;
import flixel.math.FlxRect;
import flixel.util.FlxStringUtil;
import backend.Paths;
import options.GameplayChangersSubstate;
import substates.ResetScoreSubState;
import states.FreeplayState;
import objects.MusicPlayerLegacy;
import options.KEOptionsMenu;
import backend.ui.PsychUIButton; 

class ToolBar extends FlxSpriteGroup
{
    public var background:FlxSprite;
    public var textDisplay:FlxText;
    public var musicPlayer:MusicPlayerLegacy;
    
    // 按钮相关
    public var buttons:Array<PsychUIButton> = [];
    public var buttonTexts:Array<String> = [];
    public var buttonWidth:Int = 250;
    public var buttonSpacing:Int = 5;
    
    // 播放器控制相关
    public var playPauseButton:FlxButton;
    public var stopButton:FlxButton;
    public var prevButton:FlxButton;
    public var nextButton:FlxButton;
    public var timeText:FlxText;
    public var volumeDownButton:FlxButton;
    public var volumeUpButton:FlxButton;
    public var volumeText:FlxText;
    
    // ★★★ 音频可视化对象 ★★★
    public var audioDisplay:AudioDisplay;
    
    // 可视化参数
    public var vizBarCount:Int = 16;
    public var vizQuality:Int = 4;
    public var vizUpdateRate:Float = 33;
    
    // 状态
    public var isMusicPlayerMode:Bool = false;
    public var currentSongName:String = "";
    
    // 引用
    private var freeplayState:FreeplayState;
    private var parentState:MusicBeatState;
    
    // 播放器更新定时器
    private var updateTimer:Float = 0;

    public function new(state:FreeplayState, width:Int, height:Int)
    {
        super();
        
        freeplayState = state;
        parentState = state;
        syncMusicPlayer();
        
        // 从配置读取可视化参数
        loadVizSettings();
        
        background = new FlxSprite(0, 10 + height).makeGraphic(width, height, 0xFF000000);
        background.alpha = 0.6;
        background.scrollFactor.set();
        add(background);
        
        // 创建文本显示（作为备用）
        textDisplay = new FlxText(0, background.y + 4, width, "", 16);
        textDisplay.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER);
        textDisplay.scrollFactor.set();
        textDisplay.visible = false;
        add(textDisplay);
        
        // 创建按钮
        createButtons();
        
        // 创建播放器控件（移除了可视化切换按钮）
        createPlayerControls();
        
        // 默认显示按钮模式
        setNormalMode();
    }
    
    // ===== 可视化参数加载 =====
    
    private function loadVizSettings():Void
    {
        vizBarCount = ClientPrefs.data.relaxAudioNumber;
        vizQuality = ClientPrefs.data.relaxAudioDisplayQuality;
        vizUpdateRate = ClientPrefs.data.audioDisplayUpdate;
    }
    
    // ===== ★★★ 音频可视化管理 ★★★ =====
    
    /**
     * 创建音频可视化（放在屏幕下方）
     */
    private function createAudioDisplay():Void
    {
        // 如果已存在则先销毁
        destroyAudioDisplay();
        
        // 如果没有音乐播放，不创建
        if (FlxG.sound.music == null || !FlxG.sound.music.playing)
        {
            return;
        }
        
        // 创建新的 AudioDisplay（放在屏幕下方）
        audioDisplay = new AudioDisplay(
            FlxG.sound.music,
            0,                              // X 位置
            FlxG.height,              // Y 位置（屏幕底部）
            FlxG.width,                     // 宽度
            300,                            // 高度
            vizBarCount,                    // 条形数量
            2,                              // 条形间距
            0xFF88FF88,                     // 颜色（绿色）
            false                           // 是否对称
        );
        audioDisplay.inRelax = true;
        audioDisplay.stopUpdate = false;
        
        // 添加到父状态
        if (parentState != null)
        {
            parentState.add(audioDisplay);
        }
        else
        {
            var state = FlxG.state;
            if (state != null) state.add(audioDisplay);
        }
    }
    
    /**
     * 销毁音频可视化
     */
    private function destroyAudioDisplay():Void
    {
        if (audioDisplay != null)
        {
            audioDisplay.destroy();
            if (parentState != null)
            {
                parentState.remove(audioDisplay);
            }
            else
            {
                var state = FlxG.state;
                if (state != null) state.remove(audioDisplay);
            }
            audioDisplay = null;
        }
    }
    
    /**
     * 重建音频可视化（参数变化时调用）
     */
    private function rebuildAudioDisplay():Void
    {
        destroyAudioDisplay();
        createAudioDisplay();
    }
    
    // ===== 创建按钮 =====
    
    private function createButtons():Void
    {
        var buttonY:Float = background.y + (background.height - 40) / 2;
        var startX:Float = (FlxG.width - (buttonWidth * 4 + buttonSpacing * 3)) / 2;
        
        var buttonData:Array<{label:String, action:Void->Void}> = [
            {label: Language.getPhrase("options", "OPTIONS"), action: openOptions},
            {label: Language.getPhrase("gameplay", "GAMEPLAY"), action: openGameplayChangers},
            {label: Language.getPhrase("reset", "RESET"), action: resetScore},
            {label: Language.getPhrase("listen", "LISTEN"), action: toggleListenMode}
        ];
        
        for (i in 0...buttonData.length)
        {
            var btn = new PsychUIButton(
                startX + i * (buttonWidth + buttonSpacing),
                buttonY,
                buttonData[i].label,
                buttonData[i].action,
                buttonWidth,
                48
            );
            btn.scrollFactor.set();
            btn.text.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER);
            btn.text.fieldWidth = buttonWidth;
            
            btn.normalStyle = {bgColor: 0xFF333333, textColor: FlxColor.WHITE, bgAlpha: 0.9};
            btn.hoverStyle = {bgColor: 0xFF555577, textColor: FlxColor.WHITE, bgAlpha: 1};
            btn.clickStyle = {bgColor: 0xFF8888AA, textColor: FlxColor.WHITE, bgAlpha: 1};
            
            add(btn);
            buttons.push(btn);
        }
    }
    
    private function createButtonGraphic(width:Int, height:Int, color:Int):FlxGraphic
    {
        var bitmapData:openfl.display.BitmapData = new openfl.display.BitmapData(width, height, true, color);
        return FlxGraphic.fromBitmapData(bitmapData, false, null);
    }
    
    // ===== 创建播放器控件（移除了可视化切换按钮） =====
    
    private function createPlayerControls():Void
    {
        var centerY:Float = background.y + background.height / 2;
        var btnSize:Int = 32;
        
        // 上一首
        prevButton = new FlxButton(0, centerY - btnSize/2, "◀◀", prevAction);
        prevButton.loadGraphic(createButtonGraphic(btnSize, btnSize, 0xFF333333));
        prevButton.label.setFormat(null, 14, FlxColor.WHITE, CENTER);
        prevButton.scrollFactor.set();
        prevButton.label.systemFont = "";
        add(prevButton);
        
        // 播放/暂停
        playPauseButton = new FlxButton(0, centerY - btnSize/2, "▶", playPauseAction);
        playPauseButton.loadGraphic(createButtonGraphic(btnSize, btnSize, 0xFF333366));
        playPauseButton.label.setFormat(null, 16, FlxColor.WHITE, CENTER);
        playPauseButton.scrollFactor.set();
        playPauseButton.label.systemFont = "";
        add(playPauseButton);
        
        // 下一首
        nextButton = new FlxButton(0, centerY - btnSize/2, "▶▶", nextAction);
        nextButton.loadGraphic(createButtonGraphic(btnSize, btnSize, 0xFF333333));
        nextButton.label.setFormat(null, 14, FlxColor.WHITE, CENTER);
        nextButton.scrollFactor.set();
        nextButton.label.systemFont = "";
        add(nextButton);
        
        // 停止
        stopButton = new FlxButton(0, centerY - btnSize/2, "■", stopAction);
        stopButton.loadGraphic(createButtonGraphic(btnSize, btnSize, 0xFF333333));
        stopButton.label.setFormat(null, 16, FlxColor.WHITE, CENTER);
        stopButton.scrollFactor.set();
        stopButton.label.systemFont = "";
        add(stopButton);
        
        // 时间文本
        timeText = new FlxText(0, centerY - 10, 140, "0:00 / 0:00", 14);
        timeText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE, CENTER);
        timeText.scrollFactor.set();
        add(timeText);
        
        // 音量减
        volumeDownButton = new FlxButton(0, centerY - btnSize/2, "-", volumeDownAction);
        volumeDownButton.loadGraphic(createButtonGraphic(btnSize, btnSize, 0xFF333333));
        volumeDownButton.label.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER);
        volumeDownButton.scrollFactor.set();
        add(volumeDownButton);
        
        // 音量加
        volumeUpButton = new FlxButton(0, centerY - btnSize/2, "+", volumeUpAction);
        volumeUpButton.loadGraphic(createButtonGraphic(btnSize, btnSize, 0xFF333333));
        volumeUpButton.label.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER);
        volumeUpButton.scrollFactor.set();
        add(volumeUpButton);
        
        // 音量文本
        volumeText = new FlxText(0, centerY - 10, 60, "100%", 16);
        volumeText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER);
        volumeText.scrollFactor.set();
        add(volumeText);
        
        // 默认隐藏播放器控件
        setPlayerControlsVisible(false);
    }
    
    // ===== 按钮动作函数 =====
    
    private function playPauseAction():Void
    {
        syncMusicPlayer();
        if (musicPlayer != null && musicPlayer.playingMusic)
        {
            musicPlayer.pauseOrResume(!musicPlayer.playing);
            updatePlayPauseButton(musicPlayer.playing);
            return;
        }

        if (freeplayState != null)
        {
            freeplayState.togglePlaySong();
        }
    }
    
    private function stopAction():Void
    {
        if (freeplayState != null)
        {
            freeplayState.stopMusicAndReset();
        }
    }
    
    private function prevAction():Void
    {
        if (freeplayState != null)
        {
            freeplayState.prevSong();
            syncMusicPlayer();
        }
    }
    
    private function nextAction():Void
    {
        if (freeplayState != null)
        {
            freeplayState.nextSong();
            syncMusicPlayer();
        }
    }
    
    private function volumeDownAction():Void
    {
        if (FlxG.sound.music != null)
        {
            var newVol:Float = FlxG.sound.music.volume - 0.1;
            if (newVol < 0) newVol = 0;
            FlxG.sound.music.volume = newVol;
            updateVolumeText();
        }
    }
    
    private function volumeUpAction():Void
    {
        if (FlxG.sound.music != null)
        {
            var newVol:Float = FlxG.sound.music.volume + 0.1;
            if (newVol > 1) newVol = 1;
            FlxG.sound.music.volume = newVol;
            updateVolumeText();
        }
    }
    
    private function updateVolumeText():Void
    {
        if (FlxG.sound.music != null && volumeText != null)
        {
            var volPercent:Int = Math.round(FlxG.sound.music.volume * 100);
            volumeText.text = volPercent + "%";
        }
    }
    
    // ===== 显示控制 =====
    
    private function setPlayerControlsVisible(visible:Bool):Void
    {
        if (playPauseButton != null) { playPauseButton.visible = visible; playPauseButton.active = visible; }
        if (stopButton != null) { stopButton.visible = visible; stopButton.active = visible; }
        if (prevButton != null) { prevButton.visible = visible; prevButton.active = visible; }
        if (nextButton != null) { nextButton.visible = visible; nextButton.active = visible; }
        if (timeText != null) timeText.visible = visible;
        if (volumeDownButton != null) { volumeDownButton.visible = visible; volumeDownButton.active = visible; }
        if (volumeUpButton != null) { volumeUpButton.visible = visible; volumeUpButton.active = visible; }
        if (volumeText != null) volumeText.visible = visible;
    }
    
    public function setNormalMode():Void
    {
        isMusicPlayerMode = false;
        if (textDisplay != null) textDisplay.visible = false;
        
        for (btn in buttons)
        {
            if (btn != null)
            {
                btn.visible = true;
                btn.active = true;
            }
        }
        
        setPlayerControlsVisible(false);
        
        // 销毁可视化
        destroyAudioDisplay();
    }
    
    public function setMusicPlayerMode(songName:String):Void
    {
        isMusicPlayerMode = true;
        currentSongName = songName;
        if (textDisplay != null) textDisplay.visible = false;
        
        for (btn in buttons)
        {
            if (btn != null)
            {
                btn.visible = false;
                btn.active = false;
            }
        }
        
        setPlayerControlsVisible(true);
        updatePlayerPositions();
        syncMusicPlayer();
        updatePlayPauseButton(musicPlayer != null ? musicPlayer.playing : true);
        updateVolumeText();
        
        // 创建可视化
        createAudioDisplay();
    }
    
    private function syncMusicPlayer():Void
    {
        if (musicPlayer == null && freeplayState != null)
            musicPlayer = freeplayState.musicPlayer;
    }
    
    public function updatePlayPauseButton(isPlaying:Bool):Void
    {
        if (playPauseButton != null)
        {
            playPauseButton.label.text = isPlaying ? "❚❚" : "▶";
        }
    }
    
    public function updateTimeDisplay(current:Float, total:Float):Void
    {
        if (timeText != null)
        {
            var currentStr:String = FlxStringUtil.formatTime(current / 1000, false);
            var totalStr:String = FlxStringUtil.formatTime(total / 1000, false);
            timeText.text = currentStr + " / " + totalStr;
        }
    }
    
    private function updatePlayerPositions():Void
    {
        var centerY:Float = background.y + background.height / 2;
        var startX:Float = 10;
        var currentX:Float = startX;
        var spacing:Float = 4;
        
        if (prevButton != null)
        {
            prevButton.x = currentX;
            prevButton.y = centerY - prevButton.height/2;
            currentX += prevButton.width + spacing;
        }
        
        if (playPauseButton != null)
        {
            playPauseButton.x = currentX;
            playPauseButton.y = centerY - playPauseButton.height/2;
            currentX += playPauseButton.width + spacing;
        }
        
        if (nextButton != null)
        {
            nextButton.x = currentX;
            nextButton.y = centerY - nextButton.height/2;
            currentX += nextButton.width + spacing;
        }
        
        if (stopButton != null)
        {
            stopButton.x = currentX;
            stopButton.y = centerY - stopButton.height/2;
            currentX += stopButton.width + spacing;
        }
        
        if (timeText != null)
        {
            timeText.x = currentX;
            timeText.y = centerY - timeText.height/2;
            currentX += timeText.width + spacing;
        }
        
        if (volumeDownButton != null)
        {
            volumeDownButton.x = currentX;
            volumeDownButton.y = centerY - volumeDownButton.height/2;
            currentX += volumeDownButton.width + spacing;
        }
        
        if (volumeUpButton != null)
        {
            volumeUpButton.x = currentX;
            volumeUpButton.y = centerY - volumeUpButton.height/2;
            currentX += volumeUpButton.width + spacing;
        }
        
        if (volumeText != null)
        {
            volumeText.x = currentX;
            volumeText.y = centerY - volumeText.height/2;
        }
    }
    
    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);
        
        if (isMusicPlayerMode)
        {
            syncMusicPlayer();
            updateTimer += elapsed;
            if (updateTimer >= 0.05)
            {
                updateTimer = 0;
                if (FlxG.sound.music != null)
                {
                    updateTimeDisplay(FlxG.sound.music.time, FlxG.sound.music.length);
                    updatePlayPauseButton(musicPlayer != null ? musicPlayer.playing : FlxG.sound.music.playing);
                }
            }
            
            // 如果音乐停止，销毁可视化
            if (FlxG.sound.music != null && !FlxG.sound.music.playing && audioDisplay != null)
            {
                destroyAudioDisplay();
            }
        }
    }
    
    // ===== 按钮回调函数 =====
    
    private function openOptions():Void
    {
        if (freeplayState != null)
        {
            MusicBeatState.switchState(new KEOptionsMenu());
            FlxG.sound.play(Paths.sound('scrollMenu'));
        }
    }
    
    private function openGameplayChangers():Void
    {
        if (freeplayState != null && freeplayState.persistentUpdate)
        {
            freeplayState.persistentUpdate = false;
            freeplayState.openSubState(new GameplayChangersSubstate());
        }
    }
    
    private function resetScore():Void
    {
        if (freeplayState != null && FreeplayState.curSelected >= 0 && FreeplayState.curSelected < freeplayState.songs.length)
        {
            freeplayState.persistentUpdate = false;
            var song = freeplayState.songs[FreeplayState.curSelected];
            freeplayState.openSubState(new ResetScoreSubState(song.songName, freeplayState.curDifficulty, song.songCharacter, -1, song.folder));
            FlxG.sound.play(Paths.sound('scrollMenu'));
        }
    }
    
    private function toggleListenMode():Void
    {
        if (freeplayState != null)
        {
            freeplayState.togglePlaySong();
        }
    }
    
    public function setText(message:String):Void
    {
        if (textDisplay != null && !isMusicPlayerMode)
        {
            textDisplay.text = message;
        }
    }
    
    public function setXY(x:Float, y:Float):Void
    {
        if (background != null)
        {
            background.x = x;
            background.y = y;
        }
        if (textDisplay != null)
        {
            textDisplay.x = x;
            textDisplay.y = y + 4;
        }
        
        var buttonY:Float = background.y + (background.height - 40) / 2;
        var startX:Float = (FlxG.width - (buttonWidth * 4 + buttonSpacing * 3)) / 2;
        
        for (i in 0...buttons.length)
        {
            if (buttons[i] != null)
            {
                buttons[i].x = startX + i * (buttonWidth + buttonSpacing);
                buttons[i].y = buttonY;
            }
        }
        
        updatePlayerPositions();
    }
    
    override public function destroy():Void
    {
        FlxTween.cancelTweensOf(this);
        
        // 销毁可视化
        destroyAudioDisplay();
        
        background = FlxDestroyUtil.destroy(background);
        textDisplay = FlxDestroyUtil.destroy(textDisplay);
        
        for (btn in buttons)
            FlxDestroyUtil.destroy(btn);
        buttons = null;
        
        playPauseButton = FlxDestroyUtil.destroy(playPauseButton);
        stopButton = FlxDestroyUtil.destroy(stopButton);
        prevButton = FlxDestroyUtil.destroy(prevButton);
        nextButton = FlxDestroyUtil.destroy(nextButton);
        timeText = FlxDestroyUtil.destroy(timeText);
        volumeDownButton = FlxDestroyUtil.destroy(volumeDownButton);
        volumeUpButton = FlxDestroyUtil.destroy(volumeUpButton);
        volumeText = FlxDestroyUtil.destroy(volumeText);
        
        freeplayState = null;
        parentState = null;
        
        super.destroy();
    }
}