<#
.SYNOPSIS
    Install opencode-profiles (PowerShell edition) on Windows.

.DESCRIPTION
    Copies ps1/opencode-profiles.ps1 to a directory on your PATH
    (default: $HOME\bin as opencode-profiles.ps1), unblocks the file,
    and prints the remaining PATH / execution-policy steps.
    Profile data is never touched.

.EXAMPLE
    .\install.ps1
    Install to the default location.

.EXAMPLE
    .\install.ps1 -Target "$HOME\bin"
    Custom directory.
#>

[CmdletBinding()]
param(
    [string]$Target = (Join-Path $HOME 'bin')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src = Join-Path $Here (Join-Path 'ps1' 'opencode-profiles.ps1')
if (-not (Test-Path -LiteralPath $Src -PathType Leaf)) {
    [Console]::Error.WriteLine("Error: cannot find $Src; run from the repo root.")
    exit 1
}

if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

$Dest = Join-Path $Target 'opencode-profiles.ps1'
Copy-Item -LiteralPath $Src -Destination $Dest -Force
Unblock-File -LiteralPath $Dest -ErrorAction SilentlyContinue
[Console]::Out.WriteLine("Installed: $Dest")

$OnPath = ($env:PATH -split ';') | Where-Object { $_ -ne '' -and `
    ([IO.Path]::GetFullPath($_) -eq [IO.Path]::GetFullPath($Target)) }
if (-not $OnPath) {
    [Console]::Out.WriteLine('')
    [Console]::Out.WriteLine("Note: $Target is not on PATH. Add it once, e.g.:")
    [Console]::Out.WriteLine('  [Environment]::SetEnvironmentVariable(')
    [Console]::Out.WriteLine("    ''PATH'', `$env:PATH + '';""$Target'', ''User'')")
}

[Console]::Out.WriteLine('')
[Console]::Out.WriteLine('If Windows blocks the script, allow per-user signed scripts once:')
[Console]::Out.WriteLine('  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned')
[Console]::Out.WriteLine('')
[Console]::Out.WriteLine('Verify with: opencode-profiles.ps1 --help')
[Console]::Out.WriteLine('The Python edition (py/opencode-profiles.py) works unchanged on Windows: py opencode-profiles.py --help')
