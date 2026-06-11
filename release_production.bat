@echo off
setlocal

echo ============================================================
echo   MAHASABHA - PRODUCTION RELEASE TOOL
echo ============================================================
echo.

:: 1. Setup
echo [STEP 1/3] Cleaning and Stopping background processes...
cd source
:: Kill any stuck gradle processes to prevent file locks
if exist "android\gradlew.bat" (
    echo Stopping Gradle daemons...
    call android\gradlew.bat --stop
)
:: Force kill any stuck Java processes that might be locking the build folder
taskkill /F /IM java.exe /T 2>nul
call flutter clean
call flutter pub get
if %ERRORLEVEL% NEQ 0 goto :error
cd ..

:: 2. Web Build and Deploy to Root
echo.
echo [STEP 2/3] Generating Cache-Busting Build ID and Building Flutter Web (Production)...

:: Generate a unique build ID based on current date and time
set BUILD_ID=%date:/=-%_%time::=-%
set BUILD_ID=%BUILD_ID: =_%
echo %BUILD_ID% > source\web\build_id.txt
echo %BUILD_ID% > source\assets\images\build_id.txt

cd source
call flutter build web --base-href "/abkm/" --release
if %ERRORLEVEL% NEQ 0 goto :error
cd ..

echo Copying web files to root for GitHub Pages...
xcopy /E /I /Y "source\build\web\*" ".\"

:: 3. Android Build (AAB and APK)
echo.
echo [STEP 3/3] Building Android Assets (AAB and Split APKs)...
cd source
echo Generating App Bundle (Preferred)...
call flutter build appbundle --release
echo.
echo Generating Split APKs (32-bit and 64-bit)...
call flutter build apk --release --split-per-abi
if %ERRORLEVEL% NEQ 0 goto :error
cd ..

echo.
echo ============================================================
echo   PRODUCTION BUILD COMPLETE!
echo ============================================================
echo.
echo WEB: Ready for commit/push. 
echo URL: https://Intellicast.github.io/abkm/
echo.
echo ANDROID: Files are located at:
echo AAB: source\build\app\outputs\bundle\release\app-release.aab
echo APKs: source\build\app\outputs\flutter-apk\
echo (Use 'app-armeabi-v7a-release.apk' for 32-bit and 'app-arm64-v8a-release.apk' for 64-bit)
echo.
echo ============================================================
pause
exit /b 0

:error
echo.
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
echo   ERROR: The process failed. Please check the logs above.
echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
pause
exit /b 1

