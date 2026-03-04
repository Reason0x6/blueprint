@echo off

rem This package is a build script, see build.odin for more
echo Validating sprite meta opaque-foot fields...
powershell -ExecutionPolicy Bypass -File ".\asset_workbench\ensure_sprite_meta_opaque.ps1"
if errorlevel 1 (
  echo Meta validation failed.
  exit /b 1
)

"D:\projects\Odin\odin.exe" run sauce\build -debug -- testarg
