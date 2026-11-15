# 生成一个属于你自己的 release 签名，并写好 app\android\key.properties。
# 已经存在 keys\release.jks 时不会覆盖——那个文件丢了，已发布的包就再也升不了级。
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$ks = 'keys\release.jks'
$props = 'app\android\key.properties'

if (Test-Path $ks) {
    Write-Host "已存在 $ks，跳过生成。"
    exit 0
}

$keytool = (Get-Command keytool -ErrorAction SilentlyContinue)
if (-not $keytool) {
    $guess = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    if ($env:JAVA_HOME -and (Test-Path $guess)) { $keytool = $guess }
    else { throw '找不到 keytool。装一个 JDK 17，或者把 %JAVA_HOME%\bin 加进 PATH。' }
}

New-Item -ItemType Directory -Force -Path 'keys' | Out-Null
$pw = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })

& $keytool -genkeypair -v `
    -keystore $ks -storetype JKS `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -alias shisheng -storepass $pw -keypass $pw `
    -dname "CN=Shisheng, OU=Shisheng, O=Shisheng, L=Beijing, ST=Beijing, C=CN"
if ($LASTEXITCODE -ne 0) { throw "keytool 失败（退出码 $LASTEXITCODE）" }

@"
storePassword=$pw
keyPassword=$pw
keyAlias=shisheng
storeFile=../../keys/release.jks
"@ | Set-Content -Encoding ASCII $props

Write-Host ""
Write-Host "已生成 $ks 与 $props。"
Write-Host "把这两个文件单独备份：丢了它，同一包名的 APK 就再也发不了升级。"
