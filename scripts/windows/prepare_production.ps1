<#
    LearnInCreation: one-time preparation for going live.

    Double-click PREPARE-PRODUCTION.cmd in the project folder. It:
      1. Creates the app's release signing key (app\android\app\release.jks) and
         app\android\key.properties, so builds are signed with YOUR key.
         Android installs an update only when it is signed with the same key,
         so keep a backup of the key forever. An existing key is never replaced.
      2. Makes a hard-to-guess admin address and a strong admin password.
      3. Writes everything to paste into GitHub and Render into
         PRODUCTION-SECRETS.txt in the project folder, and the signing key as
         text (for GitHub) into PRODUCTION-KEYSTORE-BASE64.txt. Both stay out
         of Git. Then it opens PRODUCTION-SECRETS.txt in Notepad.
#>

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$SecretsFile = Join-Path $Root 'PRODUCTION-SECRETS.txt'
$Base64File = Join-Path $Root 'PRODUCTION-KEYSTORE-BASE64.txt'
$KeyStore = Join-Path $Root 'app\android\app\release.jks'
$KeyProps = Join-Path $Root 'app\android\key.properties'
$Alias = 'learnincreation'
$Ascii = New-Object System.Text.UTF8Encoding($false)
$Alnum = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$LowerDigits = 'abcdefghijkmnpqrstuvwxyz23456789'

function New-RandomText([int]$Length, [string]$Alphabet) {
    $bytes = New-Object byte[] ($Length * 2)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    $text = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Length; $i++) {
        $value = ([int]$bytes[2 * $i] * 256) + [int]$bytes[2 * $i + 1]
        $null = $text.Append($Alphabet[$value % $Alphabet.Length])
    }
    return $text.ToString()
}

function Find-Keytool {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\keytool.exe') }
    $candidates += (Join-Path $env:USERPROFILE 'jdk-21\bin\keytool.exe')
    $candidates += "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe"
    $candidates += "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe"
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $found = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    throw 'Java keytool was not found. Run SETUP-AND-BUILD-ON-WINDOWS.cmd first (it installs Java), then run this again.'
}

function Get-NativeOutput([string]$Exe, [string[]]$Arguments) {
    # Runs a program and returns its standard output lines (standard error is ignored).
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Exe @Arguments 2>$null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) { throw ((Split-Path $Exe -Leaf) + ' failed with exit code ' + $code + '.') }
    return @($output | ForEach-Object { [string]$_ })
}

