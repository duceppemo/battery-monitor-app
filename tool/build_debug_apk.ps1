param(
    [string]$DeviceId
)

$ErrorActionPreference = 'Stop'
$revision = (git rev-parse --short HEAD).Trim()
if (git status --porcelain) {
    $revision = "$revision-dirty"
}

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -eq $flutter) {
    $flutterPath = 'C:\src\flutter\flutter\bin\flutter.bat'
} else {
    $flutterPath = $flutter.Source
}

& $flutterPath build apk --debug "--dart-define=GIT_SHA=$revision"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($DeviceId) {
    $apk = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-debug.apk'
    $adb = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
    & $adb -s $DeviceId install -r $apk
    exit $LASTEXITCODE
}
