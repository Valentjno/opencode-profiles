<#
.SYNOPSIS
    Suite for ps1/opencode-profiles.ps1. No Pester required.

.DESCRIPTION
    Runs entirely inside a throwaway OPENCODE_PROFILE_BASE_DIR, so the real
    profile directory is never touched. Needs PowerShell 5.1+.

    Run from the repo root on Windows:
        powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_ps1.ps1
    or with PowerShell 7+:
        pwsh -NoProfile -File tests/test_ps1.ps1
#>

$ErrorActionPreference = 'Stop'

$Script:Pass = 0
$Script:Fail = 0

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Tool = Join-Path $Here (Join-Path '..' 'ps1' 'opencode-profiles.ps1')
$Runner = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

function New-Scratch {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('ocp-test-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Invoke-Tool {
    param([string]$Base, [string[]]$ToolArgs, [string]$Feed = $null)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Runner
    $quoted = @()
    foreach ($a in $ToolArgs) { $quoted += ('"' + ($a -replace '"', '\"') + '"') }
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Tool`" $($quoted -join ' ')"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables['OPENCODE_PROFILE_BASE_DIR'] = $Base
    $proc = [Diagnostics.Process]::Start($psi)
    if ($null -ne $Feed) {
        $proc.StandardInput.Write($Feed)
    }
    $proc.StandardInput.Close()
    $out = $proc.StandardOutput.ReadToEnd().Trim()
    $err = $proc.StandardError.ReadToEnd().Trim()
    $proc.WaitForExit()
    return @{ Code = $proc.ExitCode; Out = $out; Err = $err }
}

function Check-Equal {
    param([string]$Label, [string]$Want, [string]$Got)
    if ($Want -ceq $Got) {
        $Script:Pass++
        [Console]::Out.WriteLine("ok   $Label")
    } else {
        $Script:Fail++
        [Console]::Out.WriteLine("FAIL $Label")
        [Console]::Out.WriteLine("     want [$Want] got [$Got]")
    }
}

function Check-Code {
    param([string]$Label, [int]$Want, [int]$Got)
    if ($Want -eq $Got) {
        $Script:Pass++
        [Console]::Out.WriteLine("ok   $Label")
    } else {
        $Script:Fail++
        [Console]::Out.WriteLine("FAIL $Label (want rc $Want, got $Got)")
    }
}

# 1. save / current / switch -------------------------------------------------
$base = New-Scratch
try {
    '{"by":"w"}' | Out-File -LiteralPath (Join-Path $base 'auth.json') -Encoding ascii -NoNewline
    $r = Invoke-Tool $base @('save', 'work')
    Check-Code 'save work rc' 0 $r.Code
    '{"by":"p"}' | Out-File -LiteralPath (Join-Path $base 'auth.json') -Encoding ascii -NoNewline
    $r = Invoke-Tool $base @('save', 'personal')
    Check-Code 'save personal rc' 0 $r.Code
    $r = Invoke-Tool $base @('current')
    Check-Equal 'current == personal' 'personal' $r.Out

    # 2. list marks active ----------------------------------------------------
    $r = Invoke-Tool $base @('list')
    if ($r.Out -match '\* personal  \(active\)' -and $r.Out -match 'work') {
        $Script:Pass++
        [Console]::Out.WriteLine('ok   list marks active')
    } else {
        $Script:Fail++
        [Console]::Out.WriteLine('FAIL list marks active')
    }

    # 3. switch copies bytes ---------------------------------------------------
    $r = Invoke-Tool $base @('switch', 'work')
    Check-Code 'switch work rc' 0 $r.Code
    $live = Get-Content -LiteralPath (Join-Path $base 'auth.json') -Raw
    Check-Equal 'live bytes after switch' '{"by":"w"}' $live.Trim()

    # 4. bare toggle flips the pair ---------------------------------------------
    $r = Invoke-Tool $base @('toggle')
    Check-Code 'toggle rc' 0 $r.Code
    $r = Invoke-Tool $base @('current')
    Check-Equal 'toggle lands personal' 'personal' $r.Out
    $r = Invoke-Tool $base @('toggle')
    $r = Invoke-Tool $base @('current')
    Check-Equal 'toggle flips back' 'work' $r.Out

    # 5. explicit pair ------------------------------------------------------------
    $r = Invoke-Tool $base @('toggle', 'work', 'personal')
    $r = Invoke-Tool $base @('current')
    Check-Equal 'pair toggle lands personal' 'personal' $r.Out

    # 6. invalid name ------------------------------------------------------------------
    $r = Invoke-Tool $base @('save', 'bad name')
    if ($r.Code -ne 0) {
        $Script:Pass++
        [Console]::Out.WriteLine('ok   invalid name rc')
    } else {
        $Script:Fail++
        [Console]::Out.WriteLine('FAIL invalid name rc')
    }

    # 7. unknown profile ------------------------------------------------------------------
    $r = Invoke-Tool $base @('switch', 'nosuch')
    if ($r.Code -ne 0 -and $r.Err -match 'Error:') {
        $Script:Pass++
        [Console]::Out.WriteLine('ok   unknown profile errors')
    } else {
        $Script:Fail++
        [Console]::Out.WriteLine('FAIL unknown profile errors')
    }

    # 8. delete ------------------------------------------------------------------
    $r = Invoke-Tool $base @('delete', 'personal', '--yes')
    Check-Code 'delete rc' 0 $r.Code
    if (-not (Test-Path -LiteralPath (Join-Path $base 'auth-personal.json'))) {
        $Script:Pass++
        [Console]::Out.WriteLine('ok   snapshot file gone')
    } else {
        $Script:Fail++
        [Console]::Out.WriteLine('FAIL snapshot file gone')
    }

    # 9. overwrite guard ------------------------------------------------------------
    '{"by":"new"}' | Out-File -LiteralPath (Join-Path $base 'auth.json') -Encoding ascii -NoNewline
    $r = Invoke-Tool $base @('save', 'work') -Feed "n`n"
    $snap = Get-Content -LiteralPath (Join-Path $base 'auth-work.json') -Raw
    Check-Equal 'overwrite declined' '{"by":"w"}' $snap.Trim()
    $r = Invoke-Tool $base @('save', 'work') -Feed "y`n"
    $snap = Get-Content -LiteralPath (Join-Path $base 'auth-work.json') -Raw
    Check-Equal 'overwrite accepted' '{"by":"new"}' $snap.Trim()

    # 10. help / version --------------------------------------------------------------
    $r = Invoke-Tool $base @('--help')
    Check-Code 'help rc' 0 $r.Code
    $r = Invoke-Tool $base @('--version')
    if ($r.Out -match '1\.0\.0') {
        $Script:Pass++
        [Console]::Out.WriteLine('ok   version string')
    } else {
        $Script:Fail++
        [Console]::Out.WriteLine('FAIL version string')
    }
} finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

[Console]::Out.WriteLine('')
[Console]::Out.WriteLine("$Script:Pass passed, $Script:Fail failed")
if ($Script:Fail -gt 0) { exit 1 }
