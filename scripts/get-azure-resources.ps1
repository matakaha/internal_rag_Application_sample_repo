# Azure Resource Information Retrieval Script
param(
    [string]$ResourceGroup = "rg-internal-rag-dev",
    [string]$SubscriptionId
)

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Azure Resource Information Retrieval" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Check Azure login
try {
    $null = az account show 2>$null
} catch {
    Write-Host "Please login to Azure" -ForegroundColor Yellow
    az login
}

# Set subscription
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
}

$currentSub = az account show -o json | ConvertFrom-Json
Write-Host "Subscription: $($currentSub.name)" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Cyan
Write-Host ""

# Check resource group exists
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "false") {
    Write-Host "ERROR: Resource group not found" -ForegroundColor Red
    exit 1
}

# Store environment variables
$envVars = @{}

# Get Azure OpenAI
Write-Host "1. Getting Azure OpenAI..." -ForegroundColor Yellow
$openaiJson = az cognitiveservices account list --resource-group $ResourceGroup -o json
$openaiList = $openaiJson | ConvertFrom-Json
$openai = $openaiList | Where-Object { $_.kind -eq 'OpenAI' } | Select-Object -First 1

if ($openai) {
    Write-Host "   Name: $($openai.name)" -ForegroundColor Green
    $envVars.AZURE_OPENAI_RESOURCE_NAME = $openai.name
    
    # Get resource-specific endpoint (not region endpoint)
    $openaiDetailJson = az cognitiveservices account show --resource-group $ResourceGroup --name $openai.name -o json
    $openaiDetail = $openaiDetailJson | ConvertFrom-Json
    $envVars.AZURE_OPENAI_ENDPOINT = $openaiDetail.properties.endpoint
    Write-Host "   Endpoint: $($envVars.AZURE_OPENAI_ENDPOINT)" -ForegroundColor Green
    
    # Get deployments
    $depJson = az cognitiveservices account deployment list --resource-group $ResourceGroup --name $openai.name -o json
    $deployments = $depJson | ConvertFrom-Json
    if ($deployments) {
        $gpt4 = $deployments | Where-Object { $_.properties.model.name -like "gpt-4*" } | Select-Object -First 1
        if ($gpt4) {
            $envVars.AZURE_OPENAI_DEPLOYMENT = $gpt4.name
            Write-Host "   Deployment: $($gpt4.name)" -ForegroundColor Green
        }
    }
}

# Get AI Search
Write-Host "2. Getting AI Search..." -ForegroundColor Yellow
$searchJson = az search service list --resource-group $ResourceGroup -o json
$searchList = $searchJson | ConvertFrom-Json
$search = $searchList | Select-Object -First 1

if ($search) {
    Write-Host "   Name: $($search.name)" -ForegroundColor Green
    $envVars.AZURE_SEARCH_SERVICE_NAME = $search.name
    $envVars.AZURE_SEARCH_ENDPOINT = "https://$($search.name).search.windows.net"
    $envVars.AZURE_SEARCH_INDEX = "redlist-index"
}

# Get Storage Account
Write-Host "3. Getting Storage Account..." -ForegroundColor Yellow
$storageJson = az storage account list --resource-group $ResourceGroup -o json
$storageList = $storageJson | ConvertFrom-Json
$storage = $storageList | Select-Object -First 1

if ($storage) {
    Write-Host "   Name: $($storage.name)" -ForegroundColor Green
    $envVars.AZURE_STORAGE_ACCOUNT_NAME = $storage.name
    $envVars.AZURE_STORAGE_CONTAINER = "redlist-data"
}

# Get App Service
Write-Host "4. Getting App Service..." -ForegroundColor Yellow
$webappJson = az webapp list --resource-group $ResourceGroup -o json
$webappList = $webappJson | ConvertFrom-Json
$webapp = $webappList | Select-Object -First 1

if ($webapp) {
    Write-Host "   Name: $($webapp.name)" -ForegroundColor Green
    $envVars.AZURE_WEBAPP_NAME = $webapp.name
    $envVars.AZURE_WEBAPP_URL = "https://$($webapp.defaultHostName)"
}

