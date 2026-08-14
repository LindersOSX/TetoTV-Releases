[CmdletBinding()]
param(
    [switch]$StageBundle,
    [string]$OutputDirectory = "",
    [switch]$RequireResolvedBinaries
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$manifestPath = Join-Path $PSScriptRoot "native_playback_manifest.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()

function Test-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Test-FileText([string]$RelativePath, [string]$Literal) {
    $path = Join-Path $script:repoRoot $RelativePath
    Test-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Missing $RelativePath"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $text = Get-Content -Raw -LiteralPath $path
        Test-Condition $text.Contains($Literal) "$RelativePath does not contain: $Literal"
    }
}

function Test-Hash([string]$Path, [string]$Expected, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $script:failures.Add("Missing $Label at $Path")
        return
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    Test-Condition ($actual -eq $Expected.ToLowerInvariant()) "$Label SHA-256 mismatch: $actual"
}

Test-Condition ($manifest.schemaVersion -eq 1) "Unsupported native manifest schema"
Test-FileText "pubspec.lock" "media_kit_libs_android_video:"
Test-FileText "pubspec.lock" 'version: "1.3.8"'
Test-FileText "pubspec.lock" "flutter_vlc_player:"
Test-FileText "android/gradle/verification-metadata.xml" 'name="libvlc-all" version="3.6.3"'
Test-FileText "android/gradle/verification-metadata.xml" "dc627487bfca9e20dec69db85288e5a0e68b04561daca8d37d9f7d2c9f5094b6"
Test-FileText "pubspec.yaml" "assets/legal/native/NATIVE_PLAYBACK_NOTICE.txt"

foreach ($license in $manifest.licenseAssets) {
    $path = Join-Path $repoRoot $license.path
    Test-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Missing license asset $($license.path)"
    $hashProperty = $license.PSObject.Properties["sha256"]
    if ($null -ne $hashProperty -and $hashProperty.Value -ne "" -and (Test-Path -LiteralPath $path)) {
        Test-Hash $path $hashProperty.Value $license.path
    }
}

$packageConfigPath = Join-Path $repoRoot ".dart_tool\package_config.json"
if (Test-Path -LiteralPath $packageConfigPath) {
    $packageConfig = Get-Content -Raw -LiteralPath $packageConfigPath | ConvertFrom-Json
    $nativePackage = $packageConfig.packages | Where-Object name -eq "media_kit_libs_android_video" | Select-Object -First 1
    Test-Condition ($null -ne $nativePackage) "media_kit_libs_android_video is absent from package_config.json"
    if ($null -ne $nativePackage) {
        $rootUri = [Uri]$nativePackage.rootUri
        $packageRoot = [Uri]::UnescapeDataString($rootUri.LocalPath)
        $pluginGradle = Join-Path $packageRoot "android\build.gradle"
        if (Test-Path -LiteralPath $pluginGradle) {
            $pluginText = Get-Content -Raw -LiteralPath $pluginGradle
            Test-Condition $pluginText.Contains("releases/download/v1.1.7/default-arm64-v8a.jar") "Plugin does not resolve v1.1.7 arm64 JAR"
            Test-Condition $pluginText.Contains("releases/download/v1.1.7/default-armeabi-v7a.jar") "Plugin does not resolve v1.1.7 armv7 JAR"
            Test-Condition $pluginText.Contains("83df25b61193af8fa815e373143ac9af") "Plugin arm64 MD5 differs from manifest evidence"
            Test-Condition $pluginText.Contains("22e21526fefc0a2b8f17adbec9f57590") "Plugin armv7 MD5 differs from manifest evidence"
        } else {
            $failures.Add("Missing resolved plugin Gradle file at $pluginGradle")
        }
    }
} else {
    $failures.Add("Run flutter pub get before verification; .dart_tool/package_config.json is missing")
}

$resolved = 0
foreach ($artifact in $manifest.binaryArtifacts) {
    $candidates = @()
    if ($artifact.id -like "libmpv-*") {
        $candidates += Join-Path $repoRoot "build\media_kit_libs_android_video\v1.1.7\$($artifact.fileName)"
        $candidates += Join-Path $repoRoot "build\media_kit_libs_android_video\output\$($artifact.fileName)"
    } else {
        $gradleRoot = Join-Path $env:USERPROFILE ".gradle\caches\modules-2\files-2.1\org.videolan.android\libvlc-all\3.6.3"
        if (Test-Path -LiteralPath $gradleRoot) {
            $candidates += Get-ChildItem -Path $gradleRoot -Recurse -Filter $artifact.fileName -File | ForEach-Object FullName
        }
    }
    $candidate = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($null -ne $candidate) {
        Test-Hash $candidate $artifact.sha256 $artifact.id
        Test-Condition ((Get-Item -LiteralPath $candidate).Length -eq $artifact.size) "$($artifact.id) size mismatch"
        $resolved++
    } elseif ($RequireResolvedBinaries) {
        $failures.Add("Resolved binary not found: $($artifact.id)")
    } else {
        Write-Warning "Resolved binary not present locally; hash not checked: $($artifact.id)"
    }
}

