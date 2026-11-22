package nmv.objects;

import nmv.shaders.RGBPalette;

/**
 * NMV RGBSprite 最小移植。Legacy `funkin.objects.RGBSprite` = FunkinSprite +
 * RGBGraphics 批渲染管线（draw 时逐精灵 pushQuad 写顶点 attribute，由 fork 的
 * flixel RGB 批渲染消费）——FE 的 flixel pin 没有该管线，全量移植=架构项。
 *
 * 语料实际用法（dialogue.hx:368-371）只有：new + loadGraphic +
 * rgbGraphics.setColors([三色])——用批次 15 血条同款路线（RGBPalette
 * attribute→uniform）整精灵单通道重映射，单精灵观感与 NMV 一致。
 * rgbGraphics/rgbShader 面与 RGBGraphics 同构（r/g/b/mult/alpha/flash/enabled/setColors）。
 */
class RGBSprite extends FunkinSprite
{
	public var rgbGraphics:RGBPalette;

	public function new(x:Float = 0, y:Float = 0)
	{
		super(x, y);
		// 默认构造 = 恒等映射（r/g/b 各自保留原通道），dialogue.hx 建完立即 setColors
		rgbGraphics = new RGBPalette();
		shader = rgbGraphics.shader;
	}

	inline function get_rgbShader():RGBPalette // compat
	{
		return rgbGraphics;
	}
}