try {
    Write-Host 'LearnInCreation: release signing key and production settings.'
    Write-Host ''

    if (Test-Path $KeyStore) {
        if (Test-Path $SecretsFile) {
            if (-not (Test-Path $Base64File)) {
                [System.IO.File]::WriteAllText($Base64File, [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($KeyStore)), $Ascii)
            }
            Write-Host 'A release key already exists, so nothing was changed (app updates need that same key).' -ForegroundColor Yellow
            Write-Host 'Opening PRODUCTION-SECRETS.txt.'
            Start-Process notepad.exe -ArgumentList ('"' + $SecretsFile + '"')
            exit 0
        }
        throw ('A release key already exists (' + $KeyStore + ') but PRODUCTION-SECRETS.txt is missing. Nothing was changed: keep using that key with its original passwords.')
    }

    $keytool = Find-Keytool
    Write-Host ('keytool: ' + $keytool)

    $storePassword = New-RandomText 24 $Alnum
    $adminPassword = New-RandomText 20 $Alnum
    $adminPath = 'manage-' + (New-RandomText 10 $LowerDigits) + '/'

    Write-Host 'Creating the release signing key...'
    $null = Get-NativeOutput $keytool @('-genkeypair', '-keystore', $KeyStore, '-storetype', 'PKCS12', '-alias', $Alias,
        '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000',
        '-dname', 'CN=LearnInCreation, O=LearnInCreation, L=Rudrapur, ST=Uttarakhand, C=IN',
        '-storepass', $storePassword, '-keypass', $storePassword)
    if (-not (Test-Path $KeyStore)) { throw 'keytool did not create the key file.' }

    $properties = "storeFile=release.jks`r`nstorePassword=$storePassword`r`nkeyAlias=$Alias`r`nkeyPassword=$storePassword`r`n"
    [System.IO.File]::WriteAllText($KeyProps, $properties, $Ascii)

    $listing = Get-NativeOutput $keytool @('-list', '-v', '-keystore', $KeyStore, '-alias', $Alias, '-storepass', $storePassword)
    $sha1 = ''
    $sha256 = ''
    foreach ($line in $listing) {
        if ($line -match '^\s*SHA1:\s*(\S+)') { $sha1 = $Matches[1] }
        elseif ($line -match '^\s*SHA256:\s*(\S+)') { $sha256 = $Matches[1] }
    }
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($KeyStore))
    [System.IO.File]::WriteAllText($Base64File, $base64, $Ascii)
    $created = Get-Date -Format 'yyyy-MM-dd HH:mm'

    $lines = @(
        "LearnInCreation - production values (created $created)",
        'KEEP THIS FILE PRIVATE. It stays on this PC; .gitignore keeps it out of GitHub.',
        '',
        'BACK UP NOW: copy this file and app\android\app\release.jks to a safe place',
        '(for example Google Drive and a USB stick). Every app update must be signed',
        'with this same key; without it, students would have to uninstall and',
        'reinstall the app.',
        '',
        '========================================================================',
        '1) GitHub: github.com/imcodemaster/learn-app-releases > Settings >',
        '   Secrets and variables > Actions > "New repository secret".',
        '   Add these four secrets (name, then value):',
        '',
        'ANDROID_KEY_ALIAS',
        $Alias,
        '',
        'ANDROID_KEYSTORE_PASSWORD',
        $storePassword,
        '',
        'ANDROID_KEY_PASSWORD',
        $storePassword,
        '',
        'ANDROID_KEYSTORE_BASE64',
        '(the long text in PRODUCTION-KEYSTORE-BASE64.txt in this folder: open that',
        ' file, press Ctrl+A, then Ctrl+C, and paste it as the value)',
        '',
        'Then: Actions tab > "Build and publish the app" > "Run workflow".',
        '',
        '========================================================================',
        '2) Render: the values Render asks for when you create the Blueprint',
        '',
        "ADMIN_URL            $adminPath",
        'ADMIN_EMAIL          (your email address; you sign in to the admin panel with it)',
        "ADMIN_PASSWORD       $adminPassword",
        'EMAIL_HOST           smtp.gmail.com for Gmail, or your mail host',
        'EMAIL_HOST_USER      (the mailbox address that sends password-reset emails)',
        'EMAIL_HOST_PASSWORD  (Gmail: an app password; otherwise the mailbox password)',
        'DEFAULT_FROM_EMAIL   LearnInCreation <the same mailbox address>',
        '',
        "Live admin panel, once DNS is set up: https://api.learnincreation.com/$adminPath",
        '',
        '========================================================================',
        '3) Release key fingerprints (needed later for Google sign-in: Google Cloud',
        '   console > Credentials > Android OAuth client)',
        '',
        "SHA-1:    $sha1",
        "SHA-256:  $sha256"
    )
    [System.IO.File]::WriteAllText($SecretsFile, (($lines -join "`r`n") + "`r`n"), $Ascii)

    Write-Host ''
    Write-Host 'Done.' -ForegroundColor Green
    Write-Host ('  Release key:     ' + $KeyStore)
    Write-Host ('  Values to paste: ' + $SecretsFile)
    Write-Host ('  Key as text:     ' + $Base64File)
    Write-Host 'Back up release.jks and PRODUCTION-SECRETS.txt now. Opening PRODUCTION-SECRETS.txt...'
    Start-Process notepad.exe -ArgumentList ('"' + $SecretsFile + '"')
} catch {
    Write-Host ''
    Write-Host ('Stopped: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
