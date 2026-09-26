package debug;

/**
 * 机型号(machine id)到人类可读机型名的映射。
 *
 * iOS 的 `lime.system.System.deviceModel` 返回 `hw.machine`，形如 "iPhone15,3"、"iPad14,5"；
 * Android 返回 `android.os.Build.MODEL`（lime 已剥掉厂商前缀）。两者都可能遇到本表未收录的
 * 新机型，此时一律回退到原样显示机型号 —— 不猜、不编。
 */
class DeviceModelMap
{
	/** 机型名超出这个长度就截断（FPS 文本一行里还要塞 OS / Render） */
	public static final MAX_LENGTH:Int = 24;

	/**
	 * 截断后保留的前缀长度。
	 * 取 `MAX_LENGTH - 1` 是为了给省略号留位，总长不超过 MAX_LENGTH。
	 */
	static final ELLIPSIS:String = '…';

	/**
	 * iOS 机型号 -> 机型名。
	 *
	 * 用 `Map` 而不是 `switch`：`FPSCounter.updateText()` 每次刷新都要查一次
	 * （最高 20Hz），线性 switch 走两三百条分支没必要。
	 */
	static final IOS_MAP:Map<String, String> = [
		// ===== iPhone =====
		// 6s / SE 一代
		'iPhone8,1' => 'iPhone 6s',
		'iPhone8,2' => 'iPhone 6s Plus',
		'iPhone8,4' => 'iPhone SE',
		// 7 / 8 / X
		'iPhone9,1' => 'iPhone 7',
		'iPhone9,3' => 'iPhone 7',
		'iPhone9,2' => 'iPhone 7 Plus',
		'iPhone9,4' => 'iPhone 7 Plus',
		'iPhone10,1' => 'iPhone 8',
		'iPhone10,4' => 'iPhone 8',
		'iPhone10,2' => 'iPhone 8 Plus',
		'iPhone10,5' => 'iPhone 8 Plus',
		'iPhone10,3' => 'iPhone X',
		'iPhone10,6' => 'iPhone X',
		// XS / XR
		'iPhone11,2' => 'iPhone XS',
		'iPhone11,4' => 'iPhone XS Max',
		'iPhone11,6' => 'iPhone XS Max',
		'iPhone11,8' => 'iPhone XR',
		// 11 系列
		'iPhone12,1' => 'iPhone 11',
		'iPhone12,3' => 'iPhone 11 Pro',
		'iPhone12,5' => 'iPhone 11 Pro Max',
		'iPhone12,8' => 'iPhone SE (2nd)',
		// 12 系列
		'iPhone13,1' => 'iPhone 12 mini',
		'iPhone13,2' => 'iPhone 12',
		'iPhone13,3' => 'iPhone 12 Pro',
		'iPhone13,4' => 'iPhone 12 Pro Max',
		// 13 系列
		'iPhone14,2' => 'iPhone 13 Pro',
		'iPhone14,3' => 'iPhone 13 Pro Max',
		'iPhone14,4' => 'iPhone 13 mini',
		'iPhone14,5' => 'iPhone 13',
		'iPhone14,6' => 'iPhone SE (3rd)',
		// 14 系列
		'iPhone14,7' => 'iPhone 14',
		'iPhone14,8' => 'iPhone 14 Plus',
		'iPhone15,2' => 'iPhone 14 Pro',
		'iPhone15,3' => 'iPhone 14 Pro Max',
		// 15 系列
		'iPhone15,4' => 'iPhone 15',
		'iPhone15,5' => 'iPhone 15 Plus',
		'iPhone16,1' => 'iPhone 15 Pro',
		'iPhone16,2' => 'iPhone 15 Pro Max',
		// 16 系列
		'iPhone17,1' => 'iPhone 16 Pro',
		'iPhone17,2' => 'iPhone 16 Pro Max',
		'iPhone17,3' => 'iPhone 16',
		'iPhone17,4' => 'iPhone 16 Plus',
		'iPhone17,5' => 'iPhone 16e',
		// 17 系列
		'iPhone18,1' => 'iPhone 17 Pro',
		'iPhone18,2' => 'iPhone 17 Pro Max',
		'iPhone18,3' => 'iPhone 17',
		'iPhone18,4' => 'iPhone Air',

		// ===== iPad =====
		// 早期数字系列 / Air / mini
		'iPad4,1' => 'iPad Air',
		'iPad4,2' => 'iPad Air',
		'iPad4,3' => 'iPad Air',
		'iPad4,4' => 'iPad Air',
		'iPad4,5' => 'iPad Air',
		'iPad4,6' => 'iPad Air',
		'iPad4,7' => 'iPad mini 2',
		'iPad4,8' => 'iPad mini 2',
		'iPad4,9' => 'iPad mini 2',
		'iPad5,1' => 'iPad mini 4',
		'iPad5,2' => 'iPad mini 4',
		'iPad5,3' => 'iPad Air 2',
		'iPad5,4' => 'iPad Air 2',
		'iPad6,3' => 'iPad Pro 9.7"',
		'iPad6,4' => 'iPad Pro 9.7"',
		'iPad6,7' => 'iPad Pro 12.9" (1st)',
		'iPad6,8' => 'iPad Pro 12.9" (1st)',
		'iPad6,11' => 'iPad 5',
		'iPad6,12' => 'iPad 5',
		'iPad7,1' => 'iPad Pro 12.9" (2nd)',
		'iPad7,2' => 'iPad Pro 12.9" (2nd)',
		'iPad7,3' => 'iPad Pro 10.5"',
		'iPad7,4' => 'iPad Pro 10.5"',
		'iPad7,5' => 'iPad 6',
		'iPad7,6' => 'iPad 6',
		'iPad7,11' => 'iPad 6',
		'iPad7,12' => 'iPad 6',
		// Pro 11" / 12.9" 3rd 起
		'iPad8,1' => 'iPad Pro 11" (1st)',
		'iPad8,2' => 'iPad Pro 11" (1st)',
		'iPad8,3' => 'iPad Pro 11" (1st)',
		'iPad8,4' => 'iPad Pro 11" (1st)',
		'iPad8,5' => 'iPad Pro 12.9" (3rd)',
		'iPad8,6' => 'iPad Pro 12.9" (3rd)',
		'iPad8,7' => 'iPad Pro 12.9" (3rd)',
		'iPad8,8' => 'iPad Pro 12.9" (3rd)',
		'iPad8,9' => 'iPad 7',
		'iPad8,10' => 'iPad 7',
		'iPad8,11' => 'iPad 7',
		'iPad8,12' => 'iPad 7',
		'iPad11,1' => 'iPad mini 5',
		'iPad11,2' => 'iPad mini 5',
		'iPad11,3' => 'iPad Air 3',
		'iPad11,4' => 'iPad Air 3',
		'iPad11,5' => 'iPad Air 4',
		'iPad11,6' => 'iPad Air 4',
		'iPad11,7' => 'iPad Air 4',
		'iPad12,1' => 'iPad 8',
		'iPad12,2' => 'iPad 8',
		'iPad13,1' => 'iPad 9',
		'iPad13,2' => 'iPad 9',
		'iPad13,4' => 'iPad Pro 11" (2nd)',
		'iPad13,5' => 'iPad Pro 11" (2nd)',
		'iPad13,6' => 'iPad Pro 11" (2nd)',
		'iPad13,7' => 'iPad Pro 11" (2nd)',
		'iPad13,8' => 'iPad Pro 12.9" (4th)',
		'iPad13,9' => 'iPad Pro 12.9" (4th)',
		'iPad13,10' => 'iPad Pro 12.9" (4th)',
		'iPad13,11' => 'iPad Pro 12.9" (4th)',
		// mini 6 / Air 5 / iPad 10 / Pro 5th(M1) / M2 / M4
		'iPad14,1' => 'iPad mini 6',
		'iPad14,2' => 'iPad mini 6',
		'iPad14,3' => 'iPad Air 5',
		'iPad14,4' => 'iPad Air 5',
		'iPad14,5' => 'iPad 10',
		'iPad14,6' => 'iPad 10',
		'iPad13,16' => 'iPad Pro 12.9" (5th)',
		'iPad13,17' => 'iPad Pro 12.9" (5th)',
		'iPad13,18' => 'iPad Pro 11" (3rd)',
		'iPad13,19' => 'iPad Pro 11" (3rd)',
		'iPad14,7' => 'iPad Pro 11" (4th)',
		'iPad14,8' => 'iPad Pro 11" (4th)',
		'iPad14,9' => 'iPad Pro 11" (4th)',
		'iPad14,10' => 'iPad Pro 11" (4th)',
		'iPad14,11' => 'iPad Pro 12.9" (6th)',
		'iPad14,12' => 'iPad Pro 12.9" (6th)',
		'iPad14,13' => 'iPad Pro 12.9" (6th)',
		'iPad14,14' => 'iPad Pro 12.9" (6th)',
		'iPad14,15' => 'iPad Air 6',
		'iPad14,16' => 'iPad Air 6',
		'iPad16,1' => 'iPad Pro 11" (M4)',
		'iPad16,2' => 'iPad Pro 11" (M4)',
		'iPad16,3' => 'iPad Pro 13" (M4)',
		'iPad16,4' => 'iPad Pro 13" (M4)',

		// ===== iPod touch =====
		'iPod9,1' => 'iPod touch 7'
	];