if ($failures.Count -gt 0) {
    throw ("Native redistribution verification failed:`n - " + ($failures -join "`n - "))
}

Write-Host "Native redistribution metadata verified; $resolved resolved binary artifact(s) checked."
foreach ($limit in $manifest.knownProvenanceLimits) {
    Write-Warning $limit
}

if (-not $StageBundle) { exit 0 }

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "build\release-compliance\native-playback"
}
$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot "build\release-compliance"))
if (-not $outputFull.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDirectory must be a child of $allowedRoot"
}
if (Test-Path -LiteralPath $outputFull) {
    throw "Refusing to overwrite existing staging directory: $outputFull"
}

$sourceDir = Join-Path $outputFull "sources"
$checkoutDir = Join-Path $outputFull ".checkouts"
$licenseDir = Join-Path $outputFull "licenses"
New-Item -ItemType Directory -Path $sourceDir, $checkoutDir, $licenseDir -Force | Out-Null
Copy-Item -LiteralPath $manifestPath -Destination $outputFull
Copy-Item -LiteralPath (Join-Path $repoRoot "docs\NATIVE_PLAYBACK_REDISTRIBUTION.md") -Destination $outputFull
foreach ($license in $manifest.licenseAssets) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $license.path) -Destination $licenseDir
}

$resolvedRefs = [System.Collections.Generic.List[object]]::new()
function Export-GitSnapshot([string]$Id, [string]$Repository, [string]$Ref, [bool]$Immutable) {
    $checkout = Join-Path $script:checkoutDir $Id
    if ($Immutable) {
        & git clone --quiet --no-checkout $Repository $checkout
        if ($LASTEXITCODE -ne 0) { throw "git clone failed for $Id" }
        & git -C $checkout checkout --quiet --detach $Ref
    } else {
        & git clone --quiet --depth 1 --branch $Ref --single-branch $Repository $checkout
    }
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed for $Id at $Ref" }
    $resolvedRef = (& git -C $checkout rev-parse HEAD).Trim()
    if ($Immutable -and $resolvedRef -ne $Ref) { throw "$Id resolved to $resolvedRef instead of $Ref" }
    $archive = Join-Path $script:sourceDir "$Id-$resolvedRef.zip"
    & git -C $checkout archive --format=zip --output=$archive $resolvedRef
    if ($LASTEXITCODE -ne 0) { throw "git archive failed for $Id" }
    $script:resolvedRefs.Add([pscustomobject]@{
        id = $Id; repository = $Repository; requestedRef = $Ref
        resolvedCommit = $resolvedRef; immutableInput = $Immutable
        archive = [IO.Path]::GetFileName($archive)
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    })
}

foreach ($source in $manifest.sourceRoots) {
    Export-GitSnapshot $source.id $source.repository $source.revision $true
}
foreach ($source in $manifest.libmpvDeclaredDependencyRefs) {
    $id = ($source.name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    Export-GitSnapshot "libmpv-dependency-$id" $source.repository $source.ref $false
}

$resolvedRefs | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $outputFull "RESOLVED_SOURCE_REFS.json")
$hashLines = Get-ChildItem -Path $sourceDir -File | Sort-Object Name | ForEach-Object {
    "{0}  sources/{1}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant(), $_.Name
}
$hashLines | Set-Content -Encoding ascii -LiteralPath (Join-Path $outputFull "SOURCE_SNAPSHOT_HASHES.sha256")

$bundleReadme = @"
This bundle contains the exact immutable source roots and snapshots of each
upstream-declared dependency ref recorded for TetoTV's native playback stacks.
Read NATIVE_PLAYBACK_REDISTRIBUTION.md and RESOLVED_SOURCE_REFS.json before use.
Mutable-tag inputs and the lack of upstream reproducible-build metadata remain
documented evidence limits; this bundle does not assert bit-for-bit identity.
"@
$bundleReadme | Set-Content -Encoding utf8 -LiteralPath (Join-Path $outputFull "README.txt")

$checkoutFull = [IO.Path]::GetFullPath($checkoutDir)
if (-not $checkoutFull.StartsWith($outputFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe checkout cleanup target: $checkoutFull"
}
Remove-Item -LiteralPath $checkoutFull -Recurse -Force
$bundlePath = Join-Path (Split-Path $outputFull -Parent) "TetoTV-native-playback-sources.zip"
if (Test-Path -LiteralPath $bundlePath) { throw "Refusing to overwrite $bundlePath" }
Compress-Archive -Path (Join-Path $outputFull "*") -DestinationPath $bundlePath -CompressionLevel Optimal
Write-Host "Staged native redistribution bundle: $bundlePath"
Write-Host "SHA-256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $bundlePath).Hash.ToLowerInvariant())"
Write-Warning "A qualified release reviewer must resolve the manifest's provenance limits and verify complete corresponding source before publishing."
