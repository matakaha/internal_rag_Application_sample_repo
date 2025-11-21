# Step 01 への NAT Gateway 統合

## 概要
完全な閉域環境を実現するため、Step 01（ネットワーク基盤）に NAT Gateway を統合し、VNet からのアウトバウンド通信を制御します。

## 背景

### 現状の問題点

1. **アウトバウンド通信が制御されていない**
   - ACI (Container Instances) や App Service から直接インターネットにアクセス可能
   - Private Endpoint は「インバウンド」のみを制御
   - 完全な閉域環境ではない

2. **GitHub Actions からの ACR アクセスができない**
   - ACR が閉域化されている（`publicNetworkAccess: Disabled`）
   - GitHub ホステッドランナーの IP アドレスが不定
   - NAT Gateway があれば、固定 Public IP を ACR ファイアウォールルールに追加可能

### Microsoft ドキュメント

参考: [Azure Container Instances の仮想ネットワーク シナリオとリソース](https://learn.microsoft.com/ja-jp/azure/container-instances/container-instances-vnet)

> VNet に統合された ACI でも、デフォルトではインターネットへの直接アウトバウンドが可能です。NAT Gateway または Azure Firewall でアウトバウンドトラフィックを制御する必要があります。

## 提案する構成

### Step 01 の Bicep に統合

`bicep/step01-networking/main.bicep` に以下のリソースを追加:

```bicep
// Public IP Address (NAT Gateway 用)
resource natGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'pip-natgw-${environmentName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  tags: tags
}

// NAT Gateway
resource natGateway 'Microsoft.Network/natGateways@2023-04-01' = {
  name: 'natgw-${environmentName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: natGatewayPublicIp.id
      }
    ]
  }
  tags: tags
}

// ACI サブネットに NAT Gateway を関連付け（既存のサブネット定義を更新）
resource aciSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  parent: vnet
  name: 'snet-container-instances'
  properties: {
    addressPrefix: '10.0.6.0/24'
    natGateway: {
      id: natGateway.id  // ← NAT Gateway を追加
    }
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    delegations: [
      {
        name: 'aciDelegation'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ]
  }
}

// App Service 統合サブネットにも NAT Gateway を関連付け（既存のサブネット定義を更新）
resource appServiceSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  parent: vnet
  name: 'snet-app-service'
  properties: {
    addressPrefix: '10.0.5.0/24'
    natGateway: {
      id: natGateway.id  // ← NAT Gateway を追加
    }
    delegations: [
      {
        name: 'delegation'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

// NAT Gateway の Public IP を出力（ACR ファイアウォール設定で使用）
output natGatewayPublicIp string = natGatewayPublicIp.properties.ipAddress
output natGatewayPublicIpId string = natGatewayPublicIp.id
output natGatewayId string = natGateway.id
```

### ACR ファイアウォールルールの更新

Step 01 デプロイ後、ACR に NAT Gateway の Public IP を許可:

```powershell
# Step 01 のデプロイ出力から NAT Gateway の Public IP を取得
$NAT_IP = az deployment group show `
  --resource-group rg-internal-rag-dev `
  --name step01-networking `
  --query properties.outputs.natGatewayPublicIp.value `
  --output tsv

# ACR のネットワークルールに追加
az acr network-rule add `
  --name acrinternalragdev `
  --ip-address $NAT_IP

# 確認
az acr network-rule list --name acrinternalragdev
```

## メリット

### 1. 完全な閉域環境の実現

```
[ACI/App Service (vNet統合)]
         ↓ アウトバウンド
   [NAT Gateway (固定 Public IP)]
         ↓ 制御されたトラフィック
      インターネット
```

### 2. GitHub Actions からの ACR アクセスが可能

- GitHub ホステッドランナーでコンテナをビルド
- NAT Gateway 経由で ACR にプッシュ
- ACR のファイアウォールルールで NAT Gateway の IP のみ許可

### 3. セキュリティ強化

- アウトバウンド通信が固定 Public IP 経由
- NSG や Azure Firewall との組み合わせで細かい制御が可能
- ログ・監査が容易

## コスト

- **NAT Gateway**: ~¥600/月（基本料金）
- **Public IP (Standard)**: ~¥400/月
- **データ処理料金**: ~¥600/GB（アウトバウンドトラフィック）

**合計**: 約 ¥1,000〜2,000/月（トラフィック量による）

## デプロイ順序

### 新規デプロイの場合

1. **Step 01: ネットワーク基盤（NAT Gateway 含む）** ← 統合
2. Step 02: ストレージ
3. Step 03: AI Foundry
4. Step 04: AI Search
5. Step 05: コンピュート
6. **ACR ファイアウォールルールの更新**

### 既存環境への追加の場合

既に Step 01 がデプロイ済みの場合は、以下の手順で追加:

1. `bicep/step01-networking/main.bicep` に NAT Gateway リソースを追加
2. 既存のサブネット定義に `natGateway` プロパティを追加
3. Step 01 を再デプロイ:
   ```powershell
   az deployment group create `
     --resource-group rg-internal-rag-dev `
     --template-file bicep/step01-networking/main.bicep `
     --parameters bicep/step01-networking/parameters.bicepparam
   ```
4. ACR ファイアウォールルールに NAT Gateway の Public IP を追加

**注意**: サブネットの更新は既存のリソース（ACI、App Service）に影響しないため、ダウンタイムなく適用可能です。

## 参考リンク

- [Azure NAT Gateway とは](https://learn.microsoft.com/ja-jp/azure/nat-gateway/nat-overview)
- [NAT Gateway と仮想ネットワーク](https://learn.microsoft.com/ja-jp/azure/nat-gateway/nat-gateway-resource)
- [コンテナー インスタンスの仮想ネットワーク シナリオとリソース](https://learn.microsoft.com/ja-jp/azure/container-instances/container-instances-vnet)

## 実装予定

### internal_rag_step_by_step リポジトリ

- [ ] `bicep/step01-networking/main.bicep` に NAT Gateway リソースを追加
- [ ] サブネット定義に `natGateway` プロパティを追加
- [ ] `bicep/step01-networking/README.md` を更新（NAT Gateway の説明を追加）
- [ ] `bicep/complete/main.bicep` が Step 01 を参照している場合は自動的に反映
- [ ] デプロイガイドの更新（ACR ファイアウォール設定手順を追加）

### internal_rag_Application_deployment_step_by_step リポジトリ

NAT Gateway 導入により、以下のドキュメントから **ACR のパブリックアクセス一時有効化手順が不要** になります:

- [ ] `bicep/step01-container-registry/README.md` を更新
  - 「5. Runnerコンテナーイメージのビルド」から `az acr update --public-network-enabled` 手順を削除
  - 前提条件に「NAT Gateway の Public IP が ACR ファイアウォールルールに追加済み」を追加
- [ ] `bicep/step01-container-registry/BUILD_GUIDE.md` を更新（存在する場合）
  - ACR パブリックアクセス制御手順を削除
- [ ] `docs/00-prerequisites.md` を更新
  - NAT Gateway が `internal_rag_step_by_step` Step 01 に含まれていることを明記
  - ACR ファイアウォールルールの設定が前提条件であることを追加
- [ ] `docs/deployment-guide.md` を更新
  - ACR ファイアウォールルール追加手順を追加
- [ ] `README.md` のアーキテクチャ図を更新
  - NAT Gateway と Public IP を追加
