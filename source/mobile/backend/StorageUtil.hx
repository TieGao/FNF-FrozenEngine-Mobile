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
	// always force path due to haxe
	public static function getExternalStorageDirectory():String
		return '/sdcard/.FrozenEngine/';

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
        if (!FileSystem.exists(StorageUtil.getStorageDirectory()))
            FileSystem.createDirectory(StorageUtil.getStorageDirectory());
    }
    catch (e:Dynamic)
    {
        CoolUtil.showPopUp(Language.getPhrase('create_directory_error', 'Please create directory to\n{1}\nPress OK to close the game', [StorageUtil.getStorageDirectory()]), Language.getPhrase('mobile_error', "Error!"));
        lime.system.System.exit(1);
    }

    try
    {
        if (!FileSystem.exists(StorageUtil.getExternalStorageDirectory() + 'mods'))
            FileSystem.createDirectory(StorageUtil.getExternalStorageDirectory() + 'mods');
    }
    catch (e:Dynamic)
    {
        CoolUtil.showPopUp(Language.getPhrase('create_directory_error', 'Please create directory to\n{1}\nPress OK to close the game', [StorageUtil.getExternalStorageDirectory()]), Language.getPhrase('mobile_error', "Error!"));
        lime.system.System.exit(1);
    }
}
	#end
	#end
}
