$ErrorActionPreference = "Stop"

$RepoRoot = "C:\Users\harrison.edwards\rustdesk-fork\rustdesk"
$FlutterDir = Join-Path $RepoRoot "flutter"
$BridgeHeader = Join-Path $RepoRoot "flutter\windows\runner\generated_bridge.h"
$LlvmPath = "C:\Program Files\LLVM\bin"
$env:USE_AOM_391 = "1"

Set-Location $RepoRoot

Write-Host "`n=== Cleaning generated/local Flutter files ===" -ForegroundColor Cyan

git restore flutter/pubspec.lock 2>$null

if (Test-Path $BridgeHeader) {
    Remove-Item $BridgeHeader -Force
}

Write-Host "`n=== Synchronizing existing submodules ===" -ForegroundColor Cyan

git submodule sync --recursive
git submodule update --init --recursive

if ($LASTEXITCODE -ne 0) {
    throw "Submodule preflight update failed. Check submodules for local changes."
}

Write-Host "`n=== Checking working tree ===" -ForegroundColor Cyan

$status = git status --porcelain

if ($status) {
    Write-Host "Working tree contains changes:" -ForegroundColor Yellow
    $status
    throw "Working tree is not clean. Resolve or commit changes before updating."
}

Write-Host "`n=== Fetching upstream ===" -ForegroundColor Cyan

git fetch upstream

if ($LASTEXITCODE -ne 0) {
    throw "git fetch upstream failed."
}

Write-Host "`n=== Switching to master ===" -ForegroundColor Cyan

git switch master

if ($LASTEXITCODE -ne 0) {
    throw "Unable to switch to master."
}

Write-Host "`n=== Merging upstream/master ===" -ForegroundColor Cyan

git merge upstream/master

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nMerge failed or produced conflicts." -ForegroundColor Red
    Write-Host "Conflicted files:" -ForegroundColor Yellow

    git diff --name-only --diff-filter=U

    Write-Host "`nResolve the conflicts, then run:" -ForegroundColor Yellow
    Write-Host "    git add <resolved-files>"
    Write-Host "    git commit"
    Write-Host "`nThen rerun this script."

    exit 1
}

# Extra safety check for unresolved conflict markers.
$unmergedFiles = git diff --name-only --diff-filter=U

if ($unmergedFiles) {
    Write-Host "`nUnresolved merge conflicts remain:" -ForegroundColor Red
    $unmergedFiles
    exit 1
}

Write-Host "`n=== Scanning tracked files for conflict markers ===" -ForegroundColor Cyan

$conflictMarkers = git grep -n -E '^(<<<<<<<|=======|>>>>>>>)' -- `
    '*.rs' `
    '*.toml' `
    '*.dart' `
    '*.c' `
    '*.h' `
    '*.cpp' `
    '*.yml' `
    '*.yaml' `
    '*.py' 2>$null

if ($conflictMarkers) {
    Write-Host "`nConflict markers were found:" -ForegroundColor Red
    $conflictMarkers
    throw "Resolve conflict markers before continuing."
}

Write-Host "`n=== Pushing updated master to fork ===" -ForegroundColor Cyan

git push origin master

if ($LASTEXITCODE -ne 0) {
    throw "git push origin master failed."
}

Write-Host "`n=== Synchronizing submodules ===" -ForegroundColor Cyan

git submodule sync --recursive
git submodule update --init --recursive

if ($LASTEXITCODE -ne 0) {
    throw "Submodule update failed."
}

Write-Host "`n=== Fetching Rust dependencies ===" -ForegroundColor Cyan

cargo fetch --locked

if ($LASTEXITCODE -ne 0) {
    throw "cargo fetch failed."
}

Write-Host "`n=== Generating Flutter Rust Bridge ===" -ForegroundColor Cyan

flutter_rust_bridge_codegen `
    --rust-input .\src\flutter_ffi.rs `
    --dart-output .\flutter\lib\generated_bridge.dart `
    --rust-output .\src\bridge_generated.rs `
    --c-output .\flutter\windows\runner\generated_bridge.h `
    --llvm-path $LlvmPath

if ($LASTEXITCODE -ne 0) {
    throw "Flutter Rust Bridge generation failed."
}

Write-Host "`n=== Refreshing Flutter dependencies ===" -ForegroundColor Cyan

Set-Location $FlutterDir

flutter clean

if ($LASTEXITCODE -ne 0) {
    throw "flutter clean failed."
}

flutter pub get

if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed."
}

Set-Location $RepoRoot

Write-Host "`n=== Building RustDesk ===" -ForegroundColor Cyan

python .\build.py --flutter --skip-portable-pack

if ($LASTEXITCODE -ne 0) {
    throw "RustDesk build failed."
}

Write-Host "`n=== Cleaning generated files after build ===" -ForegroundColor Cyan

git restore flutter/pubspec.lock 2>$null

if (Test-Path $BridgeHeader) {
    Remove-Item $BridgeHeader -Force
}

Write-Host "`n=== Final repository status ===" -ForegroundColor Cyan

git status

Write-Host "`nBuild workflow completed successfully." -ForegroundColor Green
