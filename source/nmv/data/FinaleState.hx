package nmv.data;

/**
 * NMV 剧情推进旗标（Legacy `funkin.data.FinaleState`，实为 enum INACTIVE/ACTIVE/COMPLETE）。
 *
 * 移植端按 GameFlags 同模式做成静态值类：hscript 对 Haxe enum 构造器的字段访问
 * 不可靠，类静态最稳；值用 String，随 ClientPrefs 主档序列化可读。
 * `ClientPrefs.finaleState` 的取值，finale/identity-crisis 的 completion.hx 解锁链用。
 */
class FinaleState
{
	public static final INACTIVE:String = 'INACTIVE';
	public static final ACTIVE:String = 'ACTIVE';
	public static final COMPLETE:String = 'COMPLETE';
}
