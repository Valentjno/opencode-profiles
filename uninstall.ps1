<#
.SYNOPSIS
    Remove an install.ps1 installation. Profile data is never touched.
#>

[CmdletBinding()]
param(
    [string]$Target = (Join-Path $HOME 'bin')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Dest = Join-Path $Target 'opencode-profiles.ps1'
if (Test-Path -LiteralPath $Dest) {
    Remove-Item -LiteralPath $Dest -Force
    [Console]::Out.WriteLine("Removed: $Dest")
} else {
    [Console]::Out.WriteLine("Skip (absent): $Dest")
}
[Console]::Out.WriteLine('Profile data left intact. To also delete snapshots, see README "Uninstalling".')