	/**
	 * Android 型号别名归一化。
	 *
	 * lime 只剥了厂商前缀（`Xiaomi 14` -> `14`），剩下的写法差异、内部代号、
	 * 以及"厂商名被吞进型号里"的情况仍需在此收敛。查不到原样返回，交给 `shorten` 兜底。
	 */
	static final ANDROID_ALIAS:Map<String, String> = [
		// Google Pixel：Build.MODEL 是 "Pixel 7" 这种带空格的写法
		'Pixel' => 'Pixel',
		'Pixel XL' => 'Pixel XL',
		// 三星：lime 剥掉 "samsung" 后剩 SM-xxx / GT-xxx，保留原样但去掉分隔
		// OPPO / vivo / 一加 / realme 常见内部代号
		'CPH2451' => 'OPPO Find X6',
		'PHB110' => 'OPPO Find X7',
		'PJD110' => 'OnePlus 12',
		'CPH2581' => 'OnePlus 12R',
		'V2227A' => 'vivo X90',
		'V2307A' => 'vivo X100',
		// 小米：Build.MODEL 剥前缀后常只剩代号
		'2304FPN6DC' => 'Xiaomi 13',
		'2210132C' => 'Xiaomi 13 Pro',
		'23127PN0CC' => 'Xiaomi 14',
		// 华为
		'ELS-NX9' => 'Huawei P40 Pro',
		'LIO-AL00' => 'Huawei Mate 30 Pro',
		'ANA-AL00' => 'Huawei P40'
	];

