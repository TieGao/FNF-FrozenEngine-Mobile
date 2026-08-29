package objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import flixel.text.FlxText;
import flixel.math.FlxMath;
import flixel.util.FlxTimer;
import flixel.math.FlxPoint;

class DraggableBar extends Bar
{
    public var onValueChanged:Float->Void = null;
    public var isDragging(default, null):Bool = false;
    public var draggable:Bool = true;
    public var jumpOnClick:Bool = true;
    
    public var valueText:FlxText = null;
    
    // 缓存相机引用避免重复查找
    var cachedCamera:FlxCamera;
    
    // 缓存点对象避免GC压力
    var mousePos:FlxPoint = FlxPoint.get();
    var bgPos:FlxPoint = FlxPoint.get();
    
    public function new(x:Float, y:Float, image:String = 'healthBar', valueFunction:Void->Float = null, boundX:Float = 0, boundY:Float = 1)
    {
        super(x, y, image, valueFunction, boundX, boundY);
        cachedCamera = cameras[0];
    }
    
    override function update(elapsed:Float)
    {
        super.update(elapsed);
        
        if (!draggable) return;
        
        // 缓存鼠标状态，减少重复调用
        var mouseJustPressed = FlxG.mouse.justPressed;
        var mousePressed = FlxG.mouse.pressed;
        var mouseJustReleased = FlxG.mouse.justReleased;
        var mouseScreenX = FlxG.mouse.screenX;
        
        // 使用更轻量的碰撞检测（矩形重叠）
        var mouseOverBg = bg.overlapsPoint(FlxG.mouse.getScreenPosition(mousePos), true, cachedCamera);
        
        // ===== 开始拖拽：点击时直接跟随鼠标 =====
        if (mouseJustPressed && mouseOverBg && !isDragging)
        {
            isDragging = true;
            
            // 直接计算鼠标在条上的百分比位置（相对于bg）
            var bgScreenPos = bg.getScreenPosition(bgPos, cachedCamera);
            var relativeX = mouseScreenX - bgScreenPos.x - barOffset.x;
            var newPercent = (relativeX / barWidth) * 100;
            newPercent = Math.max(0, Math.min(100, newPercent));
            
            // 直接设置到鼠标位置，而不是从旧位置开始
            if (newPercent != percent)
            {
                percent = newPercent;
                updateBar();
                if (onValueChanged != null) onValueChanged(percent);
            }
            
            // 视觉反馈
            leftBar.alpha = 0.7;
            rightBar.alpha = 0.7;
        }
        
        // ===== 拖拽中 =====
        if (isDragging && mousePressed)
        {
            var bgScreenPos = bg.getScreenPosition(bgPos, cachedCamera);
            var relativeX = mouseScreenX - bgScreenPos.x - barOffset.x;
            var newPercent = (relativeX / barWidth) * 100;
            newPercent = Math.max(0, Math.min(100, newPercent));
            
            if (newPercent != percent)
            {
                percent = newPercent;
                updateBar();
                if (onValueChanged != null) onValueChanged(percent);
            }
        }
        
        // ===== 结束拖拽 =====
        if (mouseJustReleased && isDragging)
        {
            isDragging = false;
            leftBar.alpha = 1;
            rightBar.alpha = 1;
        }
        
        // ===== 点击跳转（仅当没有拖拽过） =====
        // 注意：由于点击时已经直接设置了位置，这个逻辑实际上是多余的
        // 但保留以兼容 jumpOnClick 标志（例如只点击不拖拽的场景）
        if (mouseJustReleased && !isDragging && jumpOnClick && mouseOverBg)
        {
            var bgScreenPos = bg.getScreenPosition(bgPos, cachedCamera);
            var relativeX = mouseScreenX - bgScreenPos.x - barOffset.x;
            var clickPercent = (relativeX / barWidth) * 100;
            clickPercent = Math.max(0, Math.min(100, clickPercent));
            
            if (clickPercent != percent)
            {
                percent = clickPercent;
                updateBar();
                if (onValueChanged != null) onValueChanged(percent);
            }
            
            // 视觉反馈
            leftBar.alpha = 0.5;
            rightBar.alpha = 0.5;
            new FlxTimer().start(0.1, function(_) {
                if (!isDragging) {
                    leftBar.alpha = 1;
                    rightBar.alpha = 1;
                }
            });
        }
        
        // 更新数值显示
        if (valueText != null)
        {
            valueText.text = Math.round(percent) + "%";
            valueText.x = x;
            valueText.y = y - 25;
        }
    }
    
    public function setPercent(value:Float, triggerCallback:Bool = true):Void
    {
        var newPercent = Math.max(0, Math.min(100, value));
        if (newPercent == percent) return;
        
        percent = newPercent;
        updateBar();
        
        if (triggerCallback && onValueChanged != null)
        {
            onValueChanged(percent);
        }
    }
    
    override public function destroy():Void
    {
        if (valueText != null) valueText.destroy();
        if (mousePos != null) mousePos.put();
        if (bgPos != null) bgPos.put();
        super.destroy();
    }
}