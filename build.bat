@echo off
chcp 65001 >nul
echo Building TrayForge...

:: Remove stale spec so fresh one is generated (prevents path resolution errors)
if exist "build\TrayForge.spec" del "build\TrayForge.spec"

set PROJECT_DIR=%CD%
uv run pyinstaller --onefile --windowed --clean --name TrayForge --icon "%PROJECT_DIR%\assets\icon.ico" --runtime-tmpdir "%%LOCALAPPDATA%%\TrayForge\runtime" --specpath build --hidden-import pystray --hidden-import PIL --hidden-import PIL.Image --hidden-import PIL.ImageDraw --hidden-import startup --add-data "%PROJECT_DIR%\assets\icon.ico;assets" src\main.pyw
echo.
if exist "dist\TrayForge.exe" (
    echo Build successful: dist\TrayForge.exe
) else (
    echo Build FAILED - check output above
)
pause
