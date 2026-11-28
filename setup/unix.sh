#!/bin/sh
# SETUP FOR MAC AND LINUX SYSTEMS!!!
# REMINDER THAT YOU NEED HAXE INSTALLED PRIOR TO USING THIS
# https://haxe.org/download
# setup 目录的绝对路径必须在 cd .. 之前抓：之后 $0 的相对路径就指到上一级去了。
# 下面调 apply-flxanimate-nmv-blend.sh 全靠它定位仓库根（旧版补丁块用
# source/nmv + ../../../setup/... 双相对路径，被 `cd ..` 一挪全线失效，补丁在 CI
# 里从未真正打上过 —— 11-22 / 11-28 Android job 两度炸在 blendNoBake）。
SETUP_DIR=$(cd "$(dirname "$0")" && pwd)
cd ..
# CI 里 workflow 已把 haxelib 钉到项目内 .haxelib/（HAXELIB_REPO 注入），这里别再 setup 到
# ~/haxelib 把配置覆盖掉，否则依赖落到家目录、缓存里的 .haxelib/ 是空的。
# 本地开发不设该变量，行为完全不变。
if [ -z "$HAXELIB_REPO" ]; then
  echo Makking the main haxelib and setuping folder in same time..
  mkdir ~/haxelib && haxelib setup ~/haxelib
fi
echo Installing dependencies...
echo This might take a few moments depending on your internet speed.
haxelib install flixel 6.2.0 --skip-dependencies
haxelib install flixel-addons 4.0.1 --skip-dependencies
haxelib install flixel-tools 1.5.1 --skip-dependencies
# hscript-iris-nmv = NMV 方言 fork（pisayesiwsi/hscript-iris @ 62d828b，未发布到 haxelib），
# 官方 1.1.3 解析不了脚本层的 EFor/CString 自定义语法节点，只能 git 别名安装。
# 这两行只属于 NMV-Features 分支（main 的 Project.xml 用官方 hscript-iris），勿并回 main。
haxelib git hscript-iris-nmv https://github.com/pisayesiwsi/hscript-iris 62d828b --skip-dependencies --always
haxelib install tjson 1.4.0 --skip-dependencies
haxelib install hxdiscord_rpc 1.2.4 --skip-dependencies
haxelib git hxvlc https://github.com/IceTheAxe/hxvlc --skip-dependencies
haxelib install extension-androidtools 2.2.2 --skip-dependencies
haxelib git moonchart https://github.com/MaybeMaru/moonchart.git --skip-dependencies
haxelib git extension-document-picker https://github.com/TieGao/extension-document-picker fe-patches --skip-dependencies
haxelib git lime https://github.com/IceTheAxe/lime haxelib --always
haxelib git openfl https://github.com/TieGao/openfl --skip-dependencies --always
haxelib install format --skip-dependencies --always
haxelib install hxp --skip-dependencies --always
haxelib git hxcpp https://github.com/TieGao/hxcpp.git  
haxelib git flxanimate https://github.com/Dot-Stuff/flxanimate 0188d47c982913eb10fad7bd75f062ddfc680f4b --always
haxelib git linc_luajit https://github.com/TieGao/linc_luajit_largs 82388eb8d9eb084d91da6ff63de44426c4df0a6e --always
haxelib git luahscript https://github.com/VapireMox/luahscript 122acb150ba5a55d02b138c2530fa5619fb06c3a --always
haxelib git funkin.vis https://github.com/FunkinCrew/funkVis 22b1ce089dd924f15cdc4632397ef3504d464e90 --always
haxelib git grig.audio https://gitlab.com/haxe-grig/grig.audio.git cbf91e2180fd2e374924fe74844086aab7891666 --always
haxelib set hxcpp git
# NMV blend 语义需要 flxanimate 库补丁（blendNoBake + 绘制树实时混合 + 遮罩贴回混合，
# 见 setup/flxanimate-nmv-blend.patch）。Dot-Stuff 上游没有 blendNoBake（全库 0 命中），
# 该改动此前只存在于本地 E 仓检出的未提交状态——CI 干净检出编译必炸
# （PsychFlxAnimate.hx blendNoBake，11-22 / 11-28 Android job 实录）。
# 具体定位/幂等/门控都在脚本里（库路径先问 $HAXELIB_REPO 再问 haxelib config），
# 这里只负责在 --always 重装完 flxanimate 之后（会覆盖本地改动）重新打一次。
# main 分支脚本自己跳过，行为不变。
sh "$SETUP_DIR/apply-flxanimate-nmv-blend.sh" || exit 1
echo Finished!
