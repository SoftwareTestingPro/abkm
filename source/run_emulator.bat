@echo off
set SDK_PATH=C:\Users\sushi\AppData\Local\Android\Sdk
set EMULATOR_EXE=%SDK_PATH%\emulator\emulator.exe
set ADB_EXE=%SDK_PATH%\platform-tools\adb.exe

echo Checking for running emulators/devices...
"%ADB_EXE%" get-state >nul 2>&1
if "%ERRORLEVEL%"=="0" (
    echo Device already connected. Skipping emulator startup.
    goto boot_finished
)

echo Starting emulator: Phone...
start "" "%EMULATOR_EXE%" -avd Phone

echo Waiting for emulator to be ready (ADB connection)...
"%ADB_EXE%" wait-for-device

echo Waiting for Android System to finish booting...
:wait_boot
for /f "tokens=*" %%i in ('"%ADB_EXE%" shell getprop sys.boot_completed 2^>nul') do set BOOT_STATUS=%%i
if "%BOOT_STATUS%"=="1" (
    echo System Boot Completed!
    goto boot_finished
)
timeout /t 2 /nobreak >nul
goto wait_boot

:boot_finished
echo Unlocking screen...
"%ADB_EXE%" shell input keyevent 82

echo Building APK...
call flutter build apk --debug

echo Installing APK...
"%ADB_EXE%" install -r build\app\outputs\flutter-apk\app-debug.apk

echo Launching App...
"%ADB_EXE%" shell monkey -p com.intellicast.abkm -c android.intent.category.LAUNCHER 1

echo Done!
pause
