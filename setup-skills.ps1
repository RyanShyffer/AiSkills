<#
.SYNOPSIS
    Junctions every skill folder in this repo into ~/.claude/skills.

.DESCRIPTION
    Run after cloning (or pulling new skills) to make Claude Code pick them
    up. Existing junctions/items at the destination are left alone unless
    -Force is passed.
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$repoRoot = $PSScriptRoot
$skillsDir = Join-Path $env:USERPROFILE ".claude\skills"

if (-not (Test-Path $skillsDir)) {
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
}

Get-ChildItem -Path $repoRoot -Directory | ForEach-Object {
    $linkPath = Join-Path $skillsDir $_.Name

    if (Test-Path $linkPath) {
        if ($Force) {
            Remove-Item -Path $linkPath -Recurse -Force
        }
        else {
            Write-Host "Skipping $($_.Name) - already exists at $linkPath (use -Force to relink)"
            return
        }
    }

    New-Item -ItemType Junction -Path $linkPath -Target $_.FullName | Out-Null
    Write-Host "Linked $($_.Name)"
}
