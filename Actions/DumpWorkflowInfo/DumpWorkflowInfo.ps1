Write-Host "Event name: $env:GITHUB_EVENT_NAME"

# Print all env variables 
Write-Host "Environment variables:"
$eventPath = Get-Content -Encoding UTF8 -Path $env:GITHUB_EVENT_PATH -Raw
Write-Host $eventPath
$eventPath | ConvertFrom-Json | Format-List | Out-String

if ($env:GITHUB_EVENT_NAME -eq 'workflow_dispatch') {
  Write-Host "Inputs:"
  $eventPath = Get-Content -Encoding UTF8 -Path $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
  if ($null -ne $eventPath.inputs) {
    $eventPath.inputs.psObject.Properties | Sort-Object { $_.Name } | ForEach-Object {
      $property = $_.Name
      $value = $eventPath.inputs."$property"
      Write-Host "- $property = '$value'"
    }
  }
}
