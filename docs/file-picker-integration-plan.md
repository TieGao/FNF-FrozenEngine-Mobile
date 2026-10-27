# 移动端文件选择器接入方案（extension-document-picker）

> 2026-10-28 起草。目标：让移动端（Android/iOS）能调系统文件选择器「打开一个文件」，
> 打通谱面编辑器的 Import Chart 流程，并为其它需要"选文件"的功能（Open Chart JSON、
> Open Events、将来 mods 导入等）提供统一入口。

---

## 0. 背景与现状

- **桌面**：`FileDialogHandler`（`states/editors/content/FileDialogHandler.hx`）包的是
  openfl `FileReference` → lime `FileDialog`，desktop 原生对话框齐全。
- **移动**：lime 8.4.0 的 FileDialog browse/open/save 只在 `#if (desktop && sys)` 编实现，
  Android/iOS 直接 `onCancel.dispatch(); return false`。因此 `browseEx()` 在移动端走到
  `return false`（无操作），所有依赖 fileDialog 的编辑器按钮当前都套着 `#if !mobile`。
- **移动端现有的替代路径**：`ChartSourceSelectSubstate`（选 content/mods 内置谱面）+
  `StorageUtil.saveContent`（直写 `/sdcard/.FrozenEngine/`）——本方案不取代它们，只补
  "用户从任意位置挑一个文件"这块空缺。
- **选型结论**（2026-10-27 调研）：flixel/lime/extension-androidtools 均无文件选择器；
  haxelib 上的 AndroidDialogs、extension-nativedialog 等只有消息框。采用
  **ngrebenshikov/extension-document-picker**（MIT，~300 行，Android+iOS 双端，已克隆）。

## 1. 库的工作原理（读源码确认）

两端哲学一致：**系统选择器选完 → 把文件拷进 App 可控目录 → 回调一个普通文件路径**。
Haxe 侧拿到的不是 content:// 或安全作用域 URL，而是直接可以 `File.getContent` 的路径，
所以 `FileDialogHandler.onLoadComplete` 现有的 `File.getContent(path)` 逻辑原样可用。

| | Android | iOS |
|---|---|---|
| 通道 | JNI（`org.haxe.extension.DocumentPickerExtension.pick`） | CFFI 静态 ndll（`extension_document_picker_pick`） |
| 选择器 | `Intent.ACTION_GET_CONTENT`，`type="*/*"` | `UIDocumentPickerViewController`，`UIDocumentPickerModeImport` |
| 拷贝 | `FileUtils.saveUriToCacheFile` → App 缓存目录 | Import 模式由系统拷进沙盒 tmp/Inbox |
| 回调 | 缓存文件路径 | `urls[0].path`；**取消时回调 null** |
| types 参数 | **被忽略**（不过滤扩展名） | 生效，但收的是 **UTI**（`public.json` 等），不是 `*.json` |

## 2. 库的接入现状（已完成）

- 已按本机 git-pin 惯例装进 E 盘 haxelib 仓库：
  `E:/HaxeToolkit/haxe/lib/extension-document-picker/git/`（`.current` = `git`），
  `haxelib list` 显示 `extension-document-picker: [git]`，`haxelib path` 解析正常。
- 克隆来源 `D:\libresearch\extension-document-picker`（调研工作副本，可删）。

## 3. 实施步骤

### Step 1 — 给扩展打补丁（在其 git 目录内改，commit 到本地分支）

1. **iOS keyWindow 适配（必改）**：`DocumentPicker.mm` 里
   `[[UIApplication sharedApplication] keyWindow]` 在 iOS 13+ scene 时代可能返回 nil，
   弹窗会静默不出来。改为遍历 connectedScenes 取 foreground active 的 window：
   ```objc
   UIWindow *window = nil;
   for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
       if (scene.activationState != UISceneActivationStateForegroundActive) continue;
       if ([scene isKindOfClass:[UIWindowScene class]])
           for (UIWindow *w in ((UIWindowScene *)scene).windows)
               if (w.isKeyWindow) { window = w; break; }
   }
   if (window == nil) window = [UIApplication sharedApplication].keyWindow; // 老系统兜底
   ```
   然后 `window.rootViewController presentViewController:...`。
2. **delegate 保活（建议改）**：`UIDocumentPickerViewController.delegate` 是 weak，
   现在靠永不 release 泄漏保活。加一个 `static StrongRef`（或 `static DocumentPickerDelegate *currentDelegate`）持有。
3. **（可选）iOS 14+ 新 API 分支**：`initWithDocumentTypes:inMode:` 已弃用但仍可用；
   若最低部署目标 ≥ iOS 14 可换 `initForOpeningContentTypes:asCopy:YES`，否则保留旧 API 即可（能编能用）。
4. **（可选）Android 过滤**：`ACTION_GET_CONTENT` 加 `CATEGORY_OPENABLE`；types 无法
   映射成 sm/qua 这类私有扩展的 MIME，保持 `*/*` 由 FE 侧校验后缀即可，不强求。

补丁落点建议：与 lime/openfl/hxcpp 同惯例，把带补丁的克隆推到
`github.com/TieGao/extension-document-picker`，setup 脚本 `haxelib git` 指向该 fork；
本地开发期直接改 E 盘 git 目录即可（本仓库 CI 用 `.haxelib/` 钉包时同样收录 fork）。

### Step 2 — 移动版仓库接线

