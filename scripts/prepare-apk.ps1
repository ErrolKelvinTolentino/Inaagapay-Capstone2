[CmdletBinding()]
param(
    [string]$ApkPath,
    [string]$DownloadPageUrl = 'https://inaagapay-capstone.vercel.app/download.html'
)

$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path -Parent $PSScriptRoot
$flutterProjectPath = Join-Path $workspacePath 'inaagapay_flutter_v2'
$downloadDirectoryPath = Join-Path $workspacePath 'admin-web/downloads'
$destinationApkPath = Join-Path $downloadDirectoryPath 'inaagapay.apk'

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $downloadPageUri = [Uri]$DownloadPageUrl
    if (-not $downloadPageUri.IsAbsoluteUri -or $downloadPageUri.Scheme -ne 'https' -or $downloadPageUri.UserInfo) {
        throw 'DownloadPageUrl must be a public HTTPS download page URL.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $flutterProjectPath '.env') -PathType Leaf)) {
        throw 'Configure inaagapay_flutter_v2/.env before building the app. See .env.example.'
    }

    Push-Location -LiteralPath $flutterProjectPath
    try {
        & flutter build apk --release "--dart-define=APP_DOWNLOAD_PAGE_URL=$DownloadPageUrl"
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter APK build failed (exit $LASTEXITCODE). The website APK was not replaced."
        }
    } finally {
        Pop-Location
    }
    $ApkPath = Join-Path $flutterProjectPath 'build/app/outputs/flutter-apk/app-release.apk'
}

$sourceApkPath = (Resolve-Path -LiteralPath $ApkPath).Path
if ([IO.Path]::GetExtension($sourceApkPath) -ne '.apk') {
    throw 'ApkPath must point to an Android .apk file.'
}

# Reject an HTML error page or a renamed non-APK file before publishing it.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($sourceApkPath)
try {
    if (-not $archive.GetEntry('AndroidManifest.xml') -or -not $archive.GetEntry('classes.dex')) {
        throw 'The source file is not a valid Android APK.'
    }
} finally {
    $archive.Dispose()
}

New-Item -ItemType Directory -Path $downloadDirectoryPath -Force | Out-Null
if ($sourceApkPath -ne $destinationApkPath) {
    Copy-Item -LiteralPath $sourceApkPath -Destination $destinationApkPath -Force
}

$apkFile = Get-Item -LiteralPath $destinationApkPath
$apkHash = (Get-FileHash -LiteralPath $destinationApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "Website APK: $destinationApkPath"
Write-Output ('Size: {0:N1} MB' -f ($apkFile.Length / 1000000))
Write-Output "SHA-256: $apkHash"
Write-Output 'Deploy the APK together with admin-web to make downloads and QR scans work on other phones.'
