Param(
    [Parameter(HelpMessage = "The project for which to fetch dependencies", Mandatory = $true)]
    [string] $project,
    [string] $baseFolder,
    [string] $buildMode = 'Default',
    [string] $projectsDependenciesJson,
    [string] $baseBranch,
    [string] $destinationPath,
    [string] $token
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Write-Host "Fetching dependencies for project '$project'. BuildMode: $buildMode, Base Folder: $baseFolder, BaseBranch: $baseBranch"
$fetchedApps= @()
$fetchedTestApps= @()

Write-Host "::group::Downloading project dependencies from probing paths"

$projectSettings = ReadSettings -baseFolder $baseFolder -project $project

if ($projectSettings.appDependencyProbingPaths) {
    Get-Dependencies -probingPathsJson $repo.appDependencyProbingPaths | ForEach-Object {
        # naming convention: app, (testapp)
        if ($_.startswith('(')) {
            $fetchedTestApps += $_    
        }
        else {
            $fetchedApps += $_    
        }
    }
}

Write-Host "::endgroup::"

Write-Host "::group::Downloading project dependencies from current build"

$projectsDependencies = $projectsDependenciesJson | ConvertFrom-Json | ConvertTo-HashTable
if ($projectsDependencies.Keys -contains $project) {
    $dependencyProjects = @($projectsDependencies."$project")
}

$dependeciesProbingPaths = @($dependencyProjects | ForEach-Object {
    $dependencyProject = $_
    $dependencyProjectSettings = ReadSettings -baseFolder $baseFolder -project $dependencyProject

    $dependencyBuildMode = $buildMode
    if(!($dependencyProjectSettings.buildModes -contains $dependencyBuildMode)) {
        # Fetch the default build mode if the specified build mode is not supported for the dependency project
        $dependencyBuildMode = 'Default';
    }

    return @{
        "release_status" = "thisBuild"
        "version" = "latest"
        "buildMode" = $dependencyBuildMode
        "projects" = $dependencyProject
        "repo" = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
        "branch" = $ENV:GITHUB_REF_NAME
        "baseBranch" = $ENV:GITHUB_BASE_REF_NAME
        "authTokenSecret" = $token
    }
})

$dependeciesProbingPaths | ForEach-Object {
    $dependencyProbingPath = $_
    $downloadedDependencies = Get-Dependencies -probingPathsJson $dependencyProbingPath -saveToPath $destinationPath | Where-Object { $_ }

    $downloadedDependencies | ForEach-Object {
        # naming convention: app, (testapp)
        if ($_.startswith('(')) {
            $fetchedTestApps += $_    
        }
        else {
            $fetchedApps += $_    
        }
    }
}

Write-Host "::endgroup::"

Write-Host "Fetched dependencies apps: $($fetchedApps -join ', ')"
Write-Host "Fetched dependencies test apps: $($fetchedTestApps -join ', ')"

$fetchedAppsJson = ConvertTo-Json $fetchedApps -Depth 99 -Compress
$fetchedTestAppsJson = ConvertTo-Json $fetchedTestApps -Depth 99 -Compress

Add-Content -Path $env:GITHUB_OUTPUT -Value "FetchedApps=$fetchedAppsJson"
Add-Content -Path $env:GITHUB_OUTPUT -Value "FetchedTestApps=$fetchedTestAppsJson"