- `Project.xml`：
  ```xml
  <haxelib name="extension-document-picker" if="mobile" />
  ```
- `setup/windows.bat` 与 `setup/unix.sh`：追加
  `haxelib git extension-document-picker https://github.com/TieGao/extension-document-picker <branch>`
  （fork 建好后；未建好前本地开发不写进 setup，只靠 E 盘已装状态）。

### Step 3 — FileDialogHandler 增加 mobile 分支（核心）

`browseEx()` 的 mobile 分支（现为一行 `return false`）替换为：

1. **扩展名 → UTI 映射**（iOS 用；Android 忽略）：
   ```haxe
   static function utiFromFilter(filter:Array<FileFilter>):Array<String>
   {
       var out:Array<String> = [];
       // json→public.json；ogg/mp3/wav→public.audio；zip(osz/qp)→com.pkware.zip-archive；
       // 其余（sm/ssc/osu/qua/mid/mc 等）与兜底→public.data
       ...
       if (out.length == 0) out.push('public.data');
       return out;
   }
   ```
2. **选文件**：
   ```haxe
   #if mobile
   extension.documentpicker.DocumentPicker.pick(utiFromFilter(typeFilter), function(p:String)
   {
       if (p == null) { openFileDialog_onCancel(); return; }   // 取消 → 走原 onCancel 链
       __path = p;
       dispatchEvent(new Event(Event.SELECT));                  // 与 desktop 分支同一出口
   });
   return true;
   #end
   ```
   `onLoadComplete` 已有 `path = __path; data = File.getContent(path)` —— 无需再动。
   注意：回调发生在平台主线程，与 desktop 的 FileDialog 线程池回调不同，但最终都
   回到 Haxe 主逻辑，事件流一致。
3. **顺手修一个现存 bug**：`onCancelFn` 里 `if(onCancel != null) onError();` 应为
   `onCancel()`——移动端取消会走错回调，接入前必须修，否则"点了取消"报错误提示。
4. `save()` / `openDirectory()` 移动端**不动**：save 继续由调用方（ChartingState 的
   `#if mobile StorageUtil.saveContent` 分支）处理；目录选择 ACTION_OPEN_DOCUMENT_TREE
   本库未实现，暂无需求。

### Step 4 — 放开编辑器入口（ChartingState）

- **放开**（依赖 `open()`，mobile 分支生效后即可用）：
  - `Import Chart...`（.sm/.ssc/.osu/.osz/.qua/.qp/.mid/.mc → ChartConvertCore 全流程）
  - `Open Chart...`（Psych JSON）、`Open Events...`、`Open Autosave...`（如需要）
- **保持 desktop-only**：
  - `Export Chart...` / 各类 Save-as：save 方向没有系统选择器，移动端继续走 StorageUtil。
  - 注意 **ACTION_SAVE（导入后另存 JSON）在移动端的落盘位置**：picked 文件在 App
    缓存（Android `Android/data/<包>/cache`、iOS tmp/Inbox），`File.saveContent` 写同目录
    技术上没问题，但用户在文件管理器里不容易找到。移动端建议把 ACTION_SAVE 的
    输出目录改到 `StorageUtil.getExternalStorageDirectory()`（`/sdcard/.FrozenEngine/`），
    一行路径替换，在本步骤一并处理。
- `openOszAudio` 的 `File.copy` 目标同理跟随 ACTION_SAVE 输出目录。

### Step 5 — 验证矩阵

| 项 | Android（Windows 本地可验） | iOS（只能 CI/真机） |
|---|---|---|
| 编译 | `haxe release.hxml --no-output` + `lime build android -release` | CI `Make IPA`（cache-build.yml 已有 mac runner 步骤）——ObjC/.mm 在此首次编译 |
| 取消 | 回调 null → onCancel | 同左 |
| 选 .sm/.osu/.osz | 缓存拷贝 → 导入流程全通（含 .osz 音频提取） | Files App / iCloud Drive 选文件 |
| 大文件（50MB 音频） | 拷贝耗时在主线程 Intent 回调后，可接受；观察 | 同左 |
| 微信/QQ 下载目录 | GET_CONTENT 走系统文档 UI，可跨应用选 | — |
| 重复打开 | completed 状态机已有互斥 | 同左 |

### Step 6 — 风险与回滚

- **Android 11+ 无影响**：GET_CONTENT 走系统文档 UI，不受包可见性限制。
- **iOS tmp 清理**：Import 拷贝的文件被系统清掉前必须完成读取（现有流程同步读完，无风险）。
- **回滚**：摘掉 Project.xml 的 haxelib 行 + `#if mobile` 分支即可，桌面路径零影响；
  已放开的按钮回套 `#if !mobile`。

## 4. 工作量估计

- Step 1 补丁：0.5h（iOS 部分本机无法编译验证，靠 CI）
- Step 2 接线：0.5h（fork 建好后）
- Step 3 包装层：1–2h（含 UTI 映射与取消链路）
- Step 4 入口放开 + 落盘调整：1h
- Step 5 验证：Android 1h；iOS 依赖 CI/真机排期

## 5. 决策记录

- 2026-10-27 调研选定 extension-document-picker（唯一双端现成方案；flixel/lime/
  androidtools/haxelib 系均无 SAF/文档选择器）。
- 2026-10-28 纳入 E 盘 haxelib 仓库（git-pin 惯例）。未打补丁、未接 Project.xml——
  按 Step 1→3 顺序实施。
