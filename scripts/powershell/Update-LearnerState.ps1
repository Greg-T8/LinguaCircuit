<#
.SYNOPSIS
Process a session result and update learner state.

.DESCRIPTION
Accepts a session-result JSON file, validates it against the lesson-result
schema contract, updates each reviewed item's learner state (scores, status,
next due date), and writes the session to the session-history folder.
Uses rule-based interval scheduling for the MVP.

.CONTEXT
LinguaCircuit — Vocabulary & Idiom Learning System (Phase 1 MVP)

.AUTHOR
Greg Tate

.NOTES
Program: Update-LearnerState.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SessionResultPath,

    [string]$LearnerId = 'greg',

    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

# Interval rules: result → days until next review
$IntervalRules = @{
    'incorrect' = 1
    'partial'   = 2
    'correct'   = 5
}

# Status transition rules based on overall performance
$StatusRules = @{
    'all_correct' = 'mastered'
    'mixed'       = 'learning'
    'mostly_wrong' = 'shaky'
}

$Main = {
    . $Helpers

    $sessionResult = Read-SessionResult
    Confirm-SessionResult -Result $sessionResult

    foreach ($reviewed in $sessionResult.items_reviewed) {
        Update-ItemState -ReviewedItem $reviewed -SessionDate $sessionResult.session_date
    }

    Save-SessionHistory -Result $sessionResult
    Show-SessionSummary -Result $sessionResult
}

