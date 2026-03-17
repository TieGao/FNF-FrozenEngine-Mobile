@echo off
cd ..

haxelib git hxcpp https://github.com/HaxeFoundation/hxcpp.git --quiet

for /f "tokens=*" %%i in ('haxelib path hxcpp') do set HXCPP_PATH=%%i
set HXCPP_PATH=%HXCPP_PATH::=%

cd %HXCPP_PATH%\tools\run
haxe compile.hxml

cd %HXCPP_PATH%\tools\hxcpp
haxe compile.hxml

cd %HXCPP_PATH%\project
haxe compile-cppia.hxml

cd %~dp0\..

haxelib git lime https://github.com/kittycathy233/lime --quiet
haxelib install openfl 9.5.0 --quiet
haxelib install flixel 6.1.0 --quiet
haxelib install flixel-addons 4.0.1 --quiet
haxelib install flixel-tools 1.5.1 --quiet
haxelib install hscript-iris 1.1.3 --quiet
haxelib install tjson 1.4.0 --quiet
haxelib git flxanimate https://github.com/Dot-Stuff/flxanimate 768740a56b26aa0c072720e0d1236b94afe68e3e --quiet
haxelib git linc_luajit https://github.com/kittycathy233/linc_luajit --quiet
haxelib install hxdiscord_rpc 1.2.4 --quiet --skip-dependencies
haxelib install hxvlc 2.2.5 --quiet --skip-dependencies
haxelib install moonchart 0.5.1 --quiet
haxelib git funkin.vis https://github.com/FunkinCrew/funkVis 22b1ce089dd924f15cdc4632397ef3504d464e90 --quiet --skip-dependencies
haxelib git grig.audio https://gitlab.com/haxe-grig/grig.audio.git cbf91e2180fd2e374924fe74844086aab7891666 --quiet

echo Finished!
pause