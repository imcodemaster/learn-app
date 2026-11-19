<#
  LearnInCreation - one-click setup and build for Windows.
  Start it by double-clicking SETUP-AND-BUILD-ON-WINDOWS.cmd in the project folder.

  What it does (finished steps are skipped or quick when you run it again):
    1. Unpacks the project files (if a newer _source.zip is present).
    2. Installs the Flutter SDK into %USERPROFILE%\flutter if Flutter is missing,
       and a Java JDK 21 into %USERPROFILE%\jdk-21 if no JDK 17+ is found
       (Android Studio's own Java is used when it is installed).
    3. Installs the Django backend's packages into backend\.venv, sets up the
       database with demo content, creates a local admin login and runs the
       backend test suite.
    4. Builds a Wi-Fi test APK that talks to the backend on this PC.
    5. Starts the backend server in its own window.

  Everything is written to setup-log.txt; the current step to setup-status.txt.

  Optional: -ServerUrl https://api.example.com builds the APK for a live server
  instead of this PC (the local backend steps still run).
#>
param(
    [string]$ServerUrl = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Backend = Join-Path $Root 'backend'
$App = Join-Path $Root 'app'
$LogFile = Join-Path $Root 'setup-log.txt'
$StatusFile = Join-Path $Root 'setup-status.txt'
$JdkHome = Join-Path $env:USERPROFILE 'jdk-21'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Summary = New-Object System.Collections.Generic.List[string]

function Write-Log([string]$Text) {
    [System.IO.File]::AppendAllText($LogFile, $Text + "`r`n", $Utf8)
}

function Set-Status([string]$Text) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    [System.IO.File]::WriteAllText($StatusFile, $stamp + '  ' + $Text + "`r`n", $Utf8)
}

function Step([string]$Title) {
    $line = '=== ' + (Get-Date -Format 'HH:mm:ss') + '  ' + $Title
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Log ''
    Write-Log $line
    Set-Status ('RUNNING: ' + $Title)
}

function Info([string]$Text) {
    Write-Host $Text
    Write-Log $Text
}

function Run {
    # Runs a program, showing its output in this window and in the log.
    # Returns the exit code. Stops the script on failure unless -AllowFail.
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Arguments = @(),
        [string]$WorkDir = $Root,
        [switch]$AllowFail
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
    if ($null -eq $code) { $code = 0 }
    if ($code -ne 0 -and -not $AllowFail) {
        throw ((Split-Path -Leaf $Exe) + ' ' + ($Arguments -join ' ') + ' failed with exit code ' + $code)
    }
    return $code
}

function Get-EnvValue([string]$Path, [string]$Key) {
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=(.*)$')) { return $Matches[1].Trim() }
    }
    return ''
}

function Set-EnvValue([string]$Path, [string]$Key, [string]$Value) {
    $lines = [System.IO.File]::ReadAllLines($Path)
    $found = $false
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $lines[$i] = $Key + '=' + $Value
            $found = $true
        }
    }
    if (-not $found) { $lines = $lines + ($Key + '=' + $Value) }
    [System.IO.File]::WriteAllLines($Path, [string[]]$lines, $Utf8)
}

