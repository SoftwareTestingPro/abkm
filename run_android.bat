@echo off
echo Launching Android Emulator (Phone)...
cd source
call flutter emulators --launch Phone
call flutter clean
echo.
echo Building and Running ABKM on Android...
echo Please wait while the app is being built and installed...
call flutter run
pause
