#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Push tags for published upstream GitHub releases to the fork remote.
.DESCRIPTION
    Requires the GitHub CLI (gh) to list published releases.
.EXAMPLE
    .\.github\sync-upstream-tags.ps1
#>
[CmdletBinding()]
param(
    [string] $UpstreamRemote = 'upstream',
    [string] $ForkRemote = 'origin',
    [string] $UpstreamRepository = 'EpicGames/lore'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)

    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
    return $output
}

function Invoke-Gh {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)

    $output = & gh @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
    return $output
}

$repositoryRoot = (Invoke-Git rev-parse --show-toplevel).Trim()
Set-Location $repositoryRoot

foreach ($remote in $UpstreamRemote, $ForkRemote) {
    Invoke-Git remote get-url $remote | Out-Null
}

# GitHub's releases API excludes drafts; select stable releases only.
$releaseTags = @(
    Invoke-Gh api --paginate "repos/$UpstreamRepository/releases" --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' |
        ForEach-Object { "$_".Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique
)
if ($releaseTags.Count -eq 0) {
    throw "No published stable releases were found in '$UpstreamRepository'."
}

# Keep upstream tags separate until each release tag has been checked against the fork.
Invoke-Git fetch --force --prune --no-tags $UpstreamRemote '+refs/tags/*:refs/lore-upstream-tags/*' | Out-Host

$pushedCount = 0
foreach ($tagName in $releaseTags) {
    $upstreamRef = "refs/lore-upstream-tags/$tagName"
    $upstreamObjectOutput = & git rev-parse --verify --quiet $upstreamRef
    if ($LASTEXITCODE -ne 0) {
        throw "Release tag '$tagName' was not found on remote '$UpstreamRemote'."
    }
    $upstreamObject = ($upstreamObjectOutput | Select-Object -First 1).Trim()
    $existingTag = @(Invoke-Git ls-remote --refs $ForkRemote "refs/tags/$tagName")

    if ($existingTag.Count -eq 0) {
        Invoke-Git push $ForkRemote "${upstreamRef}:refs/tags/$tagName" | Out-Host
        $pushedCount++
        continue
    }

    $forkObject = ($existingTag[0] -split '\s+')[0]
    if ($forkObject -ne $upstreamObject) {
        throw "Tag '$tagName' exists on '$ForkRemote' with a different object; refusing to overwrite it."
    }

    Write-Host "Tag '$tagName' is already synchronized."
}

Write-Host "Synchronized $pushedCount new tag(s) from '$UpstreamRemote' to '$ForkRemote'."