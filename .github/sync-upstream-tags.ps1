#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Push tags from the upstream remote to the fork remote.
.EXAMPLE
    .\.github\sync-upstream-tags.ps1
#>
[CmdletBinding()]
param(
    [string] $UpstreamRemote = 'upstream',
    [string] $ForkRemote = 'origin'
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

$repositoryRoot = (Invoke-Git rev-parse --show-toplevel).Trim()
Set-Location $repositoryRoot

foreach ($remote in $UpstreamRemote, $ForkRemote) {
    Invoke-Git remote get-url $remote | Out-Null
}

# Keep upstream tags separate until each one has been checked against origin.
Invoke-Git fetch --force --prune --no-tags $UpstreamRemote '+refs/tags/*:refs/lore-upstream-tags/*' | Out-Host

$upstreamRefs = @(Invoke-Git for-each-ref '--format=%(refname)' refs/lore-upstream-tags/)
if ($upstreamRefs.Count -eq 0) {
    throw "No tags were found on remote '$UpstreamRemote'."
}

$pushedCount = 0
foreach ($upstreamRef in $upstreamRefs) {
    $tagName = $upstreamRef.Substring('refs/lore-upstream-tags/'.Length)
    $upstreamObject = (Invoke-Git rev-parse $upstreamRef).Trim()
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