$Helpers = {

    function Read-SessionResult {
        # Load the session result JSON file
        if (-not (Test-Path $SessionResultPath)) {
            throw "Session result file not found: $SessionResultPath"
        }
        Get-Content $SessionResultPath -Raw | ConvertFrom-Json
    }

    function Confirm-SessionResult {
        # Validate required fields exist in the session result
        param([object]$Result)

        $requiredFields = @('session_id', 'learner_id', 'session_date', 'items_reviewed', 'session_summary')
        foreach ($field in $requiredFields) {
            if (-not ($Result.PSObject.Properties.Name -contains $field)) {
                throw "Session result missing required field: $field"
            }
        }

        # Validate each reviewed item has required fields
        foreach ($item in $Result.items_reviewed) {
            $itemFields = @('item_id', 'recall_result', 'usage_result', 'root_understanding', 'recommended_status', 'recommended_next_due_days', 'notes')
            foreach ($field in $itemFields) {
                if (-not ($item.PSObject.Properties.Name -contains $field)) {
                    throw "Reviewed item '$($item.item_id)' missing required field: $field"
                }
            }
        }

        Write-Verbose "Session result validation passed."
    }

    function Update-ItemState {
        # Update a single item's learner state based on session results
        param(
            [object]$ReviewedItem,
            [string]$SessionDate
        )

        $stateDir = Join-Path $RepoRoot "data\learner-state\$LearnerId\item-state"
        $statePath = Join-Path $stateDir "$($ReviewedItem.item_id).json"

        if (-not (Test-Path $statePath)) {
            Write-Warning "Item state file not found: $statePath — skipping."
            return
        }

        $state = Get-Content $statePath -Raw | ConvertFrom-Json

        # Update recall counts
        switch ($ReviewedItem.recall_result) {
            'correct'   { $state.correct_count++ }
            'partial'   { $state.partial_count++ }
            'incorrect' { $state.incorrect_count++ }
        }

        # Update recall dimensions
        $state.recall_dimensions.definition = Convert-ResultToScore -Result $ReviewedItem.recall_result
        $state.recall_dimensions.sentence_usage = Convert-ResultToScore -Result $ReviewedItem.usage_result
        $state.recall_dimensions.root_understanding = Convert-ResultToScore -Result $ReviewedItem.root_understanding

        # Determine the interval using rule-based scheduling
        $interval = Resolve-Interval -ReviewedItem $ReviewedItem -CurrentState $state

        # Update status based on the recommendation but validated against our rules
        $newStatus = Resolve-Status -ReviewedItem $ReviewedItem -CurrentState $state

        # Track lapses when status regresses
        if ((Get-StatusRank -Status $newStatus) -lt (Get-StatusRank -Status $state.status)) {
            $state.lapse_count++
        }

        # Apply updates
        $state.status = $newStatus
        $state.last_reviewed = $SessionDate
        $state.next_due = ([datetime]::Parse($SessionDate)).AddDays($interval).ToString('yyyy-MM-dd')
        $state.stability = $interval

        # Update ease factor
        $state.ease = Update-EaseFactor -CurrentEase $state.ease -RecallResult $ReviewedItem.recall_result

        # Append notes from the session
        if ($ReviewedItem.notes -and $ReviewedItem.notes.Count -gt 0) {
            $existingNotes = @()
            if ($state.notes) {
                $existingNotes = @($state.notes)
            }
            $state.notes = $existingNotes + @($ReviewedItem.notes)
        }

        # Write updated state back
        $state | ConvertTo-Json -Depth 3 | Set-Content -Path $statePath -Encoding utf8
        Write-Verbose "Updated: $($ReviewedItem.item_id) → status=$newStatus, next_due=$($state.next_due)"
    }

    function Convert-ResultToScore {
        # Map a result string to a numeric recall dimension score
        param([string]$Result)

        switch ($Result) {
            'correct'   { return 2 }
            'partial'   { return 1 }
            'incorrect' { return 0 }
            default     { return 0 }
        }
    }

    function Resolve-Interval {
        # Calculate the next review interval using rule-based scheduling
        param(
            [object]$ReviewedItem,
            [object]$CurrentState
        )

        # Use the worst result across dimensions to determine the base interval
        $results = @($ReviewedItem.recall_result, $ReviewedItem.usage_result, $ReviewedItem.root_understanding)

        if ($results -contains 'incorrect') {
            $baseInterval = $IntervalRules['incorrect']
        }
        elseif ($results -contains 'partial') {
            $baseInterval = $IntervalRules['partial']
        }
        else {
            $baseInterval = $IntervalRules['correct']
        }

        # Boost interval for repeated mastery
        if ($CurrentState.status -eq 'mastered' -and -not ($results -contains 'incorrect') -and -not ($results -contains 'partial')) {
            $baseInterval = [math]::Min(14, [math]::Max($baseInterval, $CurrentState.stability * 2))
        }

        return $baseInterval
    }

    function Resolve-Status {
        # Determine the new status based on review results and current state
        param(
            [object]$ReviewedItem,
            [object]$CurrentState
        )

        $results = @($ReviewedItem.recall_result, $ReviewedItem.usage_result, $ReviewedItem.root_understanding)
        $incorrectCount = ($results | Where-Object { $_ -eq 'incorrect' }).Count
        $correctCount = ($results | Where-Object { $_ -eq 'correct' }).Count

        # All correct → promote toward mastered
        if ($correctCount -eq 3) {
            if ($CurrentState.status -eq 'mastered') {
                return 'mastered'
            }
            if ($CurrentState.correct_count -ge 2) {
                return 'mastered'
            }
            return 'learning'
        }

        # Majority incorrect → mark as shaky
        if ($incorrectCount -ge 2) {
            return 'shaky'
        }

        # Mixed results → learning
        return 'learning'
    }

    function Get-StatusRank {
        # Return a numeric rank for status comparison (higher = better)
        param([string]$Status)

        switch ($Status) {
            'new'      { return 0 }
            'shaky'    { return 1 }
            'learning' { return 2 }
            'mastered' { return 3 }
            default    { return 0 }
        }
    }

    function Update-EaseFactor {
        # Adjust the ease factor based on recall performance
        param(
            [double]$CurrentEase,
            [string]$RecallResult
        )

        $adjustment = switch ($RecallResult) {
            'correct'   { 0.1 }
            'partial'   { -0.1 }
            'incorrect' { -0.2 }
            default     { 0 }
        }

        $newEase = $CurrentEase + $adjustment

        # Clamp between 1.3 and 3.0
        return [math]::Max(1.3, [math]::Min(3.0, $newEase))
    }

    function Save-SessionHistory {
        # Write the session result to the session-history folder
        param([object]$Result)

        $historyDir = Join-Path $RepoRoot "data\learner-state\$LearnerId\session-history"
        if (-not (Test-Path $historyDir)) {
            New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
        }

        $historyPath = Join-Path $historyDir "$($Result.session_id).json"
        $Result | ConvertTo-Json -Depth 5 | Set-Content -Path $historyPath -Encoding utf8
        Write-Host "Session history saved: $historyPath"
    }

    function Show-SessionSummary {
        # Display a human-readable summary of the session results
        param([object]$Result)

        $summary = $Result.session_summary
        Write-Host ""
        Write-Host "=== Session Summary: $($Result.session_id) ==="
        Write-Host "  Mastered:       $($summary.mastered -join ', ')"
        Write-Host "  Shaky:          $($summary.shaky -join ', ')"
        Write-Host "  Missed again:   $($summary.missed_again -join ', ')"
        Write-Host "  New introduced: $($summary.new_introduced -join ', ')"
        Write-Host "  Total reviewed: $($Result.items_reviewed.Count)"
        Write-Host ""
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
