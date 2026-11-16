# Sets up a Flutter + Android build toolchain on a Windows ARM64 box (SAE) under C:\kiraya-build.
# Runs unattended (SYSTEM scheduled task); progress in C:\kiraya-build\setup.log
$ErrorActionPreference = 'Stop'
$root = 'C:\kiraya-build'; New-Item -ItemType Directory -Force $root | Out-Null
$log = "$root\setup.log"
function Log($m) { "$(Get-Date -f 'HH:mm:ss') $m" | Add-Content $log }
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$ProgressPreference = 'SilentlyContinue'
function Fetch($url, $out) { Log "GET $url"; Invoke-WebRequest $url -OutFile $out -UseBasicParsing }
try {
  Log 'start'
  # 1. JDK 17 (arm64)
  if (-not (Test-Path "$root\jdk\bin\java.exe")) {
    Fetch 'https://aka.ms/download-jdk/microsoft-jdk-17-windows-aarch64.zip' "$root\jdk.zip"
    Expand-Archive "$root\jdk.zip" "$root\jdk-tmp" -Force
    Move-Item (Get-ChildItem "$root\jdk-tmp" -Directory)[0].FullName "$root\jdk"; Remove-Item "$root\jdk-tmp", "$root\jdk.zip" -Recurse -Force
  }
  Log 'jdk ok'
  # 2. MinGit (flutter needs git)
  if (-not (Test-Path "$root\git\cmd\git.exe")) {
    $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{ 'User-Agent' = 'kiraya' }
    $asset = $rel.assets | Where-Object { $_.name -match '^MinGit-[\d.]+-arm64\.zip$' } | Select-Object -First 1
    if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -match '^MinGit-[\d.]+-64-bit\.zip$' } | Select-Object -First 1 }
    Fetch $asset.browser_download_url "$root\git.zip"
    Expand-Archive "$root\git.zip" "$root\git" -Force; Remove-Item "$root\git.zip"
  }
  $env:Path = "$root\git\cmd;$root\jdk\bin;$env:Path"; $env:JAVA_HOME = "$root\jdk"
  # Native tools write progress to stderr; don't treat that as a failure from here on.
  $ErrorActionPreference = 'Continue'
  git config --system --add safe.directory '*' 2>$null
  Log 'git ok'
  # 3. Flutter stable
  if (-not (Test-Path "$root\flutter\bin\flutter.bat")) {
    if (Test-Path "$root\flutter") { Remove-Item "$root\flutter" -Recurse -Force }
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$root\flutter" 2>&1 | Out-Null
    if (-not (Test-Path "$root\flutter\bin\flutter.bat")) { throw 'flutter clone failed' }
  }
  $env:Path = "$root\flutter\bin;$env:Path"
  & flutter --disable-analytics 2>&1 | Out-Null
  & flutter --version 2>&1 | Add-Content $log
  Log 'flutter ok'
  # 4. Android SDK
  $sdk = "$root\android-sdk"; $env:ANDROID_HOME = $sdk
  if (-not (Test-Path "$sdk\cmdline-tools\latest\bin\sdkmanager.bat")) {
    Fetch 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip' "$root\clt.zip"
    Expand-Archive "$root\clt.zip" "$root\clt" -Force
    New-Item -ItemType Directory -Force "$sdk\cmdline-tools" | Out-Null
    Move-Item "$root\clt\cmdline-tools" "$sdk\cmdline-tools\latest"; Remove-Item "$root\clt", "$root\clt.zip" -Recurse -Force
  }
  $yes = ('y' + [Environment]::NewLine) * 30
  $yes | & "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" --licenses 2>&1 | Out-Null
  & "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'build-tools;28.0.3' 2>&1 | Select-Object -Last 3 | Add-Content $log
  & flutter config --android-sdk $sdk 2>&1 | Out-Null
  & flutter doctor 2>&1 | Add-Content $log
  Log 'DONE'
} catch {
  Log "FAILED: $($_.Exception.Message)"
}
