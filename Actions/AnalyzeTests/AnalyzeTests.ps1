Param(
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project to analyze", Mandatory = $false)]
    [string] $project
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0082' -parentTelemetryScopeJson $parentTelemetryScopeJson

    . (Join-Path -Path $PSScriptRoot 'TestResultAnalyzer.ps1')

    $testResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\TestResults.xml"
    if (Test-Path $testResultsFile) {
        $testResults = [xml](Get-Content "$project\TestResults.xml")
        $testResultSummary = GetTestResultSummary -testResults $testResults -includeFailures 50

        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "TestResultMD=$testResultSummary"
        Write-Host "TestResultMD=$testResultSummary"

        # If event is pull_request
        if ($env:GITHUB_EVENT_NAME -eq 'pull_request') {
            $runId = $env:GITHUB_RUN_ID
            $attemptNumber = $env:GITHUB_RUN_NUMBER
            $pullRequestNumber = "135" # $env:GITHUB_EVENT_PATH | Get-Content | ConvertFrom-Json | Select-Object -ExpandProperty number

            Write-Host "RunId: $runId"
            Write-Host "AttemptNumber: $attemptNumber"
            Write-Host "PullRequestNumber: $pullRequestNumber"

            $pullRequestCommentAffix = "<!--$runId -->`n"

            Write-Host "PullRequestCommentAffix: $pullRequestCommentAffix"

            # Check if a comment with the affix already exists using gh api
            $existingComments = gh api --method GET -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$ENV:GITHUB_REPOSITORY/issues/$pullRequestNumber/comments | ConvertFrom-Json
            $existingComment = $existingComments | Where-Object { ($_.PSObject.Properties.Name -contains "body") -and ($_.body -like "$pullRequestCommentAffix*")} | Select-Object -First 1

            if ($existingComment) {
                Write-Host "Updating existing comment: $($existingComment.id)"
                # Update the existing comment
                $pullRequestComment = ($existingComment.body + $testResultSummary) -replace "\\n", "`n"
                gh api --method PATCH -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$ENV:GITHUB_REPOSITORY/issues/comments/$($existingComment.id) -f body=$pullRequestComment
            }
            else {
                # Create a new comment
                $pullRequestComment = ($pullRequestCommentAffix + $testResultSummary) -replace "\\n", "`n"
                Write-Host "PullRequestComment: $pullRequestComment"
                gh api --method POST -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$ENV:GITHUB_REPOSITORY/issues/$pullRequestNumber/comments -f body=$pullRequestComment 
            }
            # Create a new comment
            # $pullRequestComment = ($pullRequestCommentAffix + $testResultSummary) -replace "\\n", "`n"
            # Write-Host "PullRequestComment: $pullRequestComment"
            # gh api --method POST -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /repos/$ENV:GITHUB_REPOSITORY/issues/$pullRequestNumber/comments -f body=$pullRequestComment 
        }
        Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "$($testResultSummary.Replace("\\n","`n"))`n"
    }
    else {
        Write-Host "Test results not found"
    }

    $bcptTestResultsFile = Join-Path $ENV:GITHUB_WORKSPACE "$project\BCPTTestResults.json"
    if (Test-Path $bcptTestResultsFile) {
        # TODO Display BCPT Test Results
    }
    else {
        #Add-Content -path $ENV:GITHUB_STEP_SUMMARY -value "*BCPT test results not found*`n`n"
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }

    throw
}
