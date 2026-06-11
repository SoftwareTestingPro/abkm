@echo off
setlocal

echo ============================================================
echo   MAHASABHA - WEB RELEASE TOOL
echo ============================================================
echo.

:: 1. Setup
echo [STEP 1/2] Cleaning and fetching dependencies...
cd source
call flutter clean
call flutter pub get
if %ERRORLEVEL% NEQ 0 goto :error
cd ..

:: 2. Web Build and Deploy to Root
echo.
echo [STEP 2/2] Generating Cache-Busting Build ID and Building Flutter Web (Production)...

:: Generate a unique build ID based on current date and time
set BUILD_ID=%date:/=-%_%time::=-%
set BUILD_ID=%BUILD_ID: =_%
echo %BUILD_ID% > source\web\build_id.txt
echo %BUILD_ID% > source\assets\images\build_id.txt

cd source
call flutter build web --base-href "/" --release
if %ERRORLEVEL% NEQ 0 goto :error
cd ..

echo.
echo Copying web files to root for GitHub Pages...
xcopy /E /I /Y "source\build\web\*" ".\"
if %ERRORLEVEL% NEQ 0 goto :error

echo.
echo ============================================================
echo   WEB RELEASE BUILD COMPLETE!
echo ============================================================
echo.
echo WEB: Ready for commit/push. 
echo URL: https://abkm.futurelab.co.in/
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
