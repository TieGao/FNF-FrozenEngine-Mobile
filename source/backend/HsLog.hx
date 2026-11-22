package backend;

/**
 * hx 脚本(hscript)报错落盘：Iris.error/warn/fatal 的 Main.hx 重定向与
 * FunkinScript.executeFunc 的吞错 catch 都汇聚到这，统一写 crash/bread.log。
 * 此前这些错误要么只 Sys.println（GUI 下不可见）、要么只上屏刷字，均无记录。
 * 同一条错误只记前 MAX_REPEATS 次——脚本错误多发生在每帧回调里，去重防撑爆。
 */
class HsLog
{
	public static inline var MAX_REPEATS:Int = 3;

	static var seen:Map<String, Int> = [];

	public static function record(level:String, msg:String):Void
	{
		final n:Int = seen.get(msg) ?? 0;
		seen.set(msg, n + 1);
		// 前 MAX_REPEATS 次照记；之后只在 10/50/100 与之后的每个整千补一行累计计数
		//（屏显同款 (x N)，见 PlayState.addTextToDebug）——文件里看得出错误规模，又不刷屏
		if (n < MAX_REPEATS)
		{
			Bread.write('HS $level $msg${n + 1 == MAX_REPEATS ? " （后续重复按阈值记 (x N)）" : ""}');
		}
		else
		{
			final c:Int = n + 1;
			if (c == 10 || c == 50 || c == 100 || c % 1000 == 0)
				Bread.write('HS $level $msg (x$c)');
		}
	}
}
