<#
    LearnInCreation: upload (push) this project folder to GitHub.

    Run it by double-clicking PUSH-TO-GITHUB.cmd in the project folder.
    It uses Git for Windows on this PC. The first upload opens a GitHub
    sign-in window (Git Credential Manager); after that Git remembers you.

    1. Makes this folder a Git repository (branch "main") if it is not one yet.
    2. Stops if a private file (.env, the database, the admin login, signing
       keys, the APK) is not covered by .gitignore or is already in Git.
    3. Commits the project files: app, backend, scripts, README and so on.
    4. Pushes to the GitHub repository given with -RepoUrl, or to the one
       already set as "origin" (it asks when there is none).

    Run it again any time to upload your latest changes.
    Everything it does is also saved to push-log.txt in this folder.
#>
param(
    [string]$RepoUrl = ''
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LogFile = Join-Path $Root 'push-log.txt'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($LogFile, '', $Utf8)

$FirstCommitMessage = @'
LearnInCreation app: Flutter Android app and Django backend

- app/: Flutter app (courses and lessons, study center batches and
  library seat booking, Razorpay payments, phone/email/Google sign-in)
- backend/: Django REST API and admin panel, with tests
- scripts/windows/ and the .cmd files: one-click setup, build, backend
  start and GitHub upload on Windows

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_016VkpiHf1bwTC1JLrcoC3No
'@

function Write-Log([string]$Text) {
    [System.IO.File]::AppendAllText($LogFile, $Text + "`r`n", $Utf8)
}

function Info([string]$Text) {
    Write-Host $Text
    Write-Log $Text
}

function Step([string]$Text) {
    $line = '=== ' + (Get-Date -Format 'HH:mm:ss') + '  ' + $Text
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Log ''
    Write-Log $line
}

function Invoke-Git {
    # Runs git; its output goes to the screen (unless -Quiet) and to the log. Returns the exit code.
    param([string[]]$GitArgs, [switch]$Quiet)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:GitExe @GitArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    foreach ($line in @($output)) {
        $text = [string]$line
        if (-not $Quiet) { Write-Host $text }
        Write-Log $text
    }
    return $code
}

function Get-GitText([string[]]$GitArgs) {
    # Runs git and returns its standard output as one trimmed string ('' on errors).
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:GitExe @GitArgs 2>$null
    } finally {
        $ErrorActionPreference = $previous
    }
    return ((@($output) | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

try {
    Write-Host 'LearnInCreation: uploads this project to your GitHub repository.'
    Write-Host 'Private files (.env, database, admin login, APK) stay on this PC.'

    Step 'Checking Git'
    $script:GitExe = ''
    $found = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($found) { $script:GitExe = $found.Source }
    elseif (Test-Path "$env:ProgramFiles\Git\cmd\git.exe") { $script:GitExe = "$env:ProgramFiles\Git\cmd\git.exe" }
    if (-not $script:GitExe) { throw 'Git for Windows is not installed. Install it from https://git-scm.com/download/win, then run this again.' }
    Info ('Git: ' + (Get-GitText @('--version')))
    Set-Location $Root

    $userName = Get-GitText @('config', 'user.name')
    $userEmail = Get-GitText @('config', 'user.email')
    if (-not $userName -or -not $userEmail) {
        Info 'Git does not know your name and email yet. They are shown on each commit.'
        if (-not $userName) {
            $userName = (Read-Host 'Your name').Trim()
            $null = Invoke-Git -GitArgs @('config', '--global', 'user.name', $userName)
        }
        if (-not $userEmail) {
            $userEmail = (Read-Host 'Your email (the one on your GitHub account)').Trim()
            $null = Invoke-Git -GitArgs @('config', '--global', 'user.email', $userEmail)
        }
    }
    Info ('Commits by: ' + $userName + ' <' + $userEmail + '>')

    Step 'Preparing the repository'
    if (-not (Test-Path (Join-Path $Root '.git'))) {
        if ((Invoke-Git -GitArgs @('init', '-b', 'main')) -ne 0) { throw 'git init failed.' }
    }
    $private = @('backend/.env', 'backend/db.sqlite3', 'backend/ADMIN-LOGIN.txt', 'backend/media/x.png',
                 'app/android/local.properties', 'app/android/key.properties', 'app/android/app/upload.jks',
                 'app/android/app/release.jks', 'PRODUCTION-SECRETS.txt', 'PRODUCTION-KEYSTORE-BASE64.txt',
                 'LearnInCreation-WiFi-test.apk', 'setup-log.txt')
    foreach ($p in $private) {
        if ((Invoke-Git -GitArgs @('check-ignore', '-q', '--no-index', '--', $p) -Quiet) -ne 0) {
            throw ('Safety stop: ' + $p + ' is not covered by .gitignore, so it could be uploaded. Nothing was uploaded.')
        }
        if ((Invoke-Git -GitArgs @('ls-files', '--error-unmatch', '--', $p) -Quiet) -eq 0) {
            throw ('Safety stop: ' + $p + ' is already in Git. Remove it with "git rm --cached ' + $p + '" first. Nothing was uploaded.')
        }
    }
    Info 'Private files are excluded.'

    $paths = @('.gitignore', '.gitattributes', 'README.md', 'render.yaml', 'SETUP-AND-BUILD-ON-WINDOWS.cmd',
               'START-BACKEND.cmd', 'PUSH-TO-GITHUB.cmd', 'PREPARE-PRODUCTION.cmd', 'scripts', 'app', 'backend', '.github')
    $present = @($paths | Where-Object { Test-Path (Join-Path $Root $_) })
    if ((Invoke-Git -GitArgs (@('add', '-A', '--') + $present) -Quiet) -ne 0) { throw 'git add failed. See push-log.txt.' }
    $staged = @((Get-GitText @('diff', '--cached', '--name-only')) -split "`n" | Where-Object { $_ })
    Info ('Files with changes to commit: ' + $staged.Count)
    foreach ($f in $staged) { Write-Log ('  ' + $f) }

    $hasCommits = (Invoke-Git -GitArgs @('rev-parse', '--verify', '-q', 'HEAD') -Quiet) -eq 0
    # An optional commit-message.txt in this folder (never uploaded) sets the message of the next commit.
    $customMessage = Join-Path $Root 'commit-message.txt'
    if ($staged.Count -gt 0) {
        if (Test-Path $customMessage) {
            $code = Invoke-Git -GitArgs @('commit', '-q', '-F', $customMessage)
        } elseif ($hasCommits) {
            $code = Invoke-Git -GitArgs @('commit', '-q', '-m', ('Update LearnInCreation app (' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ')'))
        } else {
            $messageFile = Join-Path $env:TEMP 'learnincreation-first-commit.txt'
            [System.IO.File]::WriteAllText($messageFile, $FirstCommitMessage.Replace("`r`n", "`n"), $Utf8)
            $code = Invoke-Git -GitArgs @('commit', '-q', '-F', $messageFile)
            Remove-Item $messageFile -Force -ErrorAction SilentlyContinue
        }
        if ($code -ne 0) { throw 'git commit failed. See push-log.txt.' }
        Info ('Committed: ' + (Get-GitText @('log', '-1', '--format=%h %s')))
    } elseif (-not $hasCommits) {
        throw 'There are no project files to commit.'
    } else {
        Info 'No new changes since the last commit.'
    }
    Remove-Item $customMessage -Force -ErrorAction SilentlyContinue

    Step 'Connecting to GitHub'
    $origin = Get-GitText @('remote', 'get-url', 'origin')
    if (-not $RepoUrl) { $RepoUrl = $origin }
    if (-not $RepoUrl) { $RepoUrl = Read-Host 'Paste your GitHub repository address (like https://github.com/you/learnincreation)' }
    $RepoUrl = $RepoUrl.Trim()
    if ($RepoUrl -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?(\.git)?/?$') {
        throw ('That is not a GitHub repository address: ' + $RepoUrl)
    }
    $RepoUrl = $RepoUrl.TrimEnd('/')
    if (-not $RepoUrl.EndsWith('.git')) { $RepoUrl = $RepoUrl + '.git' }
    if (-not $origin) { $null = Invoke-Git -GitArgs @('remote', 'add', 'origin', $RepoUrl) }
    elseif ($origin -ne $RepoUrl) { $null = Invoke-Git -GitArgs @('remote', 'set-url', 'origin', $RepoUrl) }
    Info ('Repository: ' + $RepoUrl)

    Step 'Getting changes made on GitHub (for example on the website)'
    $remoteMain = Invoke-Git -GitArgs @('ls-remote', '--exit-code', '--heads', 'origin', 'main') -Quiet
    if ($remoteMain -eq 0) {
        if ((Invoke-Git -GitArgs @('fetch', 'origin', 'main')) -ne 0) { throw 'Could not read the repository on GitHub. See push-log.txt.' }
        $behind = Get-GitText @('rev-list', '--count', 'HEAD..FETCH_HEAD')
        if ($behind -match '^\d+$' -and [int]$behind -gt 0) {
            Info ('GitHub has ' + $behind + ' commit(s) that are not on this PC yet. Adding them here first...')
            if ((Invoke-Git -GitArgs @('rebase', '--autostash', 'FETCH_HEAD')) -ne 0) {
                $null = Invoke-Git -GitArgs @('rebase', '--abort') -Quiet
                throw 'The changes on GitHub clash with the changes on this PC, so nothing was uploaded. See push-log.txt.'
            }
            Info 'This PC now has the changes from GitHub as well.'
        } else {
            Info 'Nothing new on GitHub.'
        }
    } elseif ($remoteMain -eq 2) {
        Info 'The repository on GitHub is still empty.'
    } else {
        Info 'Could not check the repository on GitHub yet; the upload below will tell.'
    }

    Step 'Uploading (the first time, a GitHub sign-in window opens: choose "Sign in with your browser")'
    Write-Log 'git push -u origin main'
    & $script:GitExe push -u origin main
    $pushCode = $LASTEXITCODE
    if ($pushCode -ne 0) {
        throw ('The upload did not go through (git exit code ' + $pushCode + '). If GitHub said the repository already has files ("rejected" or "fetch first"), create a new EMPTY repository (no README, no .gitignore, no license) and run this again. If the sign-in window was closed, run this again and complete it.')
    }

    $webUrl = $RepoUrl -replace '\.git$', ''
    Step 'Done'
    Info ('Uploaded commit ' + (Get-GitText @('rev-parse', '--short', 'HEAD')) + ' to ' + $webUrl)
    Write-Log ('RESULT: OK ' + $webUrl)
} catch {
    $message = $_.Exception.Message
    Write-Host ''
    Write-Host ('Upload stopped: ' + $message) -ForegroundColor Red
    Write-Log ''
    Write-Log ('RESULT: FAILED ' + $message)
    exit 1
}
