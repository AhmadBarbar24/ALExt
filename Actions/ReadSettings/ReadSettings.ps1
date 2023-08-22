Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Specifies whether you want to include production environments", Mandatory = $false)]
    [bool] $includeProduction,
    [Parameter(HelpMessage = "Indicates whether this is called from a release pipeline", Mandatory = $false)]
    [bool] $release,
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = ""
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper

    import-module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0079' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $settings = ReadSettings -project $project
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @()
    }

    if ($ENV:GITHUB_EVENT_NAME -in @("pull_request_target", "pull_request")) {
        $settings.doNotSignApps = $true
        $settings.versioningStrategy = 15
    }

    if ($settings.appBuild -eq [int32]::MaxValue) {
        $settings.versioningStrategy = 15
    }

    if ($settings.versioningstrategy -ne -1) {
        switch ($settings.versioningStrategy -band 15) {
            0 { # Use RUN_NUMBER and RUN_ATTEMPT
                $settings.appBuild = $settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
                $settings.appRevision = [Int32]($ENV:GITHUB_RUN_ATTEMPT) - 1
            }
            1 { # Use RUN_ID and RUN_ATTEMPT
                OutputError -message "Versioning strategy 1 is no longer supported"
            }
            2 { # USE DATETIME
                $settings.appBuild = [Int32]([DateTime]::UtcNow.ToString('yyyyMMdd'))
                $settings.appRevision = [Int32]([DateTime]::UtcNow.ToString('HHmmss'))
            }
            15 { # Use maxValue
                $settings.appBuild = [Int32]::MaxValue
                $settings.appRevision = 0
            }
            default {
                OutputError -message "Unknown version strategy $versionStrategy"
                exit
            }
        }
    }

    $outSettings = @{}
    $settings.Keys | ForEach-Object {
        $setting = $_
        $settingValue = $settings."$setting"
        $outSettings += @{ "$setting" = $settingValue }
        if ($getSettings -contains $setting) {
            if ($settingValue -is [System.Collections.Specialized.OrderedDictionary] -or $settingValue -is [hashtable]) {
                Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "$setting=$(ConvertTo-Json $settingValue -Depth 99 -Compress)"
            }
            elseif ($settingValue -is [String] -and ($settingValue.contains("`n") -or $settingValue.contains("`r"))) {
                throw "Setting $setting contains line breaks, which is not supported"
            }
            else {
                Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "$setting=$settingValue"
            }
        }
    }

    Write-Host "SETTINGS:"
    $outSettings | ConvertTo-Json -Depth 99 | Out-Host
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "Settings=$($outSettings | ConvertTo-Json -Depth 99 -Compress)"

    $gitHubRunner = $settings.githubRunner.Split(',').Trim() | ConvertTo-Json -compress
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "GitHubRunnerJson=$githubRunner"
    Write-Host "GitHubRunnerJson=$githubRunner"

    $gitHubRunnerShell = $settings.githubRunnerShell
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "GitHubRunnerShell=$githubRunnerShell"
    Write-Host "GitHubRunnerShell=$githubRunnerShell"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if ($env:BcContainerHelperPath) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
