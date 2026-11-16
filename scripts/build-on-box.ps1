# Builds the tenant APK on the SAE build box (run as a SYSTEM scheduled task). Log: C:\kiraya-build\build.log
$root = 'C:\kiraya-build'; $log = "$root\build.log"
$ErrorActionPreference = 'Continue'
Set-Content $log "$(Get-Date -f HH:mm:ss) start"
$env:JAVA_HOME = "$root\jdk"; $env:ANDROID_HOME = "$root\android-sdk"
$env:Path = "$root\flutter\bin;$root\git\cmd;$root\jdk\bin;$env:Path"
$env:PUB_CACHE = "$root\pub-cache"; $env:GRADLE_USER_HOME = "$root\gradle-home"
$src = "$root\src"
if (Test-Path $src) { Remove-Item $src -Recurse -Force }
Expand-Archive "$root\kiraya-src.zip" $src
Set-Location $src
flutter pub get 2>&1 | Select-Object -Last 2 | Add-Content $log
Set-Location "$src\apps\tenant"
flutter build apk --release 2>&1 | Select-Object -Last 15 | Add-Content $log
$apk = "$src\apps\tenant\build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apk) { Copy-Item $apk "$root\kiraya-tenant.apk" -Force; Add-Content $log "$(Get-Date -f HH:mm:ss) DONE" }
else { Add-Content $log "$(Get-Date -f HH:mm:ss) FAILED" }
