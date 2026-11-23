package nmv.backend;

/**
 * NMV `Main` 的最小脚本面（Legacy 引擎 Main 同形；corpus 用点 = utils.hx:241
 * `Main.LEGACY_VERSION`，inDevMode TAB 调试面板的版本显示）。
 *
 * 用独立类而不是 FE 的根 Main：FE Main 没有 LEGACY_VERSION 字段，直接注册会让脚本
 * 读到 null；NMV 系脚本对 Main 的其余面（instance/game 等）语料 0 用，按需再补。
 */
class LegacyMain
{
	/** Legacy 引擎自报版本（impostorLegacyPublic source/Main.hx:19 同值）。 */
	public static final LEGACY_VERSION:String = '1.1.3';
}
