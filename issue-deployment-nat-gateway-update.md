# NAT Gateway 導入に伴うドキュメント更新

## 概要

[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step) リポジトリに NAT Gateway が統合される予定です（[Issue #2](https://github.com/matakaha/internal_rag_step_by_step/issues/2)）。

これに伴い、本リポジトリのドキュメントを更新し、ACR のパブリックアクセス一時有効化の手順を削除します。

## 背景

### 現状の問題

現在、Runner イメージのビルド時に以下の手順が必要:

```powershell
# 1. ACR のパブリックアクセスを一時的に有効化
az acr update --name $ACR_NAME --public-network-enabled true --default-action Allow

# 2. ACR Tasks でビルド
az acr build --registry $ACR_NAME --image github-runner:latest .

# 3. ACR のパブリックアクセスを無効化
az acr update --name $ACR_NAME --public-network-enabled false --default-action Deny
```

**理由**: ACR Tasks が使用する Microsoft 管理の Public IP が、閉域化された ACR にアクセスできないため。

### NAT Gateway 導入後

NAT Gateway の Public IP を ACR ファイアウォールルールに追加することで:

```powershell
# 一度だけ実行（前提条件として）
$NAT_IP = az deployment group show `
  --resource-group rg-internal-rag-dev `
  --name step01-networking `
  --query properties.outputs.natGatewayPublicIp.value `
  --output tsv

az acr network-rule add --name acrinternalragdev --ip-address $NAT_IP

# 以降、パブリックアクセス有効化なしでビルド可能
az acr build --registry $ACR_NAME --image github-runner:latest .
```

**メリット**:
- ✅ セキュリティ強化（ACR のパブリックアクセスを常に無効化）
- ✅ 手順簡素化（ビルドのたびに有効化/無効化が不要）
- ✅ 完全な閉域環境（固定 Public IP のみ許可）

## 更新が必要なファイル

### 1. `bicep/step01-container-registry/README.md`

#### セクション: 「前提条件」

**追加**:

```markdown
### 前提条件

- [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step) Step 01が完了していること
  - Virtual Network `vnet-internal-rag-<環境名>` が存在すること
  - **NAT Gateway が Step 01 に統合されていること** ← 追加
  - **ACR ファイアウォールに NAT Gateway の Public IP が追加されていること** ← 追加
- Azure CLI がインストールされていること
```

#### セクション: 「5. Runnerコンテナーイメージのビルド」→「方法1: ACR Tasks使用(推奨)」

**現在の手順**:

```powershell
# 1. パブリックアクセスとネットワークルールを一時的に許可（ACR Tasksに必要）
az acr update --name $ACR_NAME --public-network-enabled true --default-action Allow

# 2. ACR上で直接ビルドとプッシュを実行
az acr build --registry $ACR_NAME --image github-runner:latest --file Dockerfile .

# 3. イメージ確認（パブリックアクセス有効中に実施）
az acr repository show-tags --name $ACR_NAME --repository github-runner --output table

# 4. パブリックアクセスとネットワークルールを無効化（セキュリティ強化）
az acr update --name $ACR_NAME --public-network-enabled false --default-action Deny
```

**更新後の手順**:

```powershell
# ACR Tasks でビルドとプッシュを実行
# NAT Gateway の Public IP が ACR ファイアウォールに追加済みのため、
# パブリックアクセスの有効化は不要
az acr build `
  --registry $ACR_NAME `
  --image github-runner:latest `
  --image github-runner:1.0.0 `
  --file Dockerfile `
  .

# イメージ確認
az acr repository show-tags `
  --name $ACR_NAME `
  --repository github-runner `
  --output table
```

**説明を追加**:

> **Note**: NAT Gateway の Public IP が ACR のネットワークルールに追加されているため、ACR Tasks は閉域環境からでも実行可能です。パブリックアクセスの一時的な有効化は不要です。

#### セクション: 「6. イメージの確認」

**削除**: パブリックアクセスの一時的な有効化に関する警告とコマンド

**現在の内容**:

> ⚠️ 注意: パブリックアクセス無効化後は、ローカルからのイメージ確認はできません。上記手順の「3. イメージ確認」で実施済みであることを確認してください。
>
> パブリックアクセス無効化後に確認が必要な場合は、一時的に有効化してください:

```powershell
# 一時的にパブリックアクセスを有効化
az acr update --name $ACR_NAME --public-network-enabled true
# ...
# 確認後、再度無効化
az acr update --name $ACR_NAME --public-network-enabled false
```

**更新後の内容**:

```markdown
### 6. イメージの確認

ACR 内のイメージを確認します:

```powershell
# ACR内のイメージ一覧を表示
az acr repository list --name $ACR_NAME --output table

# 特定リポジトリのタグ一覧を表示
az acr repository show-tags --name $ACR_NAME --repository github-runner --output table
```

期待される出力:

```
Repository      Tag
--------------  -------
github-runner   latest
github-runner   1.0.0
node            18-alpine
```

> **Note**: NAT Gateway 経由で ACR にアクセスしているため、`az acr repository` コマンドは常に実行可能です。
```

### 2. `docs/00-prerequisites.md`

**追加**:

```markdown
### 前提条件

#### internal_rag_step_by_step の環境構築

以下のリポジトリで基盤インフラが構築済みであること:
[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)

**必須リソース**:
- Virtual Network (vNet)
- **NAT Gateway (Step 01 に統合)** ← 追加
- Private DNS Zones
- App Service (vNet統合済、フロントエンド用)
- Azure Functions (Flex Consumption, vNet統合済、バックエンド用)

#### ACR ファイアウォール設定

NAT Gateway の Public IP を ACR のネットワークルールに追加済みであること:

```powershell
# NAT Gateway の Public IP を取得
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
```

### 3. `README.md`

#### セクション: 「前提条件」

**更新前**:

```markdown
### 前提条件

- [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)の環境が構築済みであること
  - Virtual Network (vNet)
  - Private DNS Zones
  - App Service (vNet統合済、フロントエンド用)
  - Azure Functions (Flex Consumption, vNet統合済、バックエンド用)
```

**更新後**:

```markdown
### 前提条件

- [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)の環境が構築済みであること
  - Virtual Network (vNet)
  - **NAT Gateway (Step 01 に統合)** ← 追加
  - Private DNS Zones
  - App Service (vNet統合済、フロントエンド用)
  - Azure Functions (Flex Consumption, vNet統合済、バックエンド用)
  - **ACR ファイアウォールに NAT Gateway の Public IP が追加済み** ← 追加
```

### 4. `docs/deployment-guide.md` (存在する場合)

NAT Gateway の Public IP を ACR に追加する手順を、Step 01 の前提条件として追加。

### 5. アーキテクチャ図の更新

`README.md` または `docs/01-architecture.md` のアーキテクチャ図に NAT Gateway を追加:

```
┌─────────────────────────────────────────────────────────────┐
│          Azure Virtual Network (10.0.0.0/16)               │
│                                                             │
│  ┌──────────────────┐     ┌──────────────────┐            │
│  │ Container Registry│     │   Key Vault      │            │
│  │   (ACR + PE)     │     │  (認証情報管理)   │            │
│  │ ┌──────────────┐ │     └────────┬─────────┘            │
│  │ │ネットワーク  │ │              │                       │
│  │ │ルール:       │ │              │ Private Endpoint      │
│  │ │NAT Gateway IP│ │              │                       │
│  │ └──────────────┘ │              │                       │
│  └────────┬─────────┘              │                       │
│           │ Private Endpoint       │                       │
│           │                        │                       │
│  ┌────────┴────────────────────────┴─────────┐            │
│  │  Container Instance Subnet (10.0.6.0/24)  │            │
│  │    (Self-hosted GitHub Actions Runner)    │            │
│  │           ↓ アウトバウンド                │            │
│  │      NAT Gateway (固定 Public IP)         │            │
│  └───────────────────────────────────────────┘            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 実装予定

- [ ] `bicep/step01-container-registry/README.md` の更新
  - [ ] 前提条件に NAT Gateway を追加
  - [ ] ACR Tasks の手順から `az acr update` コマンドを削除
  - [ ] イメージ確認セクションの簡素化
- [ ] `docs/00-prerequisites.md` の更新
  - [ ] NAT Gateway の前提条件を追加
  - [ ] ACR ファイアウォール設定手順を追加
- [ ] `README.md` の更新
  - [ ] 前提条件セクションに NAT Gateway を追加
- [ ] アーキテクチャ図の更新
  - [ ] NAT Gateway をアーキテクチャに追加
- [ ] `docs/deployment-guide.md` の更新（存在する場合）

## 依存関係

この Issue は以下の Issue が完了した後に実施:
- [internal_rag_step_by_step #2: Step 01 への NAT Gateway 統合](https://github.com/matakaha/internal_rag_step_by_step/issues/2)

## 参考リンク

- [Azure NAT Gateway](https://learn.microsoft.com/ja-jp/azure/nat-gateway/nat-overview)
- [ACR ネットワークルール](https://learn.microsoft.com/ja-jp/azure/container-registry/container-registry-access-selected-networks)
- [ACR Tasks](https://learn.microsoft.com/ja-jp/azure/container-registry/container-registry-tasks-overview)