function Add-ToUserPath([string]$Folder) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $parts = @($raw.Split(';') | Where-Object { $_ -ne '' })
        foreach ($p in $parts) {
            if ([Environment]::ExpandEnvironmentVariables($p).TrimEnd('\') -ieq $Folder.TrimEnd('\')) { return $false }
        }
        $key.SetValue('Path', (($parts + $Folder) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally {
        $key.Close()
    }
    # Setting a variable through .NET tells Windows that the environment changed.
    [Environment]::SetEnvironmentVariable('LEARNINCREATION_SETUP', '1', 'User')
    [Environment]::SetEnvironmentVariable('LEARNINCREATION_SETUP', $null, 'User')
    return $true
}

function New-Password {
    $bytes = New-Object byte[] 12
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return 'Li' + (([Convert]::ToBase64String($bytes)) -replace '[^A-Za-z0-9]', 'x') + '7'
}

function Get-JdkMajor([string]$JdkDir) {
    # Major Java version of a JDK folder, or 0 if the folder is not a usable JDK.
    if (-not $JdkDir) { return 0 }
    if (-not (Test-Path (Join-Path $JdkDir 'bin\java.exe'))) { return 0 }
    if (-not (Test-Path (Join-Path $JdkDir 'bin\javac.exe'))) { return 0 }
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
    # A JDK 17 or newer: JAVA_HOME, Android Studio's Java, the one this script
    # downloaded earlier, or a JDK installed in the usual places.
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:JAVA_HOME) { $candidates.Add($env:JAVA_HOME) }
    foreach ($p in @("$env:ProgramFiles\Android\Android Studio\jbr", "$env:LOCALAPPDATA\Programs\Android Studio\jbr", "$env:ProgramFiles\Android\Android Studio\jre", $JdkHome)) {
        $candidates.Add($p)
    }
    foreach ($parent in @("$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Microsoft", "$env:ProgramFiles\Java", "$env:ProgramFiles\Zulu", "$env:ProgramFiles\Amazon Corretto", "$env:ProgramFiles\BellSoft", (Join-Path $env:USERPROFILE '.jdks'))) {
        if (Test-Path $parent) {
            foreach ($d in @(Get-ChildItem -Path $parent -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
                $candidates.Add($d.FullName)
            }
        }
    }
    foreach ($c in $candidates) {
        if ((Get-JdkMajor $c) -ge 17) { return (Resolve-Path $c).Path }
    }
    return ''
}

function Install-Jdk {
    # Downloads Eclipse Temurin JDK 21 (a free OpenJDK build) and checks its SHA-256.
    Info 'No Java JDK 17 or newer was found. Downloading Eclipse Temurin JDK 21 (about 200 MB)...'
    $api = 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
    $package = $null
    foreach ($asset in @(Invoke-RestMethod -Uri $api)) {
        if ($asset.binary -and $asset.binary.package -and ([string]$asset.binary.package.name) -like '*.zip') {
            $package = $asset.binary.package
            break
        }
    }
    if (-not $package) { throw 'Could not find a Java download. Install Android Studio (it includes Java), then run this again.' }
    Info ('Java download: ' + $package.name)
    $archive = Join-Path $env:TEMP ([string]$package.name)
    $haveArchive = (Test-Path $archive) -and ((Get-FileHash $archive -Algorithm SHA256).Hash -eq [string]$package.checksum)
    if (-not $haveArchive) {
        $null = Run -Exe 'curl.exe' -Arguments @('-L', '--fail', '--retry', '5', '-sS', '-o', $archive, [string]$package.link)
        if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne [string]$package.checksum) {
            Remove-Item $archive -Force
            throw 'The Java download was damaged. Run this again to retry.'
        }
    }
    $unpackDir = $JdkHome + '.unpacking'
    if (Test-Path $unpackDir) { Remove-Item $unpackDir -Recurse -Force }
    if (Test-Path $JdkHome) { Remove-Item $JdkHome -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $unpackDir
    $null = Run -Exe 'tar.exe' -Arguments @('-xf', $archive, '-C', $unpackDir)
    $inner = @(Get-ChildItem -Path $unpackDir -Directory)
    if ($inner.Count -ne 1) { throw ('Java did not unpack as expected in ' + $unpackDir) }
    Move-Item -Path $inner[0].FullName -Destination $JdkHome
    Remove-Item $unpackDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $archive -Force -ErrorAction SilentlyContinue
    if ((Get-JdkMajor $JdkHome) -lt 17) { throw ('Java was unpacked but does not work: ' + $JdkHome) }
    return $JdkHome
}

try {
    [System.IO.File]::WriteAllText($LogFile, '', $Utf8)
    Step 'Starting'
    Info ('Project folder: ' + $Root)
    Info ('PowerShell ' + $PSVersionTable.PSVersion.ToString() + ' on ' + [Environment]::OSVersion.VersionString)

    # ------------------------------------------------------------------ 1. project files
    $sourceZip = Join-Path $Root '_source.zip'
    $marker = Join-Path $Root '.source-unpacked'
    if (Test-Path $sourceZip) {
        $unpack = -not (Test-Path $marker)
        if (-not $unpack) { $unpack = (Get-Item $sourceZip).LastWriteTime -gt (Get-Item $marker).LastWriteTime }
        if ($unpack) {
            Step 'Unpacking the project files'
            $null = Run -Exe 'tar.exe' -Arguments @('-xf', $sourceZip, '-C', $Root)
            [System.IO.File]::WriteAllText($marker, (Get-Date -Format o), $Utf8)
        }
    }
    if (-not (Test-Path (Join-Path $App 'pubspec.yaml'))) { throw 'The app folder is missing. Put the project files next to this script.' }
    if (-not (Test-Path (Join-Path $Backend 'manage.py'))) { throw 'The backend folder is missing. Put the project files next to this script.' }

    # ------------------------------------------------------------------ 2. tools already installed
    Step 'Checking the tools already on this PC'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        foreach ($p in @("$env:ProgramFiles\Git\cmd", "${env:ProgramFiles(x86)}\Git\cmd", "$env:LOCALAPPDATA\Programs\Git\cmd")) {
            if (Test-Path (Join-Path $p 'git.exe')) { $env:Path = $p + ';' + $env:Path; break }
        }
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { throw 'Git for Windows is needed by Flutter. Install it from https://git-scm.com/download/win, then run this again.' }
    Info ('Git: ' + $git.Source)

    if (-not $env:ANDROID_HOME -or -not (Test-Path $env:ANDROID_HOME)) {
        $env:ANDROID_HOME = ''
        $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
        if (Test-Path $sdk) { $env:ANDROID_HOME = $sdk }
    }
    if (-not $env:ANDROID_HOME) { throw 'The Android SDK was not found. Open Android Studio once so it downloads the SDK, then run this again.' }
    Info ('Android SDK: ' + $env:ANDROID_HOME)
    if (-not (Test-Path (Join-Path $env:ANDROID_HOME 'licenses\android-sdk-license'))) {
        Info 'Note: the Android SDK licence file is missing, so the build may not be able to download SDK parts it needs.'
    }

    $jdk = Find-Jdk
    if (-not $jdk) {
        Step 'Java JDK for the Android build'
        $jdk = Install-Jdk
    }
    $env:JAVA_HOME = $jdk
    $env:Path = (Join-Path $jdk 'bin') + ';' + $env:Path
    Info ('Java: ' + $jdk + ' (version ' + (Get-JdkMajor $jdk) + ')')

    # ------------------------------------------------------------------ 3. Flutter
    Step 'Flutter SDK'
    $flutterBin = $null
    $existing = Get-Command flutter -ErrorAction SilentlyContinue
    if ($existing) { $flutterBin = Split-Path -Parent $existing.Source }
    $flutterHome = Join-Path $env:USERPROFILE 'flutter'
    if ($env:USERPROFILE -match '\s') { $flutterHome = 'C:\flutter' }
    if (-not $flutterBin -and (Test-Path (Join-Path $flutterHome 'bin\flutter.bat'))) { $flutterBin = Join-Path $flutterHome 'bin' }
    if (-not $flutterBin) {
        Info 'Flutter is not installed yet. Downloading the current stable release (about 1 GB)...'
        $index = Invoke-RestMethod -Uri 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
        $stableHash = $index.current_release.stable
        $release = $index.releases | Where-Object { $_.hash -eq $stableHash -and $_.channel -eq 'stable' } | Select-Object -First 1
        if (-not $release) { throw 'Could not find the current stable Flutter release.' }
        Info ('Flutter version: ' + $release.version)
        $archive = Join-Path $env:TEMP ('flutter_windows_' + $release.version + '-stable.zip')
        $url = $index.base_url + '/' + $release.archive
        $haveArchive = (Test-Path $archive) -and ((Get-FileHash $archive -Algorithm SHA256).Hash -eq $release.sha256)
        if (-not $haveArchive) {
            $null = Run -Exe 'curl.exe' -Arguments @('-L', '--fail', '--retry', '5', '-sS', '-o', $archive, $url)
            if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $release.sha256) {
                Remove-Item $archive -Force
                throw 'The Flutter download was damaged. Run this again to retry.'
            }
        }
        Info 'Unpacking Flutter (a few minutes)...'
        $parent = Split-Path -Parent $flutterHome
        $null = Run -Exe 'tar.exe' -Arguments @('-xf', $archive, '-C', $parent)
        if (-not (Test-Path (Join-Path $flutterHome 'bin\flutter.bat'))) { throw ('Flutter did not unpack where expected: ' + $flutterHome) }
        $flutterBin = Join-Path $flutterHome 'bin'
        Remove-Item $archive -Force -ErrorAction SilentlyContinue
    }
    $env:Path = $flutterBin + ';' + $env:Path
    if (Add-ToUserPath $flutterBin) { Info ('Added ' + $flutterBin + ' to your PATH, so new terminals find "flutter".') }
    $flutter = Join-Path $flutterBin 'flutter.bat'
    Info ('Flutter: ' + $flutter)
    $null = Run -Exe $flutter -Arguments @('--disable-analytics') -AllowFail
    $null = Run -Exe $flutter -Arguments @('config', '--android-sdk', $env:ANDROID_HOME) -AllowFail
    if ($env:JAVA_HOME) { $null = Run -Exe $flutter -Arguments @('config', '--jdk-dir', $env:JAVA_HOME) -AllowFail }
    $null = Run -Exe $flutter -Arguments @('--version')

    Step 'Flutter doctor (information only)'
    $null = Run -Exe $flutter -Arguments @('doctor', '-v') -AllowFail

    # ------------------------------------------------------------------ 4. this PC's address
    Step 'Finding this PC''s Wi-Fi address'
    $lanIp = ''
    $configs = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })
    $preferred = @($configs | Where-Object { $_.InterfaceAlias -match 'Wi-?Fi|Wireless|WLAN|Ethernet' })
    if ($preferred.Count -gt 0) { $configs = $preferred }
    foreach ($c in $configs) {
        foreach ($a in @($c.IPv4Address)) {
            if ($a.IPAddress -and $a.IPAddress -notlike '169.254.*' -and -not $lanIp) { $lanIp = $a.IPAddress }
        }
    }
    if (-not $lanIp) { throw 'Could not find this PC''s network address. Connect the PC to Wi-Fi or a router and run this again.' }
    Info ('This PC on the network: ' + $lanIp)
    if ($ServerUrl) { $baseUrl = $ServerUrl.TrimEnd('/') } else { $baseUrl = 'http://' + $lanIp + ':8000' }
    Info ('The app will use the server at: ' + $baseUrl)

    # ------------------------------------------------------------------ 5. backend
    Step 'Python'
    $python = $null
    $pythonArgs = @()
    $candidates = @(
        @{ Exe = 'py'; Args = @('-3') },
        @{ Exe = (Join-Path $env:LOCALAPPDATA 'Python\bin\python.exe'); Args = @() },
        @{ Exe = 'python'; Args = @() }
    )
    foreach ($c in $candidates) {
        if (-not (Get-Command $c.Exe -ErrorAction SilentlyContinue)) { continue }
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = & $c.Exe @($c.Args + @('-c', 'import sys; print(sys.version_info >= (3, 10))')) 2>$null
        $ErrorActionPreference = $prev
        if (("$out").Trim() -eq 'True') { $python = $c.Exe; $pythonArgs = $c.Args; break }
    }
    if (-not $python) { throw 'Python 3.10 or newer was not found. Install it from https://www.python.org/downloads/ and run this again.' }
    $null = Run -Exe $python -Arguments ($pythonArgs + @('--version'))

    Step 'Backend packages (Django and the rest)'
    $venvPy = Join-Path $Backend '.venv\Scripts\python.exe'
    if (-not (Test-Path $venvPy)) {
        $null = Run -Exe $python -Arguments ($pythonArgs + @('-m', 'venv', '.venv')) -WorkDir $Backend
    }
    $null = Run -Exe $venvPy -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', '--upgrade', 'pip') -WorkDir $Backend -AllowFail
    # The PostgreSQL driver and gunicorn are for the live Linux server, not this PC.
    $localRequirements = Join-Path $Backend '.venv\requirements-windows.txt'
    $requirementLines = @(Get-Content (Join-Path $Backend 'requirements.txt') | Where-Object { $_ -notmatch '^\s*(psycopg|gunicorn)' })
    [System.IO.File]::WriteAllLines($localRequirements, [string[]]$requirementLines, $Utf8)
    $null = Run -Exe $venvPy -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', '-r', $localRequirements) -WorkDir $Backend
    $null = Run -Exe $venvPy -Arguments @('-m', 'pip', 'list', '--disable-pip-version-check') -WorkDir $Backend -AllowFail

    Step 'Backend settings (.env)'
    $envFile = Join-Path $Backend '.env'
    if (-not (Test-Path $envFile)) {
        Copy-Item (Join-Path $Backend '.env.example') $envFile
        $secret = (& $venvPy -c 'import secrets; print(secrets.token_urlsafe(50))').Trim()
        Set-EnvValue $envFile 'DJANGO_SECRET_KEY' $secret
        Info 'Created backend\.env for this PC (debug mode, test payments, codes shown in the server window).'
    }
    $hosts = New-Object System.Collections.Generic.List[string]
    foreach ($h in ((Get-EnvValue $envFile 'DJANGO_ALLOWED_HOSTS') -split ',')) {
        if ($h.Trim() -and -not $hosts.Contains($h.Trim())) { $hosts.Add($h.Trim()) }
    }
    foreach ($h in @('localhost', '127.0.0.1', '10.0.2.2', $lanIp)) {
        if (-not $hosts.Contains($h)) { $hosts.Add($h) }
    }
    Set-EnvValue $envFile 'DJANGO_ALLOWED_HOSTS' ($hosts -join ',')
    Set-EnvValue $envFile 'PUBLIC_BASE_URL' ('http://' + $lanIp + ':8000')
    Info ('Allowed hosts: ' + ($hosts -join ','))

    Step 'Database and demo content'
    $null = Run -Exe $venvPy -Arguments @('manage.py', 'makemigrations', 'accounts', 'core', 'courses', 'payments', 'studycenter') -WorkDir $Backend
    $null = Run -Exe $venvPy -Arguments @('manage.py', 'migrate', '--noinput') -WorkDir $Backend
    $null = Run -Exe $venvPy -Arguments @('manage.py', 'seed_demo') -WorkDir $Backend

    Step 'Admin login for the admin panel'
    $adminFile = Join-Path $Backend 'ADMIN-LOGIN.txt'
    if (Test-Path $adminFile) {
        Info 'Admin login already created earlier (see backend\ADMIN-LOGIN.txt).'
    } else {
        $adminEmail = 'admin@learnincreation.local'
        $env:DJANGO_SUPERUSER_EMAIL = $adminEmail
        $env:DJANGO_SUPERUSER_PASSWORD = New-Password
        $env:DJANGO_SUPERUSER_NAME = 'Admin'
        $code = Run -Exe $venvPy -Arguments @('manage.py', 'createsuperuser', '--noinput') -WorkDir $Backend -AllowFail
        if ($code -eq 0) {
            $text = @(
                'LearnInCreation admin panel (on this PC only)',
                '',
                'On this PC:      http://127.0.0.1:8000/admin/',
                ('From your phone: http://' + $lanIp + ':8000/admin/  (same Wi-Fi, backend running)'),
                ('Email:    ' + $adminEmail),
                ('Password: ' + $env:DJANGO_SUPERUSER_PASSWORD),
                '',
                'Change the password in the admin panel (top right) if you like.'
            ) -join "`r`n"
            [System.IO.File]::WriteAllText($adminFile, $text + "`r`n", $Utf8)
            Info 'Admin login saved to backend\ADMIN-LOGIN.txt'
        } else {
            Info 'Could not create the admin login automatically (one may exist already).'
        }
        Remove-Item Env:DJANGO_SUPERUSER_PASSWORD -ErrorAction SilentlyContinue
    }

    Step 'Backend tests'
    $backendTests = Run -Exe $venvPy -Arguments @('manage.py', 'test', '--noinput', '-v', '2') -WorkDir $Backend -AllowFail
    if ($backendTests -eq 0) { $Summary.Add('Backend tests: all passed') } else { $Summary.Add('Backend tests: some FAILED') }

    # ------------------------------------------------------------------ 6. app
    Step 'App packages (flutter pub get)'
    $null = Run -Exe $flutter -Arguments @('pub', 'get') -WorkDir $App

    Step 'Checking the app code (flutter analyze)'
    $analyze = Run -Exe $flutter -Arguments @('analyze', '--no-fatal-infos', '--no-fatal-warnings') -WorkDir $App -AllowFail
    if ($analyze -eq 0) { $Summary.Add('App code check: no errors') } else { $Summary.Add('App code check: errors found') }

    Step 'App unit tests (flutter test)'
    $appTests = Run -Exe $flutter -Arguments @('test') -WorkDir $App -AllowFail
    if ($appTests -eq 0) { $Summary.Add('App tests: all passed') } else { $Summary.Add('App tests: some FAILED') }

    Step 'Building the APK (the first build downloads Android build parts; 10-30 minutes)'
    if (-not $ServerUrl) { $env:LI_ALLOW_CLEARTEXT = 'true' }
    $buildArgs = @('build', 'apk', '--release', ('--dart-define=API_BASE_URL=' + $baseUrl))
    if ($env:GOOGLE_SERVER_CLIENT_ID) { $buildArgs += ('--dart-define=GOOGLE_SERVER_CLIENT_ID=' + $env:GOOGLE_SERVER_CLIENT_ID) }
    $null = Run -Exe $flutter -Arguments $buildArgs -WorkDir $App
    $builtApk = Join-Path $App 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $builtApk)) { throw ('The build finished but the APK was not found at ' + $builtApk) }
    if ($ServerUrl) { $apkName = 'LearnInCreation.apk' } else { $apkName = 'LearnInCreation-WiFi-test.apk' }
    $finalApk = Join-Path $Root $apkName
    Copy-Item $builtApk $finalApk -Force
    $sizeMb = [math]::Round((Get-Item $finalApk).Length / 1MB, 1)
    Info ('APK ready: ' + $finalApk + ' (' + $sizeMb + ' MB)')
    $Summary.Add('APK: ' + $apkName + ' (' + $sizeMb + ' MB)')

    # ------------------------------------------------------------------ 7. backend server
    Step 'Starting the backend server'
    $listening = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        Info 'A server is already running on port 8000.'
    } else {
        Start-Process -FilePath (Join-Path $Root 'START-BACKEND.cmd') -WorkingDirectory $Root
        Start-Sleep -Seconds 8
    }
    foreach ($u in @('http://127.0.0.1:8000/api/health', ('http://' + $lanIp + ':8000/api/health'))) {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 15
            Info ('Health check ' + $u + ' -> ' + $r.StatusCode + ' ' + $r.Content)
        } catch {
            Info ('Health check ' + $u + ' failed: ' + $_.Exception.Message)
        }
    }
    $Summary.Add('Server: http://' + $lanIp + ':8000')

    Step 'Finished'
    foreach ($s in $Summary) { Info $s }
    Set-Status ('DONE: ' + ($Summary -join ' | '))
    exit 0
} catch {
    $message = $_.Exception.Message
    Write-Host ''
    Write-Host ('STOPPED: ' + $message) -ForegroundColor Red
    Write-Log ('STOPPED: ' + $message)
    Write-Log $_.ScriptStackTrace
    Set-Status ('FAILED: ' + $message)
    exit 1
}
