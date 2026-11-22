@echo off
color 0a
cd ..
@echo on
echo Installing dependencies...
echo This might take a few moments depending on your internet speed.
REM 每行都带 || exit /b 1：haxelib 装挂了必须立刻停。半装的库（典型是 luahscript
REM 只剩一个空目录）在后面的编译里表现为 Type not found，CI 还会把这份坏状态存进
REM 缓存、之后每轮都命中它。对齐主版 windows.bat，多了 extension-androidtools /
REM extension-document-picker 两个移动端库；flxanimate / linc_luajit 必须带
REM --skip-dependencies，否则它们的依赖解析会把 release 版 hxcpp 4.3.2 拽下来
REM 覆盖 git 版，装一半 std@sys_file_type 崩掉（2026-11-04 CI 实录）。
haxelib git flixel https://github.com/TieGao/flixel --skip-dependencies || exit /b 1
haxelib git flixel-addons https://github.com/TieGao/flixel-addons --skip-dependencies || exit /b 1
haxelib install flixel-tools 1.5.1 --skip-dependencies || exit /b 1
REM hscript-iris-nmv = NMV 方言 fork（pisayesiwsi/hscript-iris @ 62d828b，未发布到 haxelib），
REM 官方 1.1.3 解析不了脚本层的 EFor/CString 自定义语法节点，只能 git 别名安装。
REM 这两行只属于 NMV-Features 分支（main 的 Project.xml 用官方 hscript-iris），勿并回 main。
haxelib git hscript-iris-nmv https://github.com/pisayesiwsi/hscript-iris 62d828b --skip-dependencies --always || exit /b 1
rem tjson 已 vendor 进 source/tjson/（BSD，原库停更），不再走 haxelib（2026-11-13 对齐主版）
haxelib install hxdiscord_rpc 1.2.4 --skip-dependencies || exit /b 1
haxelib git hxvlc https://github.com/IceTheAxe/hxvlc --skip-dependencies --always || exit /b 1
haxelib install extension-androidtools 2.2.2 --skip-dependencies || exit /b 1
haxelib git extension-document-picker https://github.com/TieGao/extension-document-picker fe-patches --skip-dependencies || exit /b 1
haxelib git lime https://github.com/IceTheAxe/lime haxelib --always || exit /b 1
haxelib git openfl https://github.com/TieGao/openfl --skip-dependencies --always || exit /b 1
haxelib git moonchart https://github.com/MaybeMaru/moonchart.git --skip-dependencies || exit /b 1
haxelib install format --skip-dependencies || exit /b 1
haxelib install hxp --skip-dependencies || exit /b 1
haxelib git hxcpp https://github.com/TieGao/hxcpp.git || exit /b 1
haxelib git flxanimate https://github.com/Dot-Stuff/flxanimate 0188d47c982913eb10fad7bd75f062ddfc680f4b --always --skip-dependencies || exit /b 1
haxelib git linc_luajit https://github.com/TieGao/linc_luajit_largs 82388eb8d9eb084d91da6ff63de44426c4df0a6e --always --skip-dependencies || exit /b 1
haxelib git luahscript https://github.com/VapireMox/luahscript 122acb150ba5a55d02b138c2530fa5619fb06c3a --always || exit /b 1
haxelib git funkin.vis https://github.com/FunkinCrew/funkVis 22b1ce089dd924f15cdc4632397ef3504d464e90 --always || exit /b 1
haxelib git grig.audio https://gitlab.com/haxe-grig/grig.audio.git cbf91e2180fd2e374924fe74844086aab7891666 --always || exit /b 1
haxelib set hxcpp git || exit /b 1
REM NMV blend 语义需要 flxanimate 库补丁（blendNoBake + 绘制树实时混合 + 遮罩贴回混合，
REM 见 setup/flxanimate-nmv-blend.patch）。Dot-Stuff 上游没有 blendNoBake，该改动此前只
REM 存在于本地 E 仓检出的未提交状态，CI 干净检出编译必炸（PsychFlxAnimate.hx
REM blendNoBake，11-22 实录）。双门控：source/nmv 存在（main 无消费端，勿同步回 main）
REM + HAXELIB_REPO 设置（本地 E 仓补丁已在位，--check 失败即跳过）。
if exist source\nmv if defined HAXELIB_REPO if exist "%HAXELIB_REPO%\flxanimate\git" (
  pushd "%HAXELIB_REPO%\flxanimate\git"
  git apply --check ..\..\..\setup\flxanimate-nmv-blend.patch
  if not errorlevel 1 git apply ..\..\..\setup\flxanimate-nmv-blend.patch && echo flxanimate nmv-blend patch: applied
  popd
)
echo Finished!
pause
