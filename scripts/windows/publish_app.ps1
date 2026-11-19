<#
    LearnInCreation: publish the Android app as the public download.

    Double-click PUBLISH-APP.cmd in the project folder. It:
      1. Builds the release APK for the live server (https://api.learnincreation.com),
         signed with your release key (PREPARE-PRODUCTION.cmd creates the key once).
      2. Checks that the APK really is signed with that key.
      3. Uploads the APK to the "apk" branch of your public learn-app-releases
         repository on GitHub and adds a version tag such as v1.0.0-build101.
         The "Publish the app" workflow in that repository then publishes it as
         a release, so this link always gives the newest version:
         https://github.com/<you>/learn-app-releases/releases/latest/download/LearnInCreation.apk
    Your signing key never leaves this PC. Git uses the GitHub sign-in that
    PUSH-TO-GITHUB.cmd already set up.
    Everything is also written to publish-log.txt; the last line starts with RESULT.

    Options: -ServerUrl https://... builds for another server address,
             -ReleasesRepo https://github.com/you/repo.git publishes elsewhere.
#>
param(
    [string]$ServerUrl = 'https://api.learnincreation.com',
    [string]$ReleasesRepo = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$App = Join-Path $Root 'app'
$KeyProps = Join-Path $App 'android\key.properties'
$LogFile = Join-Path $Root 'publish-log.txt'
$Work = Join-Path $env:TEMP 'learnincreation-publish'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($LogFile, '', $Utf8)

function Write-Log([string]$Text) {
    [System.IO.File]::AppendAllText($LogFile, $Text + "`r`n", $Utf8)
}

function Info([string]$Text) {
    Write-Host $Text
    Write-Log $Text
}

function Step([string]$Title) {
    $line = '=== ' + (Get-Date -Format 'HH:mm:ss') + '  ' + $Title
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Log ''
    Write-Log $line
}

function Run {
    # Runs a program, showing its output in this window and in the log.
    # Stops the script when the program fails.
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @(),
        [string]$WorkDir = $Root
    )
    Write-Log ('> ' + $Exe + ' ' + ($Arguments -join ' '))
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    Push-Location $WorkDir
    try {
        & $Exe @Arguments 2>&1 | ForEach-Object {
            $text = "$_"
            Write-Host $text
            Write-Log $text
        }
        $code = $global:LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) {
        throw ((Split-Path -Leaf $Exe) + ' ' + ($Arguments -join ' ') + ' failed with exit code ' + $code)
    }
}

function Get-Lines([string]$Exe, [string[]]$Arguments) {
    # Runs a program and returns its standard output lines (standard error is ignored).
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Exe @Arguments 2>$null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) { throw ((Split-Path -Leaf $Exe) + ' ' + $Arguments[0] + ' failed with exit code ' + $code + '.') }
    return @($output | ForEach-Object { [string]$_ })
}

function Invoke-GitCapture([string[]]$GitArgs) {
    # Runs git quietly; returns its exit code and output (both also go to the log).
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:GitExe @GitArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    $lines = @($output | ForEach-Object { [string]$_ })
    Write-Log ('> git ' + ($GitArgs -join ' '))
    foreach ($l in $lines) { Write-Log $l }
    return [pscustomobject]@{ Code = $code; Lines = $lines; Text = (($lines -join "`n").Trim()) }
}

function Get-JdkMajor([string]$JdkDir) {
    if (-not $JdkDir) { return 0 }
    if (-not (Test-Path (Join-Path $JdkDir 'bin\java.exe'))) { return 0 }
    $releaseFile = Join-Path $JdkDir 'release'
    if (-not (Test-Path $releaseFile)) { return 0 }
    foreach ($line in [System.IO.File]::ReadAllLines($releaseFile)) {
        if ($line -match '^JAVA_VERSION="?(\d+)(?:\.(\d+))?') {
            $major = [int]$Matches[1]
            if ($major -eq 1 -and $Matches[2]) { $major = [int]$Matches[2] }
            return $major
        }
    }
    return 0
}

function Find-Jdk {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    $candidates += @("$env:ProgramFiles\Android\Android Studio\jbr", "$env:LOCALAPPDATA\Programs\Android Studio\jbr",
                     (Join-Path $env:USERPROFILE 'jdk-21'))
    foreach ($c in $candidates) {
        if ((Get-JdkMajor $c) -ge 17) { return (Resolve-Path $c).Path }
    }
    return ''
}