	/**
	 * 把 iOS 机型号解析成机型名，查不到返回 `null`。
	 *
	 * 返回 `null` 而不是编一个名字：调用方据此决定"要不要显示机型段"，
	 * 未知机型显示机型号本身比显示一个猜的名字有用。
	 */
	public static function resolveIOS(machineId:String):String
	{
		if (machineId == null) return null;

		var id = StringTools.trim(machineId);
		if (id == '') return null;

		// 大小写不敏感：hw.machine 实测都是规范大小写，但模拟器 / 某些越狱环境会小写
		var hit = IOS_MAP.get(id);
		if (hit == null) hit = IOS_MAP.get(id.toLowerCase());

		return hit;
	}

	/**
	 * Android 型号名归一化。查不到原样返回（非空时才返回）。
	 */
	public static function resolveAndroid(model:String):String
	{
		if (model == null) return null;

		var name = StringTools.trim(model);
		if (name == '') return null;

		var hit = ANDROID_ALIAS.get(name);
		if (hit == null) hit = ANDROID_ALIAS.get(name.toUpperCase());

		return hit != null ? hit : name;
	}

	/**
	 * 机型名过长时截断。
	 *
	 * 机型名和 `OS:` / `Render:` 拼在同一行，14px `vcr.ttf` 下超长名会顶出屏幕右侧。
	 */
	public static function shorten(name:String):String
	{
		if (name == null) return null;
		if (name.length <= MAX_LENGTH) return name;

		return name.substr(0, MAX_LENGTH - ELLIPSIS.length) + ELLIPSIS;
	}
}
