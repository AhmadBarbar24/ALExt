param(
    [Parameter(Mandatory = $true)]
    [string] $Repository,
    [Parameter(Mandatory = $true)]
    [string] $RunId
)

Write-Host "Checking workflow status for run $RunId in repository $Repository"

$workflowJobs = gh api /repos/$Repository/actions/runs/$RunId/jobs -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json
$failedJobs = $workflowJobs.jobs | Where-Object { $_.conclusion -eq "failure" }

if ($failedJobs) {
    throw "Workflow failed with the following jobs: $($failedJobs.name -join ', ')"
}

Write-Host "Workflow succeeded"