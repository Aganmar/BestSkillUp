# BestSkillUp - Auctionator price sync
# Copies AH prices from the account with the newest Auctionator scan into your other accounts,
# then opens Battle.net. Only AUCTIONATOR_PRICE_DATABASE is touched; settings, shopping lists and
# history stay as they are. Each changed file is backed up first (Auctionator.lua.bsu-bak).

$ErrorActionPreference = 'Stop'
$enc = [System.Text.Encoding]::GetEncoding(28591)   # byte-for-byte (Latin-1)
$head = 'AUCTIONATOR_PRICE_DATABASE = {'

function Done($msg, $wait) {
    Write-Host $msg
    if ($wait) { Read-Host 'Press Enter to close' | Out-Null }
}

try {
    $forever = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $accounts = Join-Path $forever 'WTF\Account'

    $wowDir = Split-Path $forever -Parent
    if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($wowDir, [StringComparison]::OrdinalIgnoreCase) }) {
        Done 'WoW is running - close it first (it overwrites saved data when it exits). Nothing changed.' $true
        return
    }

    $files = @()
    foreach ($dir in Get-ChildItem -Path $accounts -Directory) {
        $path = Join-Path $dir.FullName 'SavedVariables\Auctionator.lua'
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $text = [System.IO.File]::ReadAllText($path, $enc)
        $s = $text.IndexOf($head)
        if ($s -lt 0) { continue }
        $m = [regex]::Match($text, '\["TimeOfLastBrowseScan"\] = (\d+)')
        $time = if ($m.Success) { [long]$m.Groups[1].Value } else { 0 }
        $files += [pscustomobject]@{ Name = $dir.Name; Path = $path; Text = $text; Time = $time }
    }

    if ($files.Count -lt 2) {
        Write-Host 'Fewer than two accounts with Auctionator data - nothing to sync.'
    } else {
        # Block of realm lines between the header line and the closing "}" line.
        function Get-Block($text) {
            $s = $text.IndexOf($head)
            $s = $text.IndexOf("`n", $s) + 1
            $e = $text.IndexOf("`n}", $s - 1) + 1
            return @($s, $e)
        }
        $realmRe = [regex]'(?m)^\["(?<realm>[^"]+)"\] = "(?<data>.*)",\r?$'

        $src = $files | Sort-Object Time -Descending | Select-Object -First 1
        $sb = Get-Block $src.Text
        $srcBody = $src.Text.Substring($sb[0], $sb[1] - $sb[0])
        $srcLines = [ordered]@{}
        foreach ($m in $realmRe.Matches($srcBody)) { $srcLines[$m.Groups['realm'].Value] = $m.Value.TrimEnd("`r") }
        $when = [DateTimeOffset]::FromUnixTimeSeconds($src.Time).LocalDateTime
        Write-Host ("Newest scan: account {0} ({1:g}), realms: {2}" -f $src.Name, $when, ($srcLines.Keys -join ', '))

        foreach ($f in $files) {
            if ($f.Path -eq $src.Path) { continue }
            if ($f.Time -ge $src.Time) { Write-Host "  $($f.Name): already newest"; continue }
            $b = Get-Block $f.Text
            $body = $f.Text.Substring($b[0], $b[1] - $b[0])
            $nl = if ($f.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
            foreach ($realm in $srcLines.Keys) {
                $line = $srcLines[$realm]
                $re = [regex]('(?m)^\["' + [regex]::Escape($realm) + '"\] = ".*",(\r?)$')
                $m = $re.Match($body)
                if ($m.Success) {
                    $body = $body.Substring(0, $m.Index) + $line + $m.Groups[1].Value + $body.Substring($m.Index + $m.Length)
                } else {
                    $body = $body + $line + $nl
                }
            }
            $new = $f.Text.Substring(0, $b[0]) + $body + $f.Text.Substring($b[1])
            if ($new -eq $f.Text) { Write-Host "  $($f.Name): already up to date"; continue }
            Copy-Item -LiteralPath $f.Path -Destination ($f.Path + '.bsu-bak') -Force
            [System.IO.File]::WriteAllText($f.Path, $new, $enc)
            Write-Host "  $($f.Name): updated ($($srcLines.Count) realm(s))"
        }
    }

    $bnet = @("${env:ProgramFiles(x86)}\Battle.net\Battle.net Launcher.exe", "${env:ProgramFiles(x86)}\Battle.net\Battle.net.exe",
              "$env:ProgramFiles\Battle.net\Battle.net Launcher.exe", "$env:ProgramFiles\Battle.net\Battle.net.exe") |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($bnet) { Start-Process -FilePath $bnet; Write-Host 'Opening Battle.net...' } else { Write-Host 'Battle.net not found - start WoW as usual.' }
    Start-Sleep -Seconds 3
} catch {
    Done ("Sync failed: " + $_.Exception.Message + "`nYour files were not changed unless listed above (backups: Auctionator.lua.bsu-bak).") $true
}