# Get Key Vault
Write-Host "5. Getting Key Vault..." -ForegroundColor Yellow
$kvJson = az keyvault list --resource-group $ResourceGroup -o json
$kvList = $kvJson | ConvertFrom-Json
$kv = $kvList | Select-Object -First 1

if ($kv) {
    Write-Host "   Name: $($kv.name)" -ForegroundColor Green
    $envVars.AZURE_KEYVAULT_NAME = $kv.name
    $envVars.AZURE_KEYVAULT_URI = $kv.properties.vaultUri
}

# Get VNet
Write-Host "6. Getting Virtual Network..." -ForegroundColor Yellow
$vnetJson = az network vnet list --resource-group $ResourceGroup -o json
$vnetList = $vnetJson | ConvertFrom-Json
$vnet = $vnetList | Select-Object -First 1

if ($vnet) {
    Write-Host "   Name: $($vnet.name)" -ForegroundColor Green
    $envVars.AZURE_VNET_NAME = $vnet.name
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Creating .env file" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Create .env file
$envPath = Join-Path (Get-Location) ".env"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$content = @"
# Azure Resource Information
# Generated: $timestamp
# Resource Group: $ResourceGroup

# Azure OpenAI Settings
AZURE_OPENAI_RESOURCE_NAME=$($envVars.AZURE_OPENAI_RESOURCE_NAME)
AZURE_OPENAI_ENDPOINT=$($envVars.AZURE_OPENAI_ENDPOINT)
AZURE_OPENAI_DEPLOYMENT=$($envVars.AZURE_OPENAI_DEPLOYMENT)

# Azure AI Search Settings
AZURE_SEARCH_SERVICE_NAME=$($envVars.AZURE_SEARCH_SERVICE_NAME)
AZURE_SEARCH_ENDPOINT=$($envVars.AZURE_SEARCH_ENDPOINT)
AZURE_SEARCH_INDEX=$($envVars.AZURE_SEARCH_INDEX)

# Azure Storage Settings
AZURE_STORAGE_ACCOUNT_NAME=$($envVars.AZURE_STORAGE_ACCOUNT_NAME)
AZURE_STORAGE_CONTAINER=$($envVars.AZURE_STORAGE_CONTAINER)

# App Service Settings
AZURE_WEBAPP_NAME=$($envVars.AZURE_WEBAPP_NAME)
AZURE_WEBAPP_URL=$($envVars.AZURE_WEBAPP_URL)

# Key Vault Settings
AZURE_KEYVAULT_NAME=$($envVars.AZURE_KEYVAULT_NAME)
AZURE_KEYVAULT_URI=$($envVars.AZURE_KEYVAULT_URI)

# Virtual Network Settings
AZURE_VNET_NAME=$($envVars.AZURE_VNET_NAME)

# Application Settings
FLASK_ENV=development
RESOURCE_GROUP=$ResourceGroup
"@

$content | Out-File -FilePath $envPath -Encoding UTF8 -Force
Write-Host "Created: $envPath" -ForegroundColor Green
Write-Host ""

# Show GitHub Secrets commands
Write-Host "GitHub Secrets commands:" -ForegroundColor Cyan
if ($envVars.AZURE_OPENAI_ENDPOINT) {
    Write-Host "  gh secret set AZURE_OPENAI_ENDPOINT -b `"$($envVars.AZURE_OPENAI_ENDPOINT)`"" -ForegroundColor Gray
}
if ($envVars.AZURE_OPENAI_DEPLOYMENT) {
    Write-Host "  gh secret set AZURE_OPENAI_DEPLOYMENT -b `"$($envVars.AZURE_OPENAI_DEPLOYMENT)`"" -ForegroundColor Gray
}
if ($envVars.AZURE_SEARCH_ENDPOINT) {
    Write-Host "  gh secret set AZURE_SEARCH_ENDPOINT -b `"$($envVars.AZURE_SEARCH_ENDPOINT)`"" -ForegroundColor Gray
}
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Done" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
