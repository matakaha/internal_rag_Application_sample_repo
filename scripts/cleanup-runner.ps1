# Self-hosted Runner Cleanup Script
# このスクリプトはRunner環境をクリーンアップします

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$GitHubRepository,
    
    [string]$RunnerName,
    
    [string]$ContainerGroupName
)

Write-Host "Cleaning up runner environment..." -ForegroundColor Cyan

# Key VaultからGitHub PATを取得
Write-Host "Retrieving GitHub PAT from Key Vault..." -ForegroundColor Cyan
$githubToken = az keyvault secret show `
    --vault-name $KeyVaultName `
    --name GITHUB-PAT `
    --query value -o tsv

if (-not $githubToken) {
    Write-Warning "Failed to retrieve GitHub PAT from Key Vault"
} else {
    # Runner一覧取得
    Write-Host "Getting runners list from GitHub..." -ForegroundColor Cyan
    $runnersUrl = "https://api.github.com/repos/$GitHubRepository/actions/runners"
    $headers = @{
        "Authorization" = "token $githubToken"
        "Accept" = "application/vnd.github+json"
    }

    try {
        $runners = Invoke-RestMethod -Uri $runnersUrl -Method Get -Headers $headers
        
        if ($RunnerName) {
            # 特定のRunnerを削除
            $runner = $runners.runners | Where-Object { $_.name -eq $RunnerName }
            if ($runner) {
                Write-Host "Removing runner: $RunnerName (ID: $($runner.id))" -ForegroundColor Yellow
                $deleteUrl = "https://api.github.com/repos/$GitHubRepository/actions/runners/$($runner.id)"
                Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers
                Write-Host "Runner removed from GitHub" -ForegroundColor Green
            } else {
                Write-Warning "Runner not found: $RunnerName"
            }
        } else {
            # すべてのオフラインRunnerを削除
            $offlineRunners = $runners.runners | Where-Object { $_.status -eq "offline" }
            foreach ($runner in $offlineRunners) {
                Write-Host "Removing offline runner: $($runner.name) (ID: $($runner.id))" -ForegroundColor Yellow
                $deleteUrl = "https://api.github.com/repos/$GitHubRepository/actions/runners/$($runner.id)"
                try {
                    Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers
                    Write-Host "Runner removed: $($runner.name)" -ForegroundColor Green
                } catch {
                    Write-Warning "Failed to remove runner: $($runner.name)"
                }
            }
        }
    } catch {
        Write-Warning "Failed to get runners list: $_"
    }
}

# Container Instance削除
if ($ContainerGroupName) {
    Write-Host "Deleting Container Instance: $ContainerGroupName" -ForegroundColor Cyan
    az container delete `
        --resource-group $ResourceGroup `
        --name $ContainerGroupName `
        --yes
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Container Instance deleted successfully!" -ForegroundColor Green
    } else {
        Write-Warning "Failed to delete Container Instance"
    }
} else {
    # すべてのContainer Instancesを一覧表示
    Write-Host "Listing all Container Instances in resource group..." -ForegroundColor Cyan
    az container list --resource-group $ResourceGroup --output table
    
    Write-Host "`nTo delete a specific container, run:" -ForegroundColor Yellow
    Write-Host "az container delete --resource-group $ResourceGroup --name <container-name> --yes" -ForegroundColor White
}

Write-Host "`nCleanup completed." -ForegroundColor Green
