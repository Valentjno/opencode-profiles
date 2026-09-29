<#
.SYNOPSIS
    Manage multiple opencode auth profiles.

.DESCRIPTION
    PowerShell port of opencode-profiles. Keeps named snapshots beside the
    live credentials file opencode reads:

        $BASE/auth.json             live credentials (opencode reads this)
        $BASE/auth-<name>.json      one snapshot per saved profile
        $BASE/current_profile.txt   active profile name
        $BASE/last_profile.txt      previously active profile (toggle memory)

    $BASE defaults to ~/.local/share/opencode; set
    OPENCODE_PROFILE_BASE_DIR to override it.

    Requires PowerShell 5.1+ (Windows PowerShell or PowerShell 7+).
    No modules, no network use. Home-directory writes only.

    Clean-room implementation for the opencode-profiles project (MIT).
    Behavioural inspirations are credited in CITATIONS.md; no lines are
    copied from those works.

.EXAMPLE
    .\opencode-profiles.ps1
    Interactive menu.

.EXAMPLE
    .\opencode-profiles.ps1 switch personal
    Activate the saved profile "personal" (quit opencode first).

.EXAMPLE
    .\opencode-profiles.ps1 toggle work personal
    Flip between the work and personal profiles.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Trailing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:ToolVersion = '1.0.0'
$Script:HomeBase = $null
$Script:LiveFile = $null
$Script:TrackFile = $null
$Script:PrevFile = $null
$Script:SavedNames = @()
$Script:SavedTotal = 0
$Script:FiledName = ''
$Script:LiveName = ''
$Script:StateText = ''
$Script:PriorName = ''

# --------------------------------------------------------------------------- #
# Messaging (console-direct so function return values stay clean)
# --------------------------------------------------------------------------- #

function Send-Note {
    param([string]$Body = '')
    [Console]::Out.WriteLine($Body)
}

function Send-Caution {
    param([string]$Body)
    [Console]::Error.WriteLine("Warning: $Body")
}

function Stop-Failed {
    param([string]$Body)
    [Console]::Error.WriteLine("Error: $Body")
    exit 1
}

function Read-Answer {
    param([string]$Lead)
    [Console]::Out.Write($Lead)
    [Console]::Out.Flush()
    try {
        $line = [Console]::In.ReadLine()
    } catch {
        return $null
    }
    if ($null -eq $line) { return $null }
    return $line.Trim()
}

# --------------------------------------------------------------------------- #
# Locations and discovery
# --------------------------------------------------------------------------- #

function Resolve-Home {
    $custom = $env:OPENCODE_PROFILE_BASE_DIR
    if ($custom -and $custom.Trim() -ne '') {
        $Script:HomeBase = $custom.Trim()
    } else {
        $Script:HomeBase = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'opencode'))
    }
    $Script:LiveFile = Join-Path $Script:HomeBase 'auth.json'
    $Script:TrackFile = Join-Path $Script:HomeBase 'current_profile.txt'
    $Script:PrevFile = Join-Path $Script:HomeBase 'last_profile.txt'
    $Script:SavedNames = @()
    $Script:SavedTotal = 0
    $Script:FiledName = ''
    $Script:LiveName = ''
    $Script:StateText = ''
    $Script:PriorName = ''
}

function Confirm-Home {
    if (-not (Test-Path -LiteralPath $Script:HomeBase -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $Script:HomeBase -Force | Out-Null
        } catch {
            Stop-Failed "cannot create directory '$Script:HomeBase'"
        }
    }
}

function Slot-Path {
    param([string]$Tag)
    return (Join-Path $Script:HomeBase ("auth-$Tag.json"))
}

