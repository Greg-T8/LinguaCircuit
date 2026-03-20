<#
.SYNOPSIS
Build the daily due queue from learner state.

.DESCRIPTION
Reads all item-state files for a learner, filters to items due today or earlier,
priority-sorts them (missed > shaky > learning > new), limits to the daily target
from the learner profile, loads full item definitions, and writes a combined
due-queue JSON to the derived/due-queues folder.

.CONTEXT
LinguaCircuit — Vocabulary & Idiom Learning System (Phase 1 MVP)

.AUTHOR
Greg Tate

.NOTES
Program: Get-DueItems.ps1
#>

[CmdletBinding()]
param(
    [string]$LearnerId = 'greg',

    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [string]$DateOverride
)

# Configuration
$StatusPriority = @{
    'shaky'    = 1
    'learning' = 2
    'new'      = 3
    'mastered' = 4
}

$Main = {
    . $Helpers

    $today = Get-EffectiveDate
    $profile = Read-LearnerProfile
    $dueItems = Get-DueItemState -Today $today
    $prioritized = Sort-DueItem -Items $dueItems
    $limited = Limit-ToTarget -Items $prioritized -Profile $profile
    $enriched = Join-ItemDefinition -Items $limited
    Export-DueQueue -Items $enriched -Today $today
}

$Helpers = {

    function Get-EffectiveDate {
        # Determine the effective date for due-item filtering
        if ($DateOverride) {
            return [datetime]::Parse($DateOverride).Date
        }
        return (Get-Date).Date
    }

    function Read-LearnerProfile {
        # Load learner preferences and daily target configuration
        $profilePath = Join-Path $RepoRoot "data\learner-state\$LearnerId\profile.json"
        if (-not (Test-Path $profilePath)) {
            throw "Learner profile not found: $profilePath"
        }
        Get-Content $profilePath -Raw | ConvertFrom-Json
    }

    function Get-DueItemState {
        # Read all item-state files and filter to items due on or before today
        param([datetime]$Today)

        $stateDir = Join-Path $RepoRoot "data\learner-state\$LearnerId\item-state"
        if (-not (Test-Path $stateDir)) {
            throw "Item-state directory not found: $stateDir"
        }

        Get-ChildItem -Path $stateDir -Filter '*.json' |
            ForEach-Object {
                $state = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $state
            } |
            Where-Object {
                $nextDue = [datetime]::Parse($_.next_due).Date
                $nextDue -le $Today
            }
    }

    function Sort-DueItem {
        # Priority-sort items: shaky > learning > new > mastered, then by oldest due date
        param([object[]]$Items)

        $Items |
            Sort-Object @(
                @{ Expression = { $StatusPriority[$_.status] }; Ascending = $true }
                @{ Expression = { [datetime]::Parse($_.next_due) }; Ascending = $true }
            )
    }

    function Limit-ToTarget {
        # Cap the queue to the daily review + new item targets
        param(
            [object[]]$Items,
            [object]$Profile
        )

        $reviewTarget = $Profile.daily_target.review_items
        $newTarget = $Profile.daily_target.new_items

        # Split into review items and new items
        $reviewItems = @($Items | Where-Object { $_.status -ne 'new' })
        $newItems = @($Items | Where-Object { $_.status -eq 'new' })

        # Apply limits
        $selectedReview = $reviewItems | Select-Object -First $reviewTarget
        $selectedNew = $newItems | Select-Object -First $newTarget

        @($selectedReview) + @($selectedNew)
    }

    function Join-ItemDefinition {
        # Enrich each due item-state with its full item definition
        param([object[]]$Items)

        $Items | ForEach-Object {
            $state = $_
            $itemId = $state.item_id

            # Determine the item type directory from the item_id prefix
            if ($itemId -match '^vocab-') {
                $typeDir = 'vocabulary'
                $fileName = $itemId -replace '^vocab-', ''
            }
            elseif ($itemId -match '^idiom-') {
                $typeDir = 'idioms'
                $fileName = $itemId -replace '^idiom-', ''
            }
            else {
                Write-Warning "Unknown item type prefix for: $itemId"
                return
            }

            $itemPath = Join-Path $RepoRoot "data\items\$typeDir\$fileName.json"
            if (-not (Test-Path $itemPath)) {
                Write-Warning "Item definition not found: $itemPath"
                return
            }

            $definition = Get-Content $itemPath -Raw | ConvertFrom-Json

            # Combine state and definition into a single object
            [PSCustomObject]@{
                item_id         = $itemId
                status          = $state.status
                next_due        = $state.next_due
                last_reviewed   = $state.last_reviewed
                ease            = $state.ease
                stability       = $state.stability
                lapse_count     = $state.lapse_count
                recall_dimensions = $state.recall_dimensions
                definition      = $definition
            }
        }
    }

    function Export-DueQueue {
        # Write the enriched due queue to the derived/due-queues folder
        param(
            [object[]]$Items,
            [datetime]$Today
        )

        $dateStr = $Today.ToString('yyyy-MM-dd')
        $outputDir = Join-Path $RepoRoot "data\derived\due-queues"

        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $outputPath = Join-Path $outputDir "$dateStr.json"

        $queue = [PSCustomObject]@{
            generated   = (Get-Date -Format 'o')
            learner_id  = $LearnerId
            date        = $dateStr
            total_items = ($Items | Measure-Object).Count
            items       = @($Items)
        }

        $queue | ConvertTo-Json -Depth 10 | Set-Content -Path $outputPath -Encoding utf8
        Write-Host "Due queue written: $outputPath ($($queue.total_items) items)"
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
