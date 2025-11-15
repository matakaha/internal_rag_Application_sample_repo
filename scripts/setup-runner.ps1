# Self-hosted Runner Setup Script
# このスクリプトはローカルでの検証用です

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$VNetName,
    
    [Parameter(Mandatory=$true)]
    [string]$SubnetName,
    
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$GitHubRepository,
    
    [string]$Location = "japaneast"
)

Write-Host "Setting up self-hosted runner..." -ForegroundColor Cyan

# Runner名を生成
$runnerName = "runner-local-$(Get-Date -Format 'yyyyMMddHHmmss')"
$containerGroupName = "aci-$runnerName"

Write-Host "Runner Name: $runnerName" -ForegroundColor Yellow
Write-Host "Container Group: $containerGroupName" -ForegroundColor Yellow

# Key VaultからGitHub PATを取得
Write-Host "Retrieving GitHub PAT from Key Vault..." -ForegroundColor Cyan
$githubToken = az keyvault secret show `
    --vault-name $KeyVaultName `
    --name GITHUB-PAT `
    --query value -o tsv

if (-not $githubToken) {
    Write-Error "Failed to retrieve GitHub PAT from Key Vault"
    exit 1
}

# GitHub Runner登録トークン取得
Write-Host "Getting GitHub Runner registration token..." -ForegroundColor Cyan
$registrationUrl = "https://api.github.com/repos/$GitHubRepository/actions/runners/registration-token"
$headers = @{
    "Authorization" = "token $githubToken"
    "Accept" = "application/vnd.github+json"
}

$response = Invoke-RestMethod -Uri $registrationUrl -Method Post -Headers $headers
$runnerToken = $response.token

if (-not $runnerToken) {
    Write-Error "Failed to get runner registration token"
    exit 1
}

# Container Instance作成
Write-Host "Creating Container Instance..." -ForegroundColor Cyan
az container create `
    --resource-group $ResourceGroup `
    --name $containerGroupName `
    --image mcr.microsoft.com/azure-cli:latest `
    --vnet $VNetName `
    --subnet $SubnetName `
    --location $Location `
    --cpu 2 `
    --memory 4 `
    --restart-policy Never `
    --environment-variables `
        RUNNER_NAME=$runnerName `
        RUNNER_TOKEN=$runnerToken `
        GITHUB_REPOSITORY=$GitHubRepository `
    --command-line "/bin/bash -c 'curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz && tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz && ./config.sh --url https://github.com/$GitHubRepository --token $runnerToken --name $runnerName --work _work --labels self-hosted,azure,vnet && ./run.sh'"

if ($LASTEXITCODE -eq 0) {
    Write-Host "Container Instance created successfully!" -ForegroundColor Green
    Write-Host "Waiting for runner to be ready (60 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
    Write-Host "Runner should be ready now." -ForegroundColor Green
} else {
    Write-Error "Failed to create Container Instance"
    exit 1
}
