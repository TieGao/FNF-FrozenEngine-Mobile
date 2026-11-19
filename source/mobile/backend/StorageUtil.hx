/*
 * Copyright (C) 2025 Mobile Porting Team
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package mobile.backend;

/**
 * A storage class for mobile.
 * @author Karim Akra and Homura Akemi (HomuHomu833)
 */
class StorageUtil
{
	#if sys
	/**
	 * 数据根目录（= 游戏 CWD）：assets / content / mods 等资源树所在，与桌面运行目录同构。
	 * android 为公共外部存储 /sdcard/.FrozenEngine/（用户可管理、卸载不丢）；
	 * iOS 为 documents/FrozenEngine/；其余平台维持进程 CWD。
	 */
	public static function getStorageDirectory():String
		return #if android getExternalStorageDirectory() #elseif ios haxe.io.Path.addTrailingSlash(lime.system.System.documentsDirectory) + 'FrozenEngine/' #else Sys.getCwd() #end;

	/**
	 * 应用私有目录：不希望被用户改动/随包管理的数据放这里（如 Replay）。
	 * android 为 /sdcard/Android/data/<包名>/files/；iOS 为沙盒 applicationStorageDirectory。
	 */
	public static function getPrivateStorageDirectory():String
		return #if android haxe.io.Path.addTrailingSlash(extension.androidtools.content.Context.getExternalFilesDir()) #elseif ios lime.system.System.applicationStorageDirectory #else Sys.getCwd() #end;

	/** 确保数据根存在（Main 在 setCwd 前调用）。 */
	public static function ensureDataRoot():Void
	{
		#if ios
		try
		{
			if (!FileSystem.exists(getStorageDirectory()))
				FileSystem.createDirectory(getStorageDirectory());
		}
		catch (e:Dynamic) {}
		#end
	}

	/**
	 * 逐层创建目录。
	 * FileSystem.createDirectory 只建最后一层，父目录缺失时 mkdir 返回 ENOENT 并抛异常；
	 * 复制资产时目录是边遍历边建的，不能假设父目录已经存在。
	 */
	public static function mkDirs(directory:String):Void
	{
		if (directory == null || directory.length == 0) return;

		var total:String = '';
		if (directory.substr(0, 1) == '/') total = '/';

		var parts:Array<String> = directory.split('/');
		if (parts.length > 0 && parts[0].indexOf(':') > -1) parts.shift();

		for (part in parts)
		{
			if (part == '.' || part == '') continue;
			if (total != '' && total != '/') total += '/';
			total += part;
			try
			{
				if (!FileSystem.exists(total))
					FileSystem.createDirectory(total);
			}
			catch (e:Dynamic) trace('[StorageUtil] mkDirs failed at $total: $e');
		}
	}

	public static function saveContent(fileName:String, fileData:String, ?alert:Bool = true):Void
	{
		final folder:String = getStorageDirectory() + 'saves/';
		try
		{
			if (!FileSystem.exists(folder))
				FileSystem.createDirectory(folder);

			File.saveContent('$folder/$fileName', fileData);
			if (alert)
				CoolUtil.showPopUp(Language.getPhrase('file_save_success', '{1} has been saved.', [fileName]), Language.getPhrase('mobile_success', "Success!"));
		}
		catch (e:Dynamic)
			if (alert)
				CoolUtil.showPopUp(Language.getPhrase('file_save_fail', '{1} couldn\'t be saved.\n({2})', [fileName, e.message]), Language.getPhrase('mobile_error', "Error!"));
			else
				trace('$fileName couldn\'t be saved. (${e.message})');
	}

	#if android
	/**
	 * 数据根的真实路径。
	 * 必须走 JNI 取 /storage/emulated/0，不能硬编码 /sdcard —— 那是个符号链接，
	 * 部分 ROM 上第三方 app 通过它 mkdir 会失败（表现就是首启弹「请创建目录」直接退出）。
	 * JNI 取不到时才退回 /sdcard。
	 */
	public static function getExternalStorageDirectory():String
	{
		var base:String = '';
		try base = extension.androidtools.os.Environment.getExternalStorageDirectory() catch (e:Dynamic) {}
		if (base == null || base.length == 0) base = '/sdcard';
		return haxe.io.Path.addTrailingSlash(base) + '.FrozenEngine/';
	}

	public static function requestPermissions():Void
{
    if (extension.androidtools.os.Build.VERSION.SDK_INT >= extension.androidtools.os.Build.VERSION_CODES.TIRAMISU)
    {
        // Request each permission individually
        extension.androidtools.Permissions.requestPermissions(['READ_MEDIA_IMAGES','READ_MEDIA_VISUAL_USER_SELECTED','READ_MEDIA_VIDEO','READ_MEDIA_AUDIO']);
    }
    else
    {
        // Request each permission individually
        extension.androidtools.Permissions.requestPermissions(['READ_EXTERNAL_STORAGE','WRITE_EXTERNAL_STORAGE']);
    }

    if (!extension.androidtools.os.Environment.isExternalStorageManager())
        extension.androidtools.Settings.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');

    // 移除了权限检查的 if 语句块

    try
    {
        // 去掉尾部斜杠再 mkdir：FUSE 上带斜杠的路径个别 ROM 会拒绝
        var root:String = StorageUtil.getStorageDirectory();
        if (root.endsWith('/')) root = root.substr(0, root.length - 1);
        if (!FileSystem.exists(root))
            FileSystem.createDirectory(root);
    }
    catch (e:Dynamic)
    {
        // requestSetting 只是异步跳转到设置页，不会等玩家授权，紧接着的 createDirectory 必然失败。
        // 这时提示「请手动创建文件夹」是误导 —— 真正缺的是「所有文件访问权限」，必须把人送回设置页。
        if (!extension.androidtools.os.Environment.isExternalStorageManager())
        {
            extension.androidtools.Settings.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
            CoolUtil.showPopUp(
                Language.getPhrase('storage_permission_required',
                    'Frozen Engine needs "All files access" to create\n{1}\n\nTurn it on in the settings page that just opened, then reopen the game.',
                    [StorageUtil.getStorageDirectory()]),
                Language.getPhrase('mobile_error', "Error!"));
        }
        else
        {
            CoolUtil.showPopUp(Language.getPhrase('create_directory_error', 'Please create directory to\n{1}\nPress OK to close the game', [StorageUtil.getStorageDirectory()]), Language.getPhrase('mobile_error', "Error!"));
        }
        lime.system.System.exit(1);
    }

    try
    {
        if (!FileSystem.exists(StorageUtil.getExternalStorageDirectory() + 'mods'))
            FileSystem.createDirectory(StorageUtil.getExternalStorageDirectory() + 'mods');
    }
    catch (e:Dynamic)
    {
        // mods 目录建不出来不该让整个游戏退出：没有 mod 也能正常玩
        trace('[StorageUtil] create mods dir failed: $e');
    }
}
	#end
	#end
}
