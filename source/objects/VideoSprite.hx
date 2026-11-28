package objects;

import flixel.addons.display.FlxPieDial;

#if hxvlc
import hxvlc.flixel.FlxVideoSprite;
#end

class VideoSprite extends FlxSpriteGroup {
	/** 存活中的视频实例数：闲置节能（backend.IdleFPSManager）据此跳过降帧，防视频卡成幻灯片 */
	public static var playingVideos:Int = 0;

	#if VIDEOS_ALLOWED
	public var finishCallback:Void->Void = null;
	public var onSkip:Void->Void = null;

	final _timeToSkip:Float = 1;
	public var holdingTime:Float = 0;
	public var videoSprite:FlxVideoSprite;
	public var skipSprite:FlxPieDial;
	public var cover:FlxSprite;
	public var canSkip(default, set):Bool = false;

	private var videoName:String;

	public var waiting:Bool = false;

	public function new(videoName:String, isWaiting:Bool, canSkip:Bool = false, shouldLoop:Dynamic = false) {
		super();

		this.videoName = videoName;
		scrollFactor.set();

		waiting = isWaiting;
		if(!waiting)
		{
			cover = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
			cover.scale.set(FlxG.width + 100, FlxG.height + 100);
			cover.screenCenter();
			cover.scrollFactor.set();
			add(cover);
		}

		// initialize sprites
		videoSprite = new FlxVideoSprite();
		videoSprite.antialiasing = ClientPrefs.data.antialiasing;
		add(videoSprite);
		if(canSkip) this.canSkip = true;

		// callbacks
		if(!shouldLoop) videoSprite.bitmap.onEndReached.add(finishVideo);

		videoSprite.bitmap.onVideoFormatSetup.add(function() // hxvlc 2.3.2 改名（旧 onFormatSetup 已弃用）
		{
			// 事件可能晚于销毁到达（hxvlc 走主线程派发），此时 bitmap 已被置空
			if(alreadyDestroyed || videoSprite == null || videoSprite.bitmap == null) return;
			/*
			#if hxvlc
			var wd:Int = videoSprite.bitmap.formatWidth;
			var hg:Int = videoSprite.bitmap.formatHeight;
			trace('Video Resolution: ${wd}x${hg}');
			videoSprite.scale.set(FlxG.width / wd, FlxG.height / hg);
			#end
			*/
			videoSprite.setGraphicSize(FlxG.width);
			videoSprite.updateHitbox();
			videoSprite.screenCenter();
		});

		// start video and adjust resolution to screen size
		videoSprite.load(videoName, shouldLoop ? ['input-repeat=65545'] : null);

		playingVideos++;
	}

	public var alreadyDestroyed:Bool = false;
	/** 销毁完成时回调，宿主（PlayState）据此清掉指向本实例的悬空引用 */
	public var onDestroyed:Void->Void = null;

	override function destroy()
	{
		if(alreadyDestroyed)
			return;

		// 先置位，避免销毁过程中被父组/回调重入
		alreadyDestroyed = true;
		playingVideos--;

		trace('Video destroyed');
		if(cover != null)
		{
			remove(cover);
			cover.destroy();
			cover = null;
		}
		
		finishCallback = null;
		onSkip = null;

		var destroyedCallback = onDestroyed;
		onDestroyed = null;
		if(destroyedCallback != null)
			destroyedCallback();

		if(FlxG.state != null)
		{
			if(FlxG.state.members != null && FlxG.state.members.contains(this))
				FlxG.state.remove(this);

			if(FlxG.state.subState != null && FlxG.state.subState.members != null && FlxG.state.subState.members.contains(this))
				FlxG.state.subState.remove(this);
		}
		super.destroy();
	}
	function finishVideo()
	{
		if (!alreadyDestroyed)
		{
			if(finishCallback != null)
				finishCallback();
			
			destroy();
		}
	}

	override function update(elapsed:Float)
	{
		if(canSkip)
		{
			if(Controls.instance.pressed('accept'))
			{
				holdingTime = Math.max(0, Math.min(_timeToSkip, holdingTime + elapsed));
			}
			else if (holdingTime > 0)
			{
				holdingTime = Math.max(0, FlxMath.lerp(holdingTime, -0.1, FlxMath.bound(elapsed * 3, 0, 1)));
			}
			updateSkipAlpha();

			if(holdingTime >= _timeToSkip)
			{
				if(onSkip != null) onSkip();
				finishCallback = null;
				// onSkip 里可能已经 destroy（自定义回调），此时 bitmap 已为空
				if(!alreadyDestroyed && videoSprite != null && videoSprite.bitmap != null)
					videoSprite.bitmap.onEndReached.dispatch();
				trace('Skipped video');
				return;
			}
		}
		super.update(elapsed);
	}

	function set_canSkip(newValue:Bool)
	{
		canSkip = newValue;
		if(canSkip)
		{
			if(skipSprite == null)
			{
				skipSprite = new FlxPieDial(0, 0, 40, FlxColor.WHITE, 40, true, 24);
				skipSprite.replaceColor(FlxColor.BLACK, FlxColor.TRANSPARENT);
				skipSprite.x = FlxG.width - (skipSprite.width + 80);
				skipSprite.y = FlxG.height - (skipSprite.height + 72);
				skipSprite.amount = 0;
				add(skipSprite);
			}
		}
		else if(skipSprite != null)
		{
			remove(skipSprite);
			skipSprite.destroy();
			skipSprite = null;
		}
		return canSkip;
	}

	function updateSkipAlpha()
	{
		if(skipSprite == null) return;

		skipSprite.amount = Math.min(1, Math.max(0, (holdingTime / _timeToSkip) * 1.025));
		skipSprite.alpha = FlxMath.remapToRange(skipSprite.amount, 0.025, 1, 0, 1);
	}

	public function play() videoSprite?.play();
	public function resume() videoSprite?.resume();
	public function pause() videoSprite?.pause();

	/**
	 * 安全设置播放速率。
	 * 视频自然播完 / 被跳过 / 切 state 后底层 `bitmap` 会被 hxvlc 置空，
	 * 但宿主可能还持有本实例的引用（例如歌曲结束时写 `playbackRate = 1`），
	 * 此时直接访问 `videoSprite.bitmap.rate` 会抛 Null Object Reference。
	 */
	public function setRate(rate:Float):Void
	{
		if(alreadyDestroyed || videoSprite == null || videoSprite.bitmap == null)
			return;

		videoSprite.bitmap.rate = rate;
	}
	#end
}