param(
    [string]$OutputDirectory = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "Windows packaging must run on Windows."
}
$appRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $appRoot "build/windows-delivery"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$manifestText = Get-Content (Join-Path $appRoot "pubspec.yaml") -Raw
$match = [regex]::Match($manifestText, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $match.Success) { throw "Cannot read the app version from pubspec.yaml." }
$version = $match.Groups[1].Value
$buildNumber = $match.Groups[2].Value

Push-Location $appRoot
try {
    if (-not $SkipBuild) {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "Flutter dependency resolution failed." }
        $defines = @{ MIKANSETA_VERSION = "$version ($buildNumber)" }
        if ($env:SUPABASE_URL -and $env:SUPABASE_ANON_KEY) {
            $defines["SUPABASE_URL"] = $env:SUPABASE_URL
            $defines["SUPABASE_ANON_KEY"] = $env:SUPABASE_ANON_KEY
        }
        $definesFile = Join-Path ([IO.Path]::GetTempPath()) ("mikanseta-defines-" + [guid]::NewGuid() + ".json")
        try {
            [IO.File]::WriteAllText($definesFile, ($defines | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
            & flutter build windows --release "--dart-define-from-file=$definesFile"
            if ($LASTEXITCODE -ne 0) { throw "Flutter Windows Release build failed." }
        } finally {
            if (Test-Path $definesFile) { Remove-Item $definesFile }
        }
    }

    $releaseDirectory = Join-Path $appRoot "build/windows/x64/runner/Release"
    foreach ($required in @("Mikanseta.exe", "flutter_windows.dll", "data/flutter_assets")) {
        if (-not (Test-Path (Join-Path $releaseDirectory $required))) {
            throw "Missing Windows application component: $required"
        }
    }
    New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
    $stage = Join-Path $OutputDirectory ("stage-" + [guid]::NewGuid())
    New-Item -ItemType Directory $stage | Out-Null
    try {
        Copy-Item (Join-Path $releaseDirectory "*") $stage -Recurse
        Get-ChildItem $stage -Filter "*.pdb" -Recurse | Remove-Item

        $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
        if (-not (Test-Path $vswhere)) { throw "Visual Studio C++ tools were not found." }
        $visualStudio = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -ne 0 -or -not $visualStudio) { throw "Visual Studio C++ tools were not found." }
        $redistRoot = Join-Path $visualStudio "VC/Redist/MSVC"
        $crt = Get-ChildItem $redistRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object {
                $x64 = Join-Path $_.FullName "x64"
                if (Test-Path $x64) { Get-ChildItem $x64 -Directory -Filter "Microsoft.VC*.CRT" }
            } | Select-Object -First 1
        if (-not $crt) { throw "The redistributable x64 VC runtime was not found." }
        Copy-Item (Join-Path $crt.FullName "*.dll") $stage
        foreach ($dll in @("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")) {
            if (-not (Test-Path (Join-Path $stage $dll))) { throw "Missing runtime DLL: $dll" }
        }
        Copy-Item (Join-Path $appRoot "packaging/windows/READ-ME.txt") $stage

        $zip = Join-Path $OutputDirectory "Mikanseta-Windows-x64.zip"
        if (Test-Path $zip) { Remove-Item $zip }
        Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal

        $iscc = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
        $compiler = if ($iscc) { $iscc.Source } else {
            Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6/ISCC.exe"
        }
        if (-not (Test-Path $compiler)) {
            throw "Install Inno Setup 6 before creating the Setup installer."
        }
        & $compiler "/DAppVersion=$version" "/DAppBuild=$buildNumber" "/DAppSource=$stage" "/DDeliveryDirectory=$OutputDirectory" (Join-Path $appRoot "packaging/windows/mikanseta.iss")
        if ($LASTEXITCODE -ne 0) { throw "Inno Setup packaging failed." }
        $setup = Join-Path $OutputDirectory "Mikanseta-Windows-x64-Setup.exe"
        if (-not (Test-Path $setup)) { throw "The installer was not created." }
        foreach ($file in @($zip, $setup)) {
            $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()
            [IO.File]::WriteAllText("$file.sha256", "$hash  $([IO.Path]::GetFileName($file))`n", [Text.UTF8Encoding]::new($false))
        }
        $info = @{
            version = $version; buildNumber = [int]$buildNumber
            platform = "windows-x64"; sourceCommit = $env:GITHUB_SHA
            supabaseConfigured = [bool]($env:SUPABASE_URL -and $env:SUPABASE_ANON_KEY)
            codeSigned = $false
        }
        $info | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory "build-info.json") -Encoding utf8
        Write-Host "Windows packages created in $OutputDirectory"
    } finally {
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    }
} finally {
    Pop-Location
}