function Find-ApkSigner {
    $tools = Join-Path $env:ANDROID_HOME 'build-tools'
    if (-not (Test-Path $tools)) { return '' }
    $best = ''
    $bestVersion = [version]'0.0'
    foreach ($d in @(Get-ChildItem -Path $tools -Directory -ErrorAction SilentlyContinue)) {
        $exe = Join-Path $d.FullName 'apksigner.bat'
        if (-not (Test-Path $exe)) { continue }
        $v = [version]'0.0.1'
        if ($d.Name -match '^(\d+\.\d+(\.\d+)?)') { $v = [version]$Matches[1] }
        if (-not $best -or $v -gt $bestVersion) { $best = $exe; $bestVersion = $v }
    }
    return $best
}

function Get-HttpStatus([string]$Url) {
    # HTTP status of a URL without following redirects, such as '200', '302' or
    # '404' ('000' when there is no answer).
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & curl.exe -s -o NUL -I -w '%{http_code}' --max-time 30 $Url 2>$null
    } finally {
        $ErrorActionPreference = $previous
    }
    return ("$out").Trim()
}

try {
    Write-Host 'LearnInCreation: builds the app for the live server and publishes it on GitHub.'
    Write-Host 'Your signing key stays on this PC.'

    # ------------------------------------------------------------------ tools
    Step 'Checking the tools'
    $script:GitExe = ''
    $found = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($found) { $script:GitExe = $found.Source }
    elseif (Test-Path "$env:ProgramFiles\Git\cmd\git.exe") { $script:GitExe = "$env:ProgramFiles\Git\cmd\git.exe" }
    if (-not $script:GitExe) { throw 'Git for Windows is not installed. Install it from https://git-scm.com/download/win, then run this again.' }

    $flutter = ''
    $found = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($found) { $flutter = $found.Source }
    foreach ($p in @((Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'), 'C:\flutter\bin\flutter.bat')) {
        if (-not $flutter -and (Test-Path $p)) { $flutter = $p }
    }
    if (-not $flutter) { throw 'Flutter was not found. Run SETUP-AND-BUILD-ON-WINDOWS.cmd once first.' }

    $jdk = Find-Jdk
    if (-not $jdk) { throw 'Java was not found. Run SETUP-AND-BUILD-ON-WINDOWS.cmd once first.' }
    $env:JAVA_HOME = $jdk
    $env:Path = (Join-Path $jdk 'bin') + ';' + $env:Path
    $keytool = Join-Path $jdk 'bin\keytool.exe'

    if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
        $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
        if (-not (Test-Path $sdk)) { throw 'The Android SDK was not found. Run SETUP-AND-BUILD-ON-WINDOWS.cmd once first.' }
        $env:ANDROID_HOME = $sdk
    }
    Info ('Git: ' + $script:GitExe)
    Info ('Flutter: ' + $flutter)
    Info ('Java: ' + $jdk)
    Info ('Android SDK: ' + $env:ANDROID_HOME)

    if ($ServerUrl -notmatch '^https://[^/\s]+') { throw ('The server address must start with https:// (got: ' + $ServerUrl + ').') }
    $ServerUrl = $ServerUrl.TrimEnd('/')

    if (-not (Test-Path $KeyProps)) { throw 'The release signing key is missing. Double-click PREPARE-PRODUCTION.cmd once, then run this again.' }
    $props = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($KeyProps)) {
        if ($line -match '^\s*([A-Za-z]+)\s*=\s*(.*?)\s*$') { $props[$Matches[1]] = $Matches[2] }
    }
    $storeFile = [string]$props['storeFile']
    if ($storeFile -and -not [System.IO.Path]::IsPathRooted($storeFile)) { $storeFile = Join-Path (Join-Path $App 'android\app') $storeFile }
    if (-not $storeFile -or -not (Test-Path $storeFile)) { throw 'The release key file named in app\android\key.properties is missing. Restore it from your backup.' }

    # ------------------------------------------------------------------ GitHub repository
    Step 'Checking the learn-app-releases repository on GitHub'
    if (-not $ReleasesRepo) {
        $origin = (Invoke-GitCapture @('-C', $Root, 'remote', 'get-url', 'origin')).Text
        if ($origin -match '^https://github\.com/([A-Za-z0-9_.-]+)/') {
            $ReleasesRepo = 'https://github.com/' + $Matches[1] + '/learn-app-releases.git'
        } else {
            throw 'Could not tell your GitHub account from this folder. Run PUSH-TO-GITHUB.cmd once first.'
        }
    }
    $ReleasesWeb = $ReleasesRepo -replace '\.git$', ''
    Info ('Repository: ' + $ReleasesWeb)
    $heads = Invoke-GitCapture @('ls-remote', '--heads', $ReleasesRepo, 'main')
    if ($heads.Code -ne 0) {
        throw ('GitHub did not find ' + $ReleasesWeb + '. Create it on github.com as a PUBLIC repository with a README, then run this again.')
    }
    if (-not ($heads.Text -match 'refs/heads/main')) {
        throw ($ReleasesWeb + ' has no main branch yet. Add a README file to it on github.com, then run this again.')
    }

    $buildNumber = 100
    $tags = Invoke-GitCapture @('ls-remote', '--tags', $ReleasesRepo)
    foreach ($l in $tags.Lines) {
        if ($l -match 'refs/tags/v[^\s^]*-build(\d+)$') {
            if ([int]$Matches[1] -gt $buildNumber) { $buildNumber = [int]$Matches[1] }
        }
    }
    $buildNumber = $buildNumber + 1
    $pubspec = [System.IO.File]::ReadAllText((Join-Path $App 'pubspec.yaml'))
    $versionName = '1.0.0'
    if ($pubspec -match '(?m)^version:\s*(\d+\.\d+\.\d+)') { $versionName = $Matches[1] }
    $tag = 'v' + $versionName + '-build' + $buildNumber
    Info ('New version: ' + $versionName + ' (build ' + $buildNumber + '), tag ' + $tag)

    $health = Get-HttpStatus ($ServerUrl + '/api/health')
    if ($health -eq '200') {
        Info ('Server ' + $ServerUrl + ' is online.')
    } else {
        Info ('Note: ' + $ServerUrl + ' is not online yet (answer: ' + $health + '). The app installs, but it can only sign in and load courses once the server is live.')
    }

    # ------------------------------------------------------------------ build
    Step 'App packages and unit tests'
    Remove-Item Env:LI_ALLOW_CLEARTEXT -ErrorAction SilentlyContinue
    Run -Exe $flutter -Arguments @('pub', 'get') -WorkDir $App
    Run -Exe $flutter -Arguments @('test') -WorkDir $App

    Step ('Building the release APK for ' + $ServerUrl + ' (5-10 minutes)')
    $buildArgs = @('build', 'apk', '--release', '--build-name', $versionName, '--build-number', [string]$buildNumber,
                   ('--dart-define=API_BASE_URL=' + $ServerUrl))
    if ($env:GOOGLE_SERVER_CLIENT_ID) { $buildArgs += ('--dart-define=GOOGLE_SERVER_CLIENT_ID=' + $env:GOOGLE_SERVER_CLIENT_ID) }
    Run -Exe $flutter -Arguments $buildArgs -WorkDir $App
    $builtApk = Join-Path $App 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $builtApk)) { throw ('The build finished but the APK was not found at ' + $builtApk) }
    $sizeMb = [math]::Round((Get-Item $builtApk).Length / 1MB, 1)
    Info ('APK built: ' + $sizeMb + ' MB')

    Step 'Checking that the APK is signed with your release key'
    $env:LI_STOREPASS = [string]$props['storePassword']
    try {
        $listing = Get-Lines $keytool @('-list', '-v', '-keystore', $storeFile, '-alias', [string]$props['keyAlias'], '-storepass:env', 'LI_STOREPASS')
    } finally {
        Remove-Item Env:LI_STOREPASS -ErrorAction SilentlyContinue
    }
    $keyDigest = ''
    foreach ($l in $listing) {
        if ($l -match '^\s*SHA-?256:\s*([0-9A-Fa-f:]{64,})') { $keyDigest = ($Matches[1] -replace ':', '').ToLower() }
    }
    $apkDigest = ''
    $signer = Find-ApkSigner
    if ($signer) {
        foreach ($l in (Get-Lines $signer @('verify', '--print-certs', $builtApk))) {
            if (-not $apkDigest -and $l -match 'certificate SHA-256 digest:\s*([0-9A-Fa-f]{64})') { $apkDigest = $Matches[1].ToLower() }
        }
    } else {
        foreach ($l in (Get-Lines $keytool @('-printcert', '-jarfile', $builtApk))) {
            if (-not $apkDigest -and $l -match '^\s*SHA-?256:\s*([0-9A-Fa-f:]{64,})') { $apkDigest = ($Matches[1] -replace ':', '').ToLower() }
        }
    }
    if (-not $keyDigest) { throw 'Could not read your release key (app\android\key.properties). Nothing was published.' }
    if (-not $apkDigest) { throw 'Could not read the APK signature. Nothing was published.' }
    if ($keyDigest -ne $apkDigest) { throw 'The APK is NOT signed with your release key, so it was not published. Check app\android\key.properties.' }
    Info 'Signed with your release key.'

    $finalApk = Join-Path $Root 'LearnInCreation.apk'
    Copy-Item $builtApk $finalApk -Force
    Info ('A copy is saved as ' + $finalApk)

    # ------------------------------------------------------------------ upload
    Step 'Uploading the APK to GitHub (about 55 MB; a few minutes on a slow connection)'
    if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $Work
    Copy-Item $builtApk (Join-Path $Work 'LearnInCreation.apk')
    $sourceCommit = (Invoke-GitCapture @('-C', $Root, 'rev-parse', '--short', 'HEAD')).Text
    $notes = @(
        $tag,
        ('LearnInCreation Android app, version ' + $versionName + ' (build ' + $buildNumber + ').'),
        '',
        'Download **LearnInCreation.apk** below on your Android phone and open it. If the phone asks, allow installing apps from your browser or Files app.',
        '',
        ('The newest version is always at ' + $ReleasesWeb + '/releases/latest/download/LearnInCreation.apk'),
        '',
        ('Built from learn-app commit ' + $sourceCommit + ' for ' + $ServerUrl + '.')
    ) -join "`n"
    [System.IO.File]::WriteAllText((Join-Path $Work 'release.txt'), $notes + "`n", $Utf8)
    [System.IO.File]::WriteAllText((Join-Path $Work '.gitattributes'), "*.apk binary`n", $Utf8)
    foreach ($a in @(@('init', '-q', '-b', 'apk'), @('add', '-A'), @('commit', '-q', '-m', ('LearnInCreation ' + $tag)))) {
        $r = Invoke-GitCapture (@('-C', $Work) + $a)
        if ($r.Code -ne 0) { throw ('git ' + $a[0] + ' failed: ' + $r.Text) }
    }
    Write-Log ('> git push --force ' + $ReleasesRepo + ' apk')
    & $script:GitExe -C $Work push --force $ReleasesRepo 'apk:refs/heads/apk'
    $pushCode = $LASTEXITCODE
    Write-Log ('git push exit code ' + $pushCode)
    if ($pushCode -ne 0) { throw ('Uploading the APK failed (git exit code ' + $pushCode + '). Check the internet connection and run this again.') }

    Step ('Publishing version ' + $tag)
    $fetch = Invoke-GitCapture @('-C', $Work, 'fetch', '-q', $ReleasesRepo, 'main')
    if ($fetch.Code -ne 0) { throw ('Could not read the main branch of ' + $ReleasesWeb + ': ' + $fetch.Text) }
    $mainSha = (Invoke-GitCapture @('-C', $Work, 'rev-parse', 'FETCH_HEAD')).Text
    $workflow = Invoke-GitCapture @('-C', $Work, 'cat-file', '-e', 'FETCH_HEAD:.github/workflows/publish.yml')
    if ($workflow.Code -ne 0) {
        throw ('The "Publish the app" workflow (.github/workflows/publish.yml) is missing in ' + $ReleasesWeb + ', so the APK was uploaded but not published. Add it (copy scripts\github\publish.yml from this project) and run this again.')
    }
    $tagPush = Invoke-GitCapture @('-C', $Work, 'push', $ReleasesRepo, ($mainSha + ':refs/tags/' + $tag))
    if ($tagPush.Code -ne 0) { throw ('Adding the version tag failed: ' + $tagPush.Text) }
    Info ('Tag ' + $tag + ' added. GitHub is publishing the release...')

    $tagUrl = $ReleasesWeb + '/releases/download/' + $tag + '/LearnInCreation.apk'
    $latestUrl = $ReleasesWeb + '/releases/latest/download/LearnInCreation.apk'
    $deadline = (Get-Date).AddMinutes(8)
    $published = $false
    $status = ''
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 10
        $status = Get-HttpStatus $tagUrl
        if ($status -eq '302' -or $status -eq '200') { $published = $true; break }
        Write-Host '.' -NoNewline
    }
    Write-Host ''
    Write-Log ('Last check of ' + $tagUrl + ': ' + $status)
    Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue

    Step 'Done'
    if ($published) {
        $latest = Get-HttpStatus $latestUrl
        Info ('Published ' + $tag + ' (' + $sizeMb + ' MB).')
        Info ('Download link (always the newest version): ' + $latestUrl)
        Info ('Release page: ' + $ReleasesWeb + '/releases/tag/' + $tag)
        if ($latest -ne '302' -and $latest -ne '200') { Info ('Note: the "latest" link answered ' + $latest + '; it can take a minute to switch to the new version.') }
        Write-Log ('RESULT: OK ' + $tag + ' ' + $latestUrl)
    } else {
        Info ('The APK and tag were uploaded, but this PC could not see the release within 8 minutes (last answer: ' + $status + ').')
        Info ('Open ' + $ReleasesWeb + '/releases to check, and ' + $ReleasesWeb + '/actions for the "Publish the app" run.')
        Write-Log ('RESULT: UPLOADED ' + $tag + ' (release not seen yet; see ' + $ReleasesWeb + '/actions)')
    }
} catch {
    $message = $_.Exception.Message
    Write-Host ''
    Write-Host ('Stopped: ' + $message) -ForegroundColor Red
    Write-Log ''
    Write-Log ('RESULT: FAILED ' + $message)
    exit 1
}
