# RustDesk automated host deployment (Windows)

param (
    [string]$DeployToken = "{{.DeployToken}}",
    [string]$ApiUrl = "{{.ApiUrl}}",
    [string]$IdServer = "{{.IdServer}}",
    [string]$RelayServer = "{{.RelayServer}}",
    [string]$Key = "{{.Key}}",
    [string]$ConfigString = "{{.ConfigString}}",
    [string]$PasswordMode = "{{.PasswordMode}}",
    [string]$CustomPassword = "{{.CustomPassword}}"
)

$ErrorActionPreference = "Stop"
$logPath = Join-Path $env:TEMP "rustdesk-deploy.log"
function Write-DeployLog($message) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function Stop-RustDeskRuntime {
    Write-DeployLog "Stopping RustDesk service and processes."
    Stop-Service -Name "rustdesk" -ErrorAction SilentlyContinue
    Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Test-RustDeskServiceInstalled {
    return $null -ne (Get-Service -Name "rustdesk" -ErrorAction SilentlyContinue)
}

function Install-RustDeskServiceIfNeeded {
    param([string]$Exe)
    if (Test-RustDeskServiceInstalled) {
        return $true
    }
    Write-Host "Installing RustDesk Windows service..." -ForegroundColor Yellow
    Write-DeployLog "Running rustdesk --install-service"
    try {
        $proc = Start-Process -FilePath $Exe -ArgumentList "--install-service" -Wait -PassThru -WindowStyle Hidden
        Write-DeployLog "rustdesk --install-service exit code: $($proc.ExitCode)"
    } catch {
        Write-DeployLog "rustdesk --install-service failed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 5
    return (Test-RustDeskServiceInstalled)
}

function Test-RustDeskIpcPipeReady {
    return Test-Path "\\.\pipe\RustDesk\query"
}

function Wait-RustDeskIpcReady {
    param([int]$MaxAttempts = 30)
    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        if (Test-RustDeskIpcPipeReady) {
            return $true
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Start-RustDeskServerProcessIfNeeded {
    param([string]$Exe)
    if (Test-RustDeskIpcPipeReady) {
        return
    }
    Write-DeployLog "Starting rustdesk --server for IPC."
    Write-Host " -> Starting RustDesk server process for IPC..." -ForegroundColor Yellow
    Start-Process -FilePath $Exe -ArgumentList "--server" -WindowStyle Hidden | Out-Null
    if (-not (Wait-RustDeskIpcReady)) {
        Write-Error "RustDesk IPC pipe is not available. Install the Windows service or start RustDesk before setting password."
        exit 1
    }
}

function Ensure-RustDeskIpcReady {
    param([string]$Exe)

    if (Test-RustDeskIpcPipeReady) {
        return
    }

    $serviceInstalled = Install-RustDeskServiceIfNeeded -Exe $Exe
    if ($serviceInstalled) {
        Write-DeployLog "Starting RustDesk Windows service."
        try {
            $svc = Get-Service -Name "rustdesk" -ErrorAction Stop
            if ($svc.Status -ne "Running") {
                Start-Service -Name "rustdesk" -ErrorAction Stop
            }
            Start-Sleep -Seconds 5
            if (Wait-RustDeskIpcReady) {
                return
            }
            Write-DeployLog "RustDesk service is running but IPC pipe is not ready yet."
        } catch {
            Write-DeployLog "Failed to start RustDesk service: $($_.Exception.Message)"
        }
    }

    Start-RustDeskServerProcessIfNeeded -Exe $Exe
}

function Start-RustDeskRuntime {
    param([string]$Exe = $rustdeskExe)
    Ensure-RustDeskIpcReady -Exe $Exe
}

function Get-RustDeskHostOptionPolicy {
    return [ordered]@{
        "verification-method" = "use-permanent-password"
        "approve-mode" = "password"
        "allow-logon-screen-password" = "Y"
        "allow-auto-update" = "Y"
    }
}

function Set-RustDeskHostOptions {
    param([string]$Exe)

    Ensure-RustDeskIpcReady -Exe $Exe
    $policy = Get-RustDeskHostOptionPolicy
    foreach ($entry in $policy.GetEnumerator()) {
        $output = (& $Exe --option $entry.Key $entry.Value 2>&1 | Out-String).Trim()
        if ($output) {
            Write-DeployLog "rustdesk --option $($entry.Key) output: $output"
        }
        Write-DeployLog "Host option applied: $($entry.Key)=$($entry.Value)"
    }
}

function Set-RustDeskPermanentPassword {
    param(
        [string]$Exe,
        [string]$Password
    )

    Ensure-RustDeskIpcReady -Exe $Exe

    $lastOutput = ""
    for ($i = 0; $i -lt 10; $i++) {
        $lastOutput = (& $Exe --password "$Password" 2>&1 | Out-String).Trim()
        Write-DeployLog "rustdesk --password attempt $($i + 1): $lastOutput"
        if ($lastOutput -match 'Done') {
            return
        }
        if ($lastOutput -match 'Installation and administrative privileges required') {
            Write-Error "Deploy script must run in an elevated Administrator PowerShell session to set permanent password."
            exit 1
        }
        if ($lastOutput -match 'cannot find the file|os error 2') {
            Ensure-RustDeskIpcReady -Exe $Exe
        }
        Start-Sleep -Seconds 2
    }

    Write-Error "Failed to set permanent password. Output: $lastOutput"
    exit 1
}

function Get-RustDeskDeviceId {
    param([string]$Exe)

    # Windows GUI build often does not print to the interactive console; capture via Out-String.
    try {
        $out = (& $Exe --get-id 2>&1 | Out-String).Trim()
        if ($out -match '(\d{9,})') {
            return $Matches[1]
        }
    } catch {}

    # Fallback: redirect stdout to a temp file (works in cmd-style capture).
    $tmp = Join-Path $env:TEMP "rustdesk-get-id.txt"
    try {
        cmd /c "`"$Exe`" --get-id > `"$tmp`" 2>&1"
        if (Test-Path $tmp) {
            $fileOut = (Get-Content $tmp -Raw -ErrorAction SilentlyContinue)
            if ($fileOut -match '(\d{9,})') {
                return $Matches[1]
            }
        }
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }

    # Fallback: newer builds may copy ID to clipboard.
    try {
        & $Exe --get-id 2>&1 | Out-Null
        Start-Sleep -Milliseconds 800
        $clip = Get-Clipboard -ErrorAction SilentlyContinue
        if ($clip -and "$clip" -match '^\d{9,}$') {
            return "$clip".Trim()
        }
    } catch {}

    # Fallback: read plaintext id from local config if present.
    $configPaths = @(
        "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml",
        "C:\Windows\System32\config\systemprofile\AppData\Roaming\RustDesk\config\RustDesk.toml",
        "$env:APPDATA\RustDesk\config\RustDesk.toml"
    )
    foreach ($tomlPath in $configPaths) {
        if (-not (Test-Path $tomlPath)) { continue }
        $content = Get-Content $tomlPath -Raw -ErrorAction SilentlyContinue
        if ($content -match "id\s*=\s*'(\d+)'") { return $Matches[1] }
        if ($content -match 'id\s*=\s*"(\d+)"') { return $Matches[1] }
    }

    return ""
}

function Normalize-RustDeskHost {
    param([string]$Value)
    $v = $Value.Trim()
    if ($v -match '^(.+):21116$') { return $Matches[1] }
    if ($v -match '^(.+):21117$') { return $Matches[1] }
    if ($v -match '^([^:]+):\d+$') { return $Matches[1] }
    return $v
}

function Get-RustDeskTomlValue {
    param(
        [string]$Content,
        [string]$Name
    )
    if ($Content -match "(?m)^\s*$([regex]::Escape($Name))\s*=\s*'([^']*)'") {
        return $Matches[1]
    }
    if ($Content -match "(?m)^\s*$([regex]::Escape($Name))\s*=\s*`"([^`"]*)`"") {
        return $Matches[1]
    }
    return ""
}

function Test-RustDeskTomlContent {
    param(
        [string]$Content,
        [string]$ExpectedHost,
        [string]$ExpectedRelay,
        [string]$ExpectedApi,
        [string]$ExpectedKey
    )

    $actualHost = Get-RustDeskTomlValue -Content $Content -Name "custom-rendezvous-server"
    $actualRelay = Get-RustDeskTomlValue -Content $Content -Name "relay-server"
    $actualApi = (Get-RustDeskTomlValue -Content $Content -Name "api-server").TrimEnd('/')
    $actualKey = Get-RustDeskTomlValue -Content $Content -Name "key"
    $actualRendezvous = Get-RustDeskTomlValue -Content $Content -Name "rendezvous_server"

    $hostOk = ($actualHost -eq $ExpectedHost)
    $relayOk = ($actualRelay -eq $ExpectedRelay)
    $apiOk = ($actualApi -eq $ExpectedApi)
    $keyOk = ($actualKey -eq $ExpectedKey)
    $rendezvousOk = ($actualRendezvous -eq "$ExpectedHost`:21116") -or ($actualRendezvous -eq $ExpectedHost)

    return [PSCustomObject]@{
        Passed = ($hostOk -and $relayOk -and $apiOk -and $keyOk)
        HostOk = $hostOk
        RelayOk = $relayOk
        ApiOk = $apiOk
        KeyOk = $keyOk
        RendezvousOk = $rendezvousOk
        ActualHost = $actualHost
        ActualRelay = $actualRelay
        ActualApi = $actualApi
        ActualKey = $actualKey
        ActualRendezvous = $actualRendezvous
    }
}

function Get-RustDeskConfigPaths {
    return @(
        "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml",
        "C:\Windows\System32\config\systemprofile\AppData\Roaming\RustDesk\config\RustDesk2.toml",
        "$env:APPDATA\RustDesk\config\RustDesk2.toml"
    )
}

function Test-RustDeskConfigApplied {
    param(
        [string]$ExpectedHost,
        [string]$ExpectedRelay,
        [string]$ExpectedApi,
        [string]$ExpectedKey
    )

    $reports = @()
    foreach ($tomlPath in (Get-RustDeskConfigPaths)) {
        if (-not (Test-Path -LiteralPath $tomlPath -ErrorAction SilentlyContinue)) {
            $reports += [PSCustomObject]@{ Path = $tomlPath; Passed = $false; Reason = "missing" }
            continue
        }
        try {
            $content = Get-Content -LiteralPath $tomlPath -Raw -ErrorAction Stop
        } catch {
            $reports += [PSCustomObject]@{ Path = $tomlPath; Passed = $false; Reason = "unreadable: $($_.Exception.Message)" }
            continue
        }
        $result = Test-RustDeskTomlContent -Content $content -ExpectedHost $ExpectedHost -ExpectedRelay $ExpectedRelay -ExpectedApi $ExpectedApi -ExpectedKey $ExpectedKey
        $reports += [PSCustomObject]@{
            Path = $tomlPath
            Passed = $result.Passed
            Reason = if ($result.Passed) { "ok" } else { "mismatch" }
            Details = $result
        }
    }

    $checkedReports = @($reports | Where-Object { $_.Reason -ne "missing" })
    $failedReports = @($checkedReports | Where-Object { -not $_.Passed })
    $userPath = "$env:APPDATA\RustDesk\config\RustDesk2.toml"
    $userReport = $reports | Where-Object { $_.Path -eq $userPath } | Select-Object -First 1
    return [PSCustomObject]@{
        Passed = ($userReport.Passed -and $failedReports.Count -eq 0)
        Path = (($checkedReports | ForEach-Object { $_.Path }) -join ", ")
        Details = ($checkedReports | Select-Object -Last 1).Details
        Reports = $reports
    }
}

function Test-RustDeskNetwork {
    param(
        [string]$HostName,
        [string]$ApiUrl
    )

    $checks = @()
    foreach ($port in @(21116, 21117)) {
        $ok = $false
        try {
            $ok = (Test-NetConnection -ComputerName $HostName -Port $port -WarningAction SilentlyContinue).TcpTestSucceeded
        } catch {}
        $checks += [PSCustomObject]@{ Target = "${HostName}:$port"; Passed = $ok }
    }

    $apiOk = $false
    try {
        $resp = Invoke-WebRequest -Uri "$($ApiUrl.TrimEnd('/'))/api/version" -UseBasicParsing -TimeoutSec 15
        $apiOk = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500)
    } catch {}
    $checks += [PSCustomObject]@{ Target = "$($ApiUrl.TrimEnd('/'))/api/version"; Passed = $apiOk }

    return [PSCustomObject]@{
        Passed = (($checks | Where-Object { -not $_.Passed }).Count -eq 0)
        Checks = $checks
    }
}

function Write-RustDeskConfigVerifyReport {
    param($VerifyResult)
    foreach ($report in $VerifyResult.Reports) {
        if ($report.Reason -eq "missing") {
            Write-DeployLog "Config verify: missing $($report.Path)"
            continue
        }
        if ($report.Reason -eq "unreadable") {
            Write-DeployLog "Config verify: $($report.Path) $($report.Reason)"
            continue
        }
        $d = $report.Details
        Write-DeployLog "Config verify: $($report.Path) host=$($d.ActualHost) relay=$($d.ActualRelay) api=$($d.ActualApi) rendezvous=$($d.ActualRendezvous) passed=$($report.Passed)"
    }
}

function Assert-RustDeskConfigApplied {
    param(
        [string]$ExpectedHost,
        [string]$ExpectedRelay,
        [string]$ExpectedApi,
        [string]$ExpectedKey,
        [int]$MaxAttempts = 15
    )

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        $verify = Test-RustDeskConfigApplied -ExpectedHost $ExpectedHost -ExpectedRelay $ExpectedRelay -ExpectedApi $ExpectedApi -ExpectedKey $ExpectedKey
        if ($verify.Passed) {
            Write-DeployLog "Config verified at $($verify.Path)"
            Write-Host " -> Config verified: $($verify.Path)" -ForegroundColor Green
            return $verify
        }
        Start-Sleep -Seconds 2
    }

    $final = Test-RustDeskConfigApplied -ExpectedHost $ExpectedHost -ExpectedRelay $ExpectedRelay -ExpectedApi $ExpectedApi -ExpectedKey $ExpectedKey
    Write-RustDeskConfigVerifyReport -VerifyResult $final
    $details = ($final.Reports | Where-Object { $_.Details } | Select-Object -Last 1).Details
    $msg = "RustDesk config verification failed."
    if ($details) {
        $msg += " Expected host=$ExpectedHost relay=$ExpectedRelay api=$ExpectedApi."
        $msg += " Last seen host=$($details.ActualHost) relay=$($details.ActualRelay) api=$($details.ActualApi)."
    }
    Write-Error $msg
    exit 1
}

function Test-RustDeskHostOptionsApplied {
    $policy = Get-RustDeskHostOptionPolicy
    $reports = @()
    foreach ($tomlPath in (Get-RustDeskConfigPaths)) {
        if (-not (Test-Path -LiteralPath $tomlPath -ErrorAction SilentlyContinue)) {
            $reports += [PSCustomObject]@{ Path = $tomlPath; Exists = $false; Passed = $false; Mismatches = @() }
            continue
        }

        $content = Get-Content -LiteralPath $tomlPath -Raw -ErrorAction SilentlyContinue
        $mismatches = @()
        foreach ($entry in $policy.GetEnumerator()) {
            $actual = Get-RustDeskTomlValue -Content $content -Name $entry.Key
            if ($actual -ne $entry.Value) {
                $mismatches += "$($entry.Key): expected=$($entry.Value), actual=$actual"
            }
        }
        $reports += [PSCustomObject]@{
            Path = $tomlPath
            Exists = $true
            Passed = ($mismatches.Count -eq 0)
            Mismatches = $mismatches
        }
    }

    $checked = @($reports | Where-Object { $_.Exists })
    $userPath = "$env:APPDATA\RustDesk\config\RustDesk2.toml"
    $userReport = $reports | Where-Object { $_.Path -eq $userPath } | Select-Object -First 1
    return [PSCustomObject]@{
        Passed = ($userReport.Passed -and @($checked | Where-Object { -not $_.Passed }).Count -eq 0)
        Reports = $reports
    }
}

function Assert-RustDeskHostOptionsApplied {
    param([int]$MaxAttempts = 15)

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        $result = Test-RustDeskHostOptionsApplied
        if ($result.Passed) {
            Write-DeployLog "Advanced host options verified."
            return
        }
        Start-Sleep -Seconds 2
    }

    $result = Test-RustDeskHostOptionsApplied
    foreach ($report in $result.Reports) {
        if (-not $report.Exists) {
            Write-DeployLog "Host option verify: missing $($report.Path)"
        } elseif (-not $report.Passed) {
            Write-DeployLog "Host option verify failed at $($report.Path): $($report.Mismatches -join '; ')"
        }
    }
    Write-Error "RustDesk advanced host option verification failed."
    exit 1
}

function Escape-RustDeskTomlSingleQuoted {
    param([string]$Value)
    return ($Value -replace "'", "''")
}

function Set-RustDeskTomlOption {
    param(
        [string]$Content,
        [string]$Key,
        [string]$Value
    )
    $escaped = Escape-RustDeskTomlSingleQuoted $Value
    $line = "$Key = '$escaped'"
    $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*=.*$"
    if ($Content -match $pattern) {
        return [regex]::Replace($Content, $pattern, $line)
    }
    if ($Content -match '(?m)^\s*\[options\]\s*$') {
        return [regex]::Replace($Content, '(?m)^\s*\[options\]\s*$', "[options]`n$line")
    }
    return ($Content.TrimEnd() + "`n`n[options]`n$line`n")
}

function Get-RustDeskLocalConfigPaths {
    return @(
        "$env:APPDATA\RustDesk\config\RustDesk_local.toml",
        "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk_local.toml"
    )
}

function Set-RustDeskClientLogin {
    param(
        [string]$AccessToken,
        [string]$UserInfoJson
    )

    $defaultToml = @"
remote_id = ''
kb_layout_type = ''
size = [
    0,
    0,
    0,
    0,
]
fav = []

[options]

[ui_flutter]
"@

    foreach ($tomlPath in (Get-RustDeskLocalConfigPaths)) {
        $parent = Split-Path -Parent $tomlPath
        if (-not (Test-Path -LiteralPath $parent -ErrorAction SilentlyContinue)) {
            try {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            } catch {
                Write-DeployLog "Client login skipped for $tomlPath : cannot create directory"
                continue
            }
        }

        $content = $defaultToml
        if (Test-Path -LiteralPath $tomlPath -ErrorAction SilentlyContinue) {
            try {
                $content = Get-Content -LiteralPath $tomlPath -Raw -ErrorAction Stop
            } catch {
                Write-DeployLog "Client login skipped for $tomlPath : unreadable"
                continue
            }
        }

        $content = Set-RustDeskTomlOption -Content $content -Key "access_token" -Value $AccessToken
        $content = Set-RustDeskTomlOption -Content $content -Key "user_info" -Value $UserInfoJson
        try {
            Set-Content -LiteralPath $tomlPath -Value $content -Encoding UTF8
            Write-DeployLog "Client login stored at $tomlPath"
            Write-Host " -> Account login stored: $tomlPath" -ForegroundColor Green
        } catch {
            Write-DeployLog "Client login failed for $tomlPath : $($_.Exception.Message)"
        }
    }
}

function Get-LatestRustDeskMsi {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    $headers = @{
        "User-Agent" = "RustDesk-Host-Deployment"
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" -Headers $headers -TimeoutSec 30 -ErrorAction Stop
        $version = ([string]$release.tag_name).Trim().TrimStart('v')
        $expectedName = "rustdesk-$version-$architecture.msi"
        $asset = $release.assets | Where-Object { $_.name -eq $expectedName -and $_.state -eq "uploaded" } | Select-Object -First 1
        if (-not $asset) {
            throw "Release $version does not contain $expectedName"
        }
        return [PSCustomObject]@{
            Version = $version
            Url = [string]$asset.browser_download_url
            FileName = $expectedName
            Size = [long]$asset.size
            Sha256 = (([string]$asset.digest) -replace '^sha256:', '').Trim()
            Source = "GitHub API"
        }
    } catch {
        Write-DeployLog "GitHub release API lookup failed: $($_.Exception.Message)"
    }

    # API rate limits or transient failures should not force a stale hard-coded
    # version. Resolve the latest release redirect and construct its MSI URL.
    try {
        $response = Invoke-WebRequest -Uri "https://github.com/rustdesk/rustdesk/releases/latest" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $releaseUrl = [string]$response.BaseResponse.ResponseUri.AbsoluteUri
        if ($releaseUrl -notmatch '/tag/([^/?#]+)') {
            throw "Cannot determine release tag from $releaseUrl"
        }
        $tag = $Matches[1]
        $version = $tag.TrimStart('v')
        $fileName = "rustdesk-$version-$architecture.msi"
        return [PSCustomObject]@{
            Version = $version
            Url = "https://github.com/rustdesk/rustdesk/releases/download/$tag/$fileName"
            FileName = $fileName
            Size = 0
            Sha256 = ""
            Source = "GitHub latest redirect"
        }
    } catch {
        Write-DeployLog "GitHub release redirect lookup failed: $($_.Exception.Message)"
        return $null
    }
}

function Install-LatestRustDeskClient {
    param([string]$Exe)

    $release = Get-LatestRustDeskMsi
    if (-not $release) {
        if (Test-Path -LiteralPath $Exe) {
            Write-Warning "Could not check the latest RustDesk release; continuing with the installed client."
            Write-DeployLog "Latest client lookup unavailable; keeping installed client."
            return
        }
        Write-Error "Could not resolve the latest RustDesk MSI from GitHub."
        exit 1
    }

    $installedVersion = ""
    if (Test-Path -LiteralPath $Exe) {
        $installedVersion = ([Diagnostics.FileVersionInfo]::GetVersionInfo($Exe).ProductVersion -split '[ +]')[0]
    }
    Write-DeployLog "Latest RustDesk client=$($release.Version) source=$($release.Source) installed=$installedVersion"
    $sameVersion = $installedVersion -match ("^" + [regex]::Escape($release.Version) + "(?:\.0)*$")
    if ($sameVersion) {
        Write-Host " -> RustDesk $installedVersion is already current." -ForegroundColor Green
        return
    }

    $tempMsi = Join-Path $env:TEMP $release.FileName
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $tempMsi -Force -ErrorAction SilentlyContinue
            Write-DeployLog "Downloading RustDesk $($release.Version), attempt ${attempt}: $($release.Url)"
            Invoke-WebRequest -Uri $release.Url -OutFile $tempMsi -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
            break
        } catch {
            Write-DeployLog "RustDesk download attempt $attempt failed: $($_.Exception.Message)"
            if ($attempt -eq 3) { throw }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }

    if ($release.Size -gt 0 -and (Get-Item -LiteralPath $tempMsi).Length -ne $release.Size) {
        Write-Error "Downloaded RustDesk MSI size does not match GitHub metadata."
        exit 1
    }
    if ($release.Sha256) {
        $actualHash = (Get-FileHash -LiteralPath $tempMsi -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $release.Sha256.ToLowerInvariant()) {
            Write-Error "Downloaded RustDesk MSI SHA-256 does not match GitHub metadata."
            exit 1
        }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $tempMsi
    if ($signature.Status -ne "Valid") {
        Write-Error "Downloaded RustDesk MSI signature is not valid: $($signature.Status)"
        exit 1
    }

    Stop-RustDeskRuntime
    Write-Host "[1/8] Installing RustDesk $($release.Version)..." -ForegroundColor Yellow
    $install = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tempMsi`" /qn /norestart" -Wait -PassThru -WindowStyle Hidden
    Write-DeployLog "RustDesk MSI exit code: $($install.ExitCode)"
    if ($install.ExitCode -notin @(0, 1641, 3010)) {
        Write-Error "RustDesk MSI installation failed with exit code $($install.ExitCode)."
        exit 1
    }

    for ($i = 0; $i -lt 30; $i++) {
        if (Test-Path -LiteralPath $Exe) { break }
        Start-Sleep -Seconds 2
    }
    if (-not (Test-Path -LiteralPath $Exe)) {
        Write-Error "RustDesk installation completed but rustdesk.exe was not found."
        exit 1
    }
    Write-DeployLog "RustDesk $($release.Version) installed. RebootRequired=$($install.ExitCode -in @(1641, 3010))"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  RUSTDESK AUTOMATED HOST DEPLOYMENT SCRIPT (WINDOWS)     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Deploy log: $logPath" -ForegroundColor Cyan
Write-DeployLog "Starting RustDesk deployment."
Write-DeployLog "UserName=$env:USERNAME ApiUrl=$ApiUrl ConfigLength=$($ConfigString.Length)"

$expectedHost = Normalize-RustDeskHost $IdServer
$expectedRelay = Normalize-RustDeskHost $(if ($RelayServer) { $RelayServer } else { $IdServer })
$expectedApi = $ApiUrl.TrimEnd('/')
$expectedKey = $Key.Trim()
Write-DeployLog "Expected host=$expectedHost relay=$expectedRelay api=$expectedApi"

if (-not $DeployToken) {
    Write-Error "Deploy token is missing. Generate a new command from Web Admin."
    exit 1
}
if (-not $ConfigString) {
    Write-Error "Server config string is missing. Regenerate deploy command from Web Admin."
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Run PowerShell as Administrator."
    exit 1
}

$rustdeskExe = "C:\Program Files\RustDesk\rustdesk.exe"
Install-LatestRustDeskClient -Exe $rustdeskExe

Install-RustDeskServiceIfNeeded -Exe $rustdeskExe

Stop-RustDeskRuntime

Write-Host "[2/8] Applying server config..." -ForegroundColor Yellow
# RustDesk's documented Windows deployment flow applies --config while the
# service is running. This lets the CLI update the service-owned configuration
# through IPC instead of writing only to the interactive user's profile.
Start-RustDeskRuntime
Write-DeployLog "Running rustdesk --config"
$configOutput = (& $rustdeskExe --config $ConfigString 2>&1 | Out-String).Trim()
if ($configOutput) {
    Write-DeployLog "rustdesk --config output: $configOutput"
}
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Warning "rustdesk --config exit code: $LASTEXITCODE"
}

Write-Host "[3/8] Verifying server config..." -ForegroundColor Yellow
$null = Assert-RustDeskConfigApplied -ExpectedHost $expectedHost -ExpectedRelay $expectedRelay -ExpectedApi $expectedApi -ExpectedKey $expectedKey
$network = Test-RustDeskNetwork -HostName $expectedHost -ApiUrl $expectedApi
foreach ($check in $network.Checks) {
    $status = if ($check.Passed) { "ok" } else { "failed" }
    Write-DeployLog "Network verify $($check.Target): $status"
    if (-not $check.Passed) {
        Write-Warning "Network check failed: $($check.Target)"
    }
}
if (-not $network.Passed) {
    Write-Warning "Some network checks failed. Deployment continues, but remote access may not work until ports/API are reachable."
}

Write-Host "[4/8] Reading device ID..." -ForegroundColor Yellow
$id = ""
for ($i = 0; $i -lt 30; $i++) {
    $id = Get-RustDeskDeviceId -Exe $rustdeskExe
    if ($id) { break }
    Start-Sleep -Seconds 2
}
if (-not $id) {
    Write-Error "Cannot read device ID from RustDesk CLI."
    exit 1
}
Write-DeployLog "Device ID: $id"

$cleanApiUrl = $ApiUrl.TrimEnd('/')
$headers = @{
    "Authorization" = "Bearer $DeployToken"
    "Content-Type"  = "application/json"
}

Write-Host "[5/8] Registering device with API..." -ForegroundColor Yellow
$deployBody = @{ id = $id } | ConvertTo-Json
$deployResponse = Invoke-RestMethod -Uri "$cleanApiUrl/api/devices/deploy" -Method Post -Headers $headers -Body $deployBody
if ($deployResponse.result -ne "OK") {
    Write-Error "Device deploy failed: $($deployResponse | ConvertTo-Json -Compress)"
    exit 1
}

Write-Host "[6/8] Setting host password..." -ForegroundColor Yellow
if ($PasswordMode -eq "custom" -and $CustomPassword) {
    $hostPassword = $CustomPassword
    Write-DeployLog "Setting custom host password from deploy token."
} else {
    $idTail = if ($id.Length -ge 5) { $id.Substring($id.Length - 5) } else { $id.PadLeft(5, '0') }
    $hostPassword = "Rd@$idTail"
    Write-DeployLog "Setting structured host password: $hostPassword"
}
Write-Host " -> Host password: $hostPassword" -ForegroundColor Green
Set-RustDeskPermanentPassword -Exe $rustdeskExe -Password $hostPassword
Set-RustDeskHostOptions -Exe $rustdeskExe

Write-Host "[7/8] Syncing address book..." -ForegroundColor Yellow
$deployedAt = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$deployNote = "Deploy: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$cliBody = @{
    id = $id
    address_book_name = "My Devices"
    address_book_tag = "deploy"
    address_book_password = $hostPassword
    address_book_alias = $env:COMPUTERNAME
    address_book_note = $deployNote
    deployed_at = $deployedAt
} | ConvertTo-Json
Invoke-RestMethod -Uri "$cleanApiUrl/api/devices/cli" -Method Post -Headers $headers -Body $cliBody | Out-Null

Write-Host "[8/8] Signing in RustDesk account..." -ForegroundColor Yellow
try {
    $loginBody = @{ id = $id } | ConvertTo-Json
    $loginResponse = Invoke-RestMethod -Uri "$cleanApiUrl/api/deploy/client-login" -Method Post -Headers $headers -Body $loginBody
    if ($loginResponse.type -eq "access_token" -and $loginResponse.access_token) {
        $userInfo = @{ name = $loginResponse.user.name }
        if ($loginResponse.user.email) { $userInfo.email = $loginResponse.user.email }
        $userInfoJson = ($userInfo | ConvertTo-Json -Compress)
        Set-RustDeskClientLogin -AccessToken $loginResponse.access_token -UserInfoJson $userInfoJson
        Write-Host " -> RustDesk account auto-login configured." -ForegroundColor Green
        Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process -FilePath $rustdeskExe
        Write-DeployLog "RustDesk UI restarted to apply account login."
    } else {
        Write-Warning "Client auto-login skipped: unexpected API response."
        Write-DeployLog "Client auto-login skipped: unexpected API response."
    }
} catch {
    Write-Warning "Client auto-login failed: $($_.Exception.Message)"
    Write-DeployLog "Client auto-login failed: $($_.Exception.Message)"
}

# UI startup triggers config synchronization. Verify again after that sync so
# deployment cannot report success when a service profile overwrites the server.
Start-Sleep -Seconds 5
Write-Host "[8/8] Verifying persisted server config..." -ForegroundColor Yellow
$null = Assert-RustDeskConfigApplied -ExpectedHost $expectedHost -ExpectedRelay $expectedRelay -ExpectedApi $expectedApi -ExpectedKey $expectedKey
Assert-RustDeskHostOptionsApplied

try {
    Invoke-RestMethod -Uri "$cleanApiUrl/api/deploy/revoke" -Method Post -Headers $headers -Body "{}" | Out-Null
} catch {}

Write-Host "Deployment completed successfully." -ForegroundColor Green
Write-Host "Device ID: $id" -ForegroundColor Green
Write-DeployLog "Deployment completed successfully."
