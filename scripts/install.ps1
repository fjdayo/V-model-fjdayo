#requires -Version 7.0
<#
Install the /vmodel command, skills and review agents into Claude Code (~/.claude).
Run with -Check for a read-only preview. Pass -Codex to also sync into Codex (~/.codex).
#>
[CmdletBinding()]
param([switch]$Check, [switch]$Codex)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$claudeRoot = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $env:USERPROFILE '.claude' }

function Copy-Item-Tracked([string]$Source, [string]$Destination) {
    $exists = Test-Path -LiteralPath $Destination -PathType Leaf
    if ($exists -and (Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Destination).Hash) {
        Write-Output "  current   $Destination"; return
    }
    $verb = if ($exists) { 'overwrite' } else { 'add' }
    if ($Check) { Write-Output "  would $verb $Destination"; return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Output "  $verb    $Destination"
}

Write-Output 'Commands:'
foreach ($file in Get-ChildItem (Join-Path $repoRoot 'commands') -Filter '*.md' -File) {
    Copy-Item-Tracked $file.FullName (Join-Path $claudeRoot "commands\$($file.Name)")
}

Write-Output 'Agents:'
foreach ($file in Get-ChildItem (Join-Path $repoRoot 'agents') -Filter '*.md' -File) {
    Copy-Item-Tracked $file.FullName (Join-Path $claudeRoot "agents\$($file.Name)")
}

Write-Output 'Skills:'
foreach ($directory in Get-ChildItem (Join-Path $repoRoot 'skills') -Directory) {
    Copy-Item-Tracked (Join-Path $directory.FullName 'SKILL.md') (Join-Path $claudeRoot "skills\$($directory.Name)\SKILL.md")
}

if ($Codex) {
    Write-Output 'Codex sync:'
    $sync = Join-Path $PSScriptRoot 'sync-claude-skills.ps1'
    if ($Check) { & $sync -Check } else { & $sync }
}

if ($Check) { Write-Output "`nPreview only. Re-run without -Check to apply." }
