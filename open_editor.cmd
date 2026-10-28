@echo off
setlocal
set "GODOT_EDITOR=%USERPROFILE%\Tools\Godot\4.7.2-voxel1.7\godot.windows.editor.x86_64.exe"
if defined GODOT set "GODOT_EDITOR=%GODOT%"

if not exist "%GODOT_EDITOR%" (
    echo Editor custom com Voxel Tools nao encontrado:
    echo "%GODOT_EDITOR%"
    echo Defina GODOT com o caminho do editor custom, conforme o README.
    pause
    exit /b 1
)

"%GODOT_EDITOR%" --headless --path "%~dp0." --script res://tools/check_env.gd
if errorlevel 1 (
    echo O editor selecionado nao atende aos requisitos do projeto.
    echo Use Godot 4.7.2 custom com Voxel Tools 1.7. Consulte o README.
    pause
    exit /b 1
)

start "" /normal "%GODOT_EDITOR%" --editor --path "%~dp0."
exit /b 0