function Refresh-Saved {
    $Script:SavedNames = @()
    $Script:SavedTotal = 0
    if (-not (Test-Path -LiteralPath $Script:HomeBase -PathType Container)) {
        return
    }
    $hits = Get-ChildItem -LiteralPath $Script:HomeBase -Filter 'auth-*.json' -File `
        -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^auth-(.+)\.json$' }
    $tags = @()
    foreach ($entry in $hits) {
        $tag = $entry.Name.Substring(5, $entry.Name.Length - 10)
        if ($tag -ne '' -and $tag -notlike '*/*' -and $tag -notlike '*\*') {
            $tags += $tag
        }
    }
    $Script:SavedNames = @($tags | Sort-Object -Unique)
    $Script:SavedTotal = $Script:SavedNames.Count
}

function Read-TopLine {
    param([string]$File)
    try {
        $grab = Get-Content -LiteralPath $File -TotalCount 1 -ErrorAction Stop
    } catch {
        return ''
    }
    if ($null -eq $grab) { return '' }
    if ($grab -is [array]) {
        if ($grab.Count -eq 0) { return '' }
        $grab = $grab[0]
    }
    return ([string]$grab).Trim()
}

function Refresh-State {
    $Script:FiledName = ''
    $Script:LiveName = ''
    $Script:StateText = ''
    $Script:PriorName = ''
    if (Test-Path -LiteralPath $Script:TrackFile -PathType Leaf) {
        $Script:FiledName = Read-TopLine $Script:TrackFile
        if ($Script:FiledName -ne '' -and `
            (Test-Path -LiteralPath (Slot-Path $Script:FiledName) -PathType Leaf)) {
            $Script:LiveName = $Script:FiledName
            $Script:StateText = $Script:FiledName
        } elseif ($Script:FiledName -ne '') {
            $Script:StateText = "$Script:FiledName (profile file missing)"
        } else {
            $Script:StateText = 'unset (empty tracking file)'
        }
    } elseif (Test-Path -LiteralPath $Script:LiveFile -PathType Leaf) {
        $Script:StateText = 'unknown (auth.json exists but is not linked to a saved profile)'
    } else {
        $Script:StateText = 'unset (no auth.json)'
    }
    if (Test-Path -LiteralPath $Script:PrevFile -PathType Leaf) {
        $Script:PriorName = Read-TopLine $Script:PrevFile
    }
}

function Test-Tag {
    param([string]$Tag)
    if ([string]::IsNullOrEmpty($Tag)) {
        Send-Note 'Profile name cannot be empty.'
        return $false
    }
    if ($Tag -notmatch '^[A-Za-z0-9_-]+$') {
        Send-Note 'Profile name may only contain letters, numbers, underscores, and hyphens.'
        return $false
    }
    return $true
}

function Confirm-Prompt {
    param([string]$Question)
    $reply = Read-Answer "$Question [y/N]: "
    if ($null -eq $reply) { return $false }
    return ($reply -match '^(?i)(y|yes)$')
}

function Test-Busy {
    try {
        $running = Get-Process -Name 'opencode' -ErrorAction SilentlyContinue
        return ($null -ne $running)
    } catch {
        return $false
    }
}

# --------------------------------------------------------------------------- #
# State writers (BOM-free UTF-8, matching the sh/py tools byte for byte)
# --------------------------------------------------------------------------- #

function Write-TextPlain {
    param([string]$File, [string]$Body)
    $codec = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($File, "$Body`n", $codec)
}

function Mark-Live {
    param([string]$Tag, [string]$Older)
    if ($Older -ne '') {
        try {
            Write-TextPlain $Script:PrevFile $Older
        } catch {
            Stop-Failed 'cannot update last_profile.txt'
        }
    }
    try {
        Write-TextPlain $Script:TrackFile $Tag
    } catch {
        Stop-Failed 'cannot update current_profile.txt'
    }
}

# --------------------------------------------------------------------------- #
# Core actions
# --------------------------------------------------------------------------- #

function Enable-Saved {
    param([string]$Tag)
    $origin = Slot-Path $Tag
    if (-not (Test-Path -LiteralPath $origin -PathType Leaf)) {
        Stop-Failed "profile not found: '$Tag' (see 'list')"
    }
    if (Test-Busy) {
        Send-Caution 'opencode seems to be running; quit it first, then switch, then reopen it.'
    }
    $older = ''
    if ($Script:LiveName -ne '' -and $Script:LiveName -ne $Tag) {
        $older = $Script:LiveName
    }
    try {
        Copy-Item -LiteralPath $origin -Destination $Script:LiveFile -Force -ErrorAction Stop
    } catch {
        Stop-Failed 'cannot copy profile over auth.json'
    }
    Mark-Live $Tag $older
    $Script:LiveName = $Tag
    $Script:StateText = $Tag
    Send-Note "Switched to profile '$Tag'."
}

