Param(
    [Parameter(HelpMessage = "All GitHub Secrets in compressed JSON format", Mandatory = $true)]
    [string] $gitHubSecrets = "",
    [Parameter(HelpMessage = "Comma separated list of Secrets to get", Mandatory = $true)]
    [string] $getSecrets = "",
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d'
)

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch
$buildMutexName = "AL-Go-ReadSecrets"
$buildMutex = New-Object System.Threading.Mutex($false, $buildMutexName)
try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0078' -parentTelemetryScopeJson $parentTelemetryScopeJson

    try {
        if (!$buildMutex.WaitOne(1000)) {
            Write-Host "Waiting for other process executing ReadSecrets"
            $buildMutex.WaitOne() | Out-Null
            Write-Host "Other process completed ReadSecrets"
        }
    }
    catch [System.Threading.AbandonedMutexException] {
       Write-Host "Other process terminated abnormally"
    }

    Import-Module (Join-Path $PSScriptRoot ".\ReadSecretsHelper.psm1") -ArgumentList $gitHubSecrets

    $outSecrets = [ordered]@{}
    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
    $outSettings = $settings
    $keyVaultName = ""
    if (IsKeyVaultSet -and $settings.ContainsKey('keyVaultName')) {
        $keyVaultName = $settings.keyVaultName
        if ([string]::IsNullOrEmpty($keyVaultName)) {
            $credentialsJson = Get-KeyVaultCredentials | ConvertTo-HashTable
            if ($credentialsJson.Keys -contains "keyVaultName") {
                $keyVaultName = $credentialsJson.keyVaultName
            }
        }
    }
    [System.Collections.ArrayList]$secretsCollection = @()
    $getSecrets.Split(',') | Select-Object -Unique | ForEach-Object {
        $secret = $_
        $secretNameProperty = "$($secret)SecretName"
        if ($settings.Keys -contains $secretNameProperty) {
            $secret = "$($secret)=$($settings."$secretNameProperty")"
        }
        $secretsCollection += $secret
    }

    @($secretsCollection) | ForEach-Object {
        $secretSplit = $_.Split('=')
        $envVar = $secretSplit[0]
        $secret = $envVar
        if ($secretSplit.Count -gt 1) {
            $secret = $secretSplit[1]
        }

        if ($secret) {
            $value = GetSecret -secret $secret -keyVaultName $keyVaultName
            if ($value) {
                $json = @{}
                try {
                    $json = $value | ConvertFrom-Json | ConvertTo-HashTable
                }
                catch {
                }
                if ($json.Keys.Count) {
                    if ($value.contains("`n")) {
                        throw "JSON Secret $secret contains line breaks. JSON Secrets should be compressed JSON (i.e. NOT contain any line breaks)."
                    }
                    $json.Keys | ForEach-Object {
                        if (@("Scopes","TenantId","BlobName","ContainerName","StorageAccountName") -notcontains $_) {
                            # Mask individual values (but not Scopes, TenantId, BlobName, ContainerName and StorageAccountName)
                            MaskValue -key "$($secret).$($_)" -value $json."$_"
                        }
                    }
                }
                $base64value = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value))
                Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "$envVar=$base64value"
                $outSecrets += @{ "$envVar" = $base64value }
                Write-Host "$envVar successfully read from secret $secret"
                $secretsCollection.Remove($_)
            }
        }
    }

    if ($outSettings.Keys -contains 'appDependencyProbingPaths') {
        $outSettings.appDependencyProbingPaths | ForEach-Object {
            if ($_.PsObject.Properties.name -eq "AuthTokenSecret") {
                $_.authTokenSecret = GetSecret -secret $_.authTokenSecret -keyVaultName $keyVaultName
            } 
        }
    }

    if ($secretsCollection) {
        Write-Host "The following secrets was not found: $(($secretsCollection | ForEach-Object { 
            $secretSplit = @($_.Split('='))
            if ($secretSplit.Count -eq 1) {
                $secretSplit[0]
            }
            else {
                "$($secretSplit[0]) (Secret $($secretSplit[1]))"
            }
            $outSecrets += @{ ""$($secretSplit[0])"" = """" }
        }) -join ', ')"
    }

    #region Action: Output

    $outSecretsJson = $outSecrets | ConvertTo-Json -Compress
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "RepoSecrets=$outSecretsJson"

    $outSettingsJson = $outSettings | ConvertTo-Json -Depth 99 -Compress
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"

    #endregion

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "ReadSecrets action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    exit
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    $buildMutex.ReleaseMutex()
}