function Keep-Snapshot {
    param([string]$Tag)
    if (-not (Test-Path -LiteralPath $Script:LiveFile -PathType Leaf)) {
        Stop-Failed "no auth.json at '$Script:LiveFile'; log in via opencode first"
    }
    try {
        Copy-Item -LiteralPath $Script:LiveFile -Destination (Slot-Path $Tag) `
            -Force -ErrorAction Stop
    } catch {
        Stop-Failed "cannot save profile '$Tag'"
    }
    $older = ''
    if ($Script:LiveName -ne '' -and $Script:LiveName -ne $Tag) {
        $older = $Script:LiveName
    }
    Mark-Live $Tag $older
    $Script:LiveName = $Tag
    $Script:StateText = $Tag
    Send-Note "Saved current auth.json to profile '$Tag'."
}

function Drop-Saved {
    param([string]$Tag, [string]$Flag = '')
    $victim = Slot-Path $Tag
    if (-not (Test-Path -LiteralPath $victim -PathType Leaf)) {
        Stop-Failed "profile not found: '$Tag' (see 'list')"
    }
    $skip = ($Flag -eq '--yes' -or $Flag -eq '-y' -or $Flag -eq '--force')
    if (-not $skip) {
        if (-not (Confirm-Prompt "Delete profile '$Tag'?")) {
            Send-Note 'Aborted.'
            return
        }
    }
    try {
        Remove-Item -LiteralPath $victim -Force -ErrorAction Stop
    } catch {
        Stop-Failed "cannot delete profile '$Tag'"
    }
    if ($Script:LiveName -eq $Tag) {
        try {
            if (Test-Path -LiteralPath $Script:TrackFile -PathType Leaf) {
                Remove-Item -LiteralPath $Script:TrackFile -Force -ErrorAction Stop
            }
        } catch {
            Stop-Failed 'cannot update current_profile.txt'
        }
        $Script:LiveName = ''
        $Script:StateText = 'unset (active profile was deleted; auth.json left in place)'
    }
    Send-Note "Deleted profile '$Tag'."
}

function Show-Listing {
    Refresh-Saved
    Refresh-State
    Send-Note "Current profile: $Script:StateText"
    Send-Note ''
    if ($Script:SavedTotal -eq 0) {
        Send-Note "No saved profiles in $Script:HomeBase"
        Send-Note "Tip: 'save <name>' snapshots the current auth.json."
        return
    }
    Send-Note 'Available profiles:'
    foreach ($entry in $Script:SavedNames) {
        if ($entry -ceq $Script:LiveName) {
            Send-Note "  * $entry  (active)"
        } else {
            Send-Note "    $entry"
        }
    }
}

function Show-Active {
    Refresh-State
    Send-Note $Script:StateText
}

function Find-Other {
    param([string]$Skip)
    foreach ($entry in $Script:SavedNames) {
        if ($entry -ne $Skip) { return $entry }
    }
    return ''
}

function Find-Following {
    $pos = -1
    for ($k = 0; $k -lt $Script:SavedTotal; $k++) {
        if ($Script:SavedNames[$k] -ceq $Script:LiveName) { $pos = $k; break }
    }
    if ($pos -lt 0) { return $Script:SavedNames[0] }
    return $Script:SavedNames[($pos + 1) % $Script:SavedTotal]
}

function Invoke-Flip {
    param([string]$First = '', [string]$Second = '')
    if ($First -ne '' -and -not (Test-Tag $First)) { exit 1 }
    if ($Second -ne '' -and -not (Test-Tag $Second)) { exit 1 }
    Refresh-Saved
    Refresh-State

    if ($First -ne '' -and $Second -ne '') {
        if ($First -ceq $Second) { Stop-Failed 'toggle needs two different profile names' }
        if (-not (Test-Path -LiteralPath (Slot-Path $First) -PathType Leaf)) {
            Stop-Failed "profile not found: '$First' (see 'list')"
        }
        if (-not (Test-Path -LiteralPath (Slot-Path $Second) -PathType Leaf)) {
            Stop-Failed "profile not found: '$Second' (see 'list')"
        }
        if ($Script:LiveName -ceq $First) {
            Enable-Saved $Second
        } elseif ($Script:LiveName -ceq $Second) {
            Enable-Saved $First
        } else {
            Send-Note "Current profile is '$Script:StateText'; selecting '$First'."
            Enable-Saved $First
        }
        return
    }

    if ($First -ne '') {
        if (-not (Test-Path -LiteralPath (Slot-Path $First) -PathType Leaf)) {
            Stop-Failed "profile not found: '$First' (see 'list')"
        }
        if ($Script:LiveName -ceq $First) {
            $fallback = ''
            if ($Script:PriorName -ne '' -and $Script:PriorName -cne $First -and `
                (Test-Path -LiteralPath (Slot-Path $Script:PriorName) -PathType Leaf)) {
                $fallback = $Script:PriorName
            } elseif ($Script:SavedTotal -ge 2) {
                $fallback = Find-Other $First
            }
            if ($fallback -eq '') {
                Stop-Failed 'only one profile exists; nothing to toggle to'
            }
            Enable-Saved $fallback
        } else {
            Enable-Saved $First
        }
        return
    }

    if ($Script:SavedTotal -eq 0) { Stop-Failed 'no saved profiles (see: save <name>)' }
    if ($Script:SavedTotal -eq 1) {
        Send-Note "Already on profile '$($Script:SavedNames[0])'. Nothing to do."
        return
    }
    if ($Script:SavedTotal -eq 2) {
        $aim = Find-Other $Script:LiveName
        if ($aim -eq '') { Stop-Failed "unrecognized active profile '$Script:StateText'" }
        Enable-Saved $aim
        return
    }
    if ($Script:PriorName -ne '' -and $Script:PriorName -cne $Script:LiveName -and `
        (Test-Path -LiteralPath (Slot-Path $Script:PriorName) -PathType Leaf)) {
        Enable-Saved $Script:PriorName
        return
    }
    $aim = Find-Following
    if ($aim -eq '') { Stop-Failed "unrecognized active profile '$Script:StateText'" }
    Enable-Saved $aim
}

function Invoke-SwitchCli {
    param([string]$Tag)
    if ([string]::IsNullOrEmpty($Tag)) { Stop-Failed 'usage: switch <profile_name>' }
    if (-not (Test-Tag $Tag)) { exit 1 }
    Refresh-Saved
    Refresh-State
    if ($Script:LiveName -ceq $Tag) {
        Send-Note "Already on profile '$Tag'. Nothing to do."
        return
    }
    Enable-Saved $Tag
}

function Invoke-SaveCli {
    param([string]$Tag)
    if ([string]::IsNullOrEmpty($Tag)) { Stop-Failed 'usage: save <profile_name>' }
    if (-not (Test-Tag $Tag)) { exit 1 }
    Refresh-Saved
    Refresh-State
    if (Test-Path -LiteralPath (Slot-Path $Tag) -PathType Leaf) {
        if (-not (Confirm-Prompt "Profile '$Tag' already exists. Overwrite?")) {
            Send-Note 'Aborted.'
            return
        }
    }
    Keep-Snapshot $Tag
}

function Invoke-DropCli {
    param([string]$Tag, [string]$Flag = '')
    if ([string]::IsNullOrEmpty($Tag)) { Stop-Failed 'usage: delete <profile_name> [--yes]' }
    if (-not (Test-Tag $Tag)) { exit 1 }
    Refresh-Saved
    Refresh-State
    Drop-Saved $Tag $Flag
}

# --------------------------------------------------------------------------- #
# Help
# --------------------------------------------------------------------------- #

function Show-Manual {
    param([string]$Prog)
    Send-Note "opencode-profiles $Script:ToolVersion - manage multiple opencode auth profiles"
    Send-Note ''
    Send-Note 'USAGE'
    Send-Note "    $Prog [COMMAND] [ARGS]"
    Send-Note '    (no arguments)         interactive menu'
    Send-Note ''
    Send-Note 'COMMANDS'
    Send-Note '    list                   list saved profiles, marking the active one'
    Send-Note '    current                print the active profile name (or status)'
    Send-Note '    switch <name>          activate a saved profile (copies it to auth.json)'
    Send-Note '    save <name>            snapshot the current auth.json as <name>'
    Send-Note '    delete <name> [--yes]  remove a saved profile (asks first unless --yes)'
    Send-Note '    toggle [a] [b]         flip between profiles:'
    Send-Note '                             toggle a b  flip between a and b'
    Send-Note '                             toggle a    flip between current and a'
    Send-Note '                             toggle      2 profiles: flip to the other;'
    Send-Note '                                         3+: jump to most-recently-used,'
    Send-Note '                                         else next in sorted order'
    Send-Note '    -i                     force the interactive menu'
    Send-Note '    -h, --help             show this help'
    Send-Note '    -V, --version          print the version'
    Send-Note ''
    Send-Note 'Always quit opencode before switching, then reopen it afterwards.'
    Send-Note 'Set OPENCODE_PROFILE_BASE_DIR to use a different directory.'
}

# --------------------------------------------------------------------------- #
# Interactive menu
# --------------------------------------------------------------------------- #

function Show-Roster {
    $k = 1
    foreach ($entry in $Script:SavedNames) {
        if ($entry -ceq $Script:LiveName) {
            Send-Note "$k) $entry  (active)"
        } else {
            Send-Note "$k) $entry"
        }
        $k++
    }
}

function Menu-Pick {
    Refresh-Saved
    Refresh-State
    if ($Script:SavedTotal -eq 0) {
        Send-Note "No saved profiles yet; use 'save' first."
        return $false
    }
    Show-Roster
    while ($true) {
        $pick = Read-Answer "Select a profile [1-$Script:SavedTotal, q]: "
        if ($null -eq $pick -or $pick -eq 'q' -or $pick -eq 'quit') { return $false }
        if ($pick -notmatch '^[0-9]+$') {
            Send-Note 'Enter a number, or q.'
            continue
        }
        $num = 0
        if (-not [int]::TryParse($pick, [ref]$num)) {
            Send-Note 'Enter a number, or q.'
            continue
        }
        if ($num -lt 1 -or $num -gt $Script:SavedTotal) {
            Send-Note "Enter a number from 1 to $Script:SavedTotal."
            continue
        }
        Refresh-State
        Enable-Saved $Script:SavedNames[$num - 1]
        return $true
    }
    return $false
}

function Menu-Keep {
    if (-not (Test-Path -LiteralPath $Script:LiveFile -PathType Leaf)) {
        Send-Note 'No auth.json found. Nothing to save.'
        return $false
    }
    Refresh-Saved
    Refresh-State
    while ($true) {
        if ($Script:LiveName -ne '') {
            $tag = Read-Answer "Profile name [$Script:LiveName]: "
        } else {
            $tag = Read-Answer 'Profile name: '
        }
        if ($null -eq $tag -or $tag -eq 'q' -or $tag -eq 'quit') { return $false }
        if ($tag -eq '' -and $Script:LiveName -ne '') { $tag = $Script:LiveName }
        if (-not (Test-Tag $tag)) { continue }
        if (Test-Path -LiteralPath (Slot-Path $tag) -PathType Leaf) {
            $reply = Read-Answer "Profile '$tag' already exists. Overwrite? [y/N]: "
            if ($null -eq $reply -or $reply -eq 'q' -or $reply -eq 'quit') { return $false }
            if ($reply -notmatch '^(?i)(y|yes)$') { continue }
        }
        Refresh-State
        Keep-Snapshot $tag
        return $true
    }
    return $false
}

function Menu-Drop {
    Refresh-Saved
    Refresh-State
    if ($Script:SavedTotal -eq 0) {
        Send-Note 'No saved profiles yet; nothing to delete.'
        return $false
    }
    Show-Roster
    while ($true) {
        $pick = Read-Answer "Delete which profile [1-$Script:SavedTotal, q]: "
        if ($null -eq $pick -or $pick -eq 'q' -or $pick -eq 'quit') { return $false }
        if ($pick -notmatch '^[0-9]+$') {
            Send-Note 'Enter a number, or q.'
            continue
        }
        $num = 0
        if (-not [int]::TryParse($pick, [ref]$num)) {
            Send-Note 'Enter a number, or q.'
            continue
        }
        if ($num -lt 1 -or $num -gt $Script:SavedTotal) {
            Send-Note "Enter a number from 1 to $Script:SavedTotal."
            continue
        }
        Refresh-State
        Drop-Saved $Script:SavedNames[$num - 1]
        return $true
    }
    return $false
}

function Start-Table {
    while ($true) {
        Refresh-Saved
        Refresh-State
        Send-Note ''
        Send-Note '=== opencode-profiles ==='
        Send-Note "Base directory : $Script:HomeBase"
        Send-Note "Current profile: $Script:StateText"
        Send-Note ''
        Send-Note '1) Switch to a profile'
        Send-Note '2) Save current auth.json as a profile'
        Send-Note '3) Toggle between profiles'
        Send-Note '4) List all profiles'
        Send-Note '5) Delete a profile'
        Send-Note 'q) Quit'
        Send-Note ''
        $move = Read-Answer 'Choose an action [1-5, q]: '
        if ($null -eq $move) { $move = 'q' }
        Send-Note ''
        switch ($move) {
            '1' { [void](Menu-Pick) }
            '2' { [void](Menu-Keep) }
            '3' {
                try { Invoke-Flip } catch { Send-Note 'Toggle failed (see message above).' }
            }
            '4' { Show-Listing }
            '5' { [void](Menu-Drop) }
            'q' { Send-Note 'Goodbye.'; exit 0 }
            'quit' { Send-Note 'Goodbye.'; exit 0 }
            default { Send-Note 'Invalid choice. Enter 1-5 or q.' }
        }
    }
}

# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

function Send-Compat {
    param([string]$Legacy)
    Send-Caution "'$Legacy' is a compatibility alias; prefer 'opencode-profiles' (see --help)."
}

Resolve-Home
Confirm-Home

$SelfName = Split-Path -Leaf $MyInvocation.MyCommand.Name
$Verb = $null
$Extra = $null
$Third = $null
if ($Trailing -and $Trailing.Count -ge 1) { $Verb = $Trailing[0] }
if ($Trailing -and $Trailing.Count -ge 2) { $Extra = $Trailing[1] }
if ($Trailing -and $Trailing.Count -ge 3) { $Third = $Trailing[2] }

if ($SelfName -like 'opencode-switch*') {
    $restA = ''
    $restB = ''
    if ($null -eq $Verb -or $Verb -eq '' -or $Verb -eq 'toggle') {
        Send-Compat $SelfName
        if ($Verb -eq 'toggle') {
            if ($null -ne $Extra) { $restA = $Extra }
            if ($null -ne $Third) { $restB = $Third }
        }
        Invoke-Flip $restA $restB
        exit 0
    }
    if (($Verb -eq 'work' -or $Verb -eq 'personal') -and $null -eq $Extra) {
        Send-Compat $SelfName
        Invoke-SwitchCli $Verb
        exit 0
    }
    Send-Compat $SelfName
} elseif ($SelfName -like 'oc-profiles*' -or $SelfName -like 'oc-profile*') {
    Send-Compat $SelfName
}

switch ($Verb) {
    { $null -eq $_ -or $_ -eq '' } { Start-Table; break }
    '-i' { Start-Table; break }
    'list' { Show-Listing; break }
    'current' { Show-Active; break }
    'switch' { Invoke-SwitchCli $Extra; break }
    'save' { Invoke-SaveCli $Extra; break }
    'delete' { Invoke-DropCli $Extra $Third; break }
    'rm' { Invoke-DropCli $Extra $Third; break }
    'remove' { Invoke-DropCli $Extra $Third; break }
    'toggle' {
        $a = ''
        $b = ''
        if ($null -ne $Extra) { $a = $Extra }
        if ($null -ne $Third) { $b = $Third }
        Invoke-Flip $a $b
        break
    }
    '-h' { Show-Manual $SelfName; exit 0; break }
    '--help' { Show-Manual $SelfName; exit 0; break }
    'help' { Show-Manual $SelfName; exit 0; break }
    '-V' { Send-Note "opencode-profiles $Script:ToolVersion"; exit 0; break }
    '--version' { Send-Note "opencode-profiles $Script:ToolVersion"; exit 0; break }
    'version' { Send-Note "opencode-profiles $Script:ToolVersion"; exit 0; break }
    default { Stop-Failed "unknown command '$Verb' (see --help)"; break }
}
