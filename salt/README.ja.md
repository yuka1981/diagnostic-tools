> このドキュメントは [README.md](README.md) の日本語翻訳版です。

# Salt モジュールデプロイ — 運用ガイド

このディレクトリには、HPC クラスタノードを管理するための SaltStack カスタムモジュール、
ステートファイル、および Reactor 構成が含まれています。Salt はコンピュートノードから
ハードウェアインベントリを収集し、ベンチマーク（HPCG および MLC）をリモートで実行
するために使用されます。

Salt master（マスターサーバー）は Ansible によって自動的にデプロイおよび設定されます。
稼働開始後、master は Git（GitFS 経由）からこのディレクトリを取得するため、
追跡対象ブランチにマージされた変更は自動的に反映されます。

---

## 目次

1. [前提条件](#前提条件)
2. [ディレクトリ構成](#ディレクトリ構成)
3. [セットアップガイド](#セットアップガイド)
4. [テスト](#テスト)
5. [カスタムモジュールリファレンス](#カスタムモジュールリファレンス)
6. [ベンチマークオーケストレーション](#ベンチマークオーケストレーション)
7. [Reactor イベント](#reactor-イベント)
8. [トラブルシューティング](#トラブルシューティング)
9. [セキュリティに関する注意事項](#セキュリティに関する注意事項)

---

## 前提条件

作業を始める前に、以下を準備してください。

- **Ansible 2.14 以上**がコントロールマシン（ノートPC またはジャンプホスト）にインストールされていること。
- コントロールマシンから全ターゲットサーバー（master および minion）への **SSH アクセス**が可能で、sudo 権限を持つユーザーであること。
- **ターゲットサーバー**が Rocky Linux 9 / RHEL 9 / AlmaLinux 9、または Ubuntu 20.04 以上 / Debian 11 以上で稼働していること。Ansible ロールは OS ファミリーを自動検出し、`dnf`（RHEL 系）または `apt`（Debian 系）を適切に使用します。
- Salt master と全 minion（管理対象）ノード間で、ポート **4505** および **4506**（Salt の ZeroMQ トランスポート）の**ネットワーク接続**が確保されていること。
- Salt master 上で **ポート 8000** が Salt REST API 用に開放されていること（Rails アプリケーションが使用します）。
- **GitHub パーソナルアクセストークン**（またはマシンアカウントトークン）にリポジトリへの読み取り権限があること。master が GitFS 経由でステートを取得するために必要です。
- ユニットテストをローカルで実行する場合は、**Python 3.8 以上**および **pytest** がインストールされていること。

---

## ディレクトリ構成

```
salt/
├── _modules/                    # Salt カスタム実行モジュール
│   ├── benchmark.py             # ベンチマーク実行 (HPCG, MLC)
│   └── inventory.py             # システムインベントリ収集
├── _tests/                      # カスタムモジュールのユニットテスト
│   ├── __init__.py
│   ├── test_benchmark.py        # benchmark モジュールのテスト
│   └── test_inventory.py        # inventory モジュールのテスト
├── benchmark/                   # ベンチマークオーケストレーション用 Salt ステートファイル
│   ├── hpcg/
│   │   ├── init.sls             # HPCG メインオーケストレーター (prepare, execute, collect を含む)
│   │   ├── prepare.sls          # 作業ディレクトリの作成と hpcg バイナリの確認
│   │   ├── execute.sls          # module.run 経由で benchmark.run_hpcg を実行
│   │   └── collect.sls          # cp.push_dir で成果物を master に送信
│   └── mlc/
│       ├── init.sls             # MLC メインオーケストレーター (prepare, execute, collect を含む)
│       ├── prepare.sls          # 作業ディレクトリの作成と mlc バイナリの確認
│       ├── execute.sls          # module.run 経由で benchmark.run_mlc を実行
│       └── collect.sls          # cp.push_dir で成果物を master に送信
├── master.d/
│   └── api.conf                 # Salt API 設定のリファレンスコピー (実際の設定は Ansible でデプロイ)
└── reactor/
    ├── job_return.sls           # ベンチマークジョブ完了時に Rails へ POST
    └── presence_change.sls      # minion の接続・切断時に Rails へ POST
```

Salt をデプロイする Ansible ファイルは、リポジトリルートの `ansible/` 配下にあります。

```
ansible/
├── ansible.cfg                          # Ansible 設定 (ロールパス, インベントリ, Vault)
├── playbooks/
│   └── salt.yml                         # メインプレイブック (master と minion の2つのプレイ)
├── inventory/
│   ├── hosts.yml                        # インベントリファイル (INI 形式)
│   └── group_vars/
│       ├── salt_minions.yml             # minion グループ変数
│       └── salt_master/
│           ├── main.yml                 # シークレット以外の master 変数
│           ├── vault.yml                # 暗号化されたシークレット (Git には含めない)
│           └── vault.yml.example        # 暗号化シークレットのテンプレート
└── roles/
    ├── salt_master/                     # Salt master のインストールと設定
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/
    │   │   ├── main.yml
    │   │   ├── install.yml              # APT リポジトリ + パッケージ
    │   │   ├── configure.yml            # api.conf のデプロイ
    │   │   ├── gitfs.yml                # GitFS バックエンドの設定
    │   │   ├── auth.yml                 # PAM 認証（関数レベルの ACL 付き）
    │   │   ├── reactor.yml              # Reactor SLS ファイルのデプロイ
    │   │   └── service.yml              # サービスの有効化と起動
    │   └── templates/
    │       ├── api.conf.j2
    │       ├── auth.conf.j2
    │       ├── gitfs.conf.j2
    │       ├── reactor.conf.j2
    │       ├── job_return.sls.j2
    │       └── presence_change.sls.j2
    └── salt_minion/                     # Salt minion のインストールと設定
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/
        │   ├── main.yml
        │   ├── install.yml              # APT リポジトリ + パッケージ
        │   ├── configure.yml            # minion を master に向ける設定
        │   └── service.yml              # salt-minion の有効化と起動
        └── templates/
            └── minion.conf.j2
```

---

## セットアップガイド

### ステップ 1: Ansible インベントリの設定

`salt_master`（1台）と `salt_minions`（1台以上のコンピュートノード）の2つのホストグループを定義するインベントリファイルを作成します。

ファイルを `ansible/inventory/hosts.yml` に作成してください。

```ini
[salt_master]
salt-master-01  ansible_host=10.0.0.1

[salt_minions]
compute-01      ansible_host=10.0.1.1
compute-02      ansible_host=10.0.1.2
compute-03      ansible_host=10.0.1.3

[all:vars]
ansible_user=deploy
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

ホスト名、IP アドレス、SSH 設定は実際の環境に合わせて変更してください。

---

### ステップ 2: 変数の設定

`ansible/inventory/group_vars/salt_master/main.yml` を環境に合わせて編集してください。デフォルト値は以下の通りです。

```yaml
salt_version: "3006"

# GitFS -- master はこのリポジトリから salt/ ステートを取得します
salt_gitfs_user: "machine-account"
salt_gitfs_branch: "develop"
salt_gitfs_repo: "https://github.com/yuka1981/diagnostic-tools.git"
salt_gitfs_update_interval: 60

# Salt REST API
salt_api_port: 8000
salt_api_user: "rails_salt_user"
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"

# ネットワーク
salt_master_address: "10.0.0.1"
rails_webhook_url: "https://your-rails-app.com/api/v1/salt/events"

# Vault 暗号化シークレットへの参照（実際の値をここに記載しないでください）
salt_gitfs_token: "{{ vault_salt_gitfs_token }}"
salt_api_password: "{{ vault_salt_api_password }}"
```

更新が必要な主な値：

| 変数 | 設定内容 |
|---|---|
| `salt_master_address` | minion が master に接続するために使用する IP またはホスト名 |
| `salt_gitfs_repo` | このリポジトリの Git URL |
| `salt_gitfs_branch` | master が追跡するブランチ（例: `develop` または `main`） |
| `rails_webhook_url` | Rails の webhook エンドポイントの完全な URL |
| `salt_api_ssl_cert` / `salt_api_ssl_key` | master 上の SSL 証明書と秘密鍵のパス |

minion ロールは `ansible/roles/salt_minion/defaults/main.yml` のデフォルト値を使用します。

```yaml
salt_version: "3006"
salt_master_address: "salt"
```

master のホスト名が `salt` として名前解決できない場合は、`group_vars/salt_minions.yml` ファイルまたはインベントリで `salt_master_address` をオーバーライドしてください。

---

### ステップ 3: Ansible Vault の作成

シークレット（GitFS 用の GitHub トークンと Salt API パスワード）は暗号化された Vault ファイルに保存する必要があります。テンプレートが用意されています。

```bash
# サンプルファイルをコピー
cp ansible/inventory/group_vars/salt_master/vault.yml.example \
   ansible/inventory/group_vars/salt_master/vault.yml

# ファイルを編集してプレースホルダー値を置換し、暗号化
ansible-vault encrypt ansible/inventory/group_vars/salt_master/vault.yml
```

暗号化する前に、`vault.yml` を編集してプレースホルダー値を置換してください。

```yaml
vault_salt_gitfs_token: "ghp_your_actual_github_token_here"
vault_salt_api_password: "a_strong_random_password"
```

> **注意:** 暗号化されていない `vault.yml` を絶対にバージョン管理にコミットしないでください。`.example` ファイルのみをチェックインしてください。

---

### ステップ 4: Salt Master のデプロイ

`--limit` フラグを付けてプレイブックを実行し、最初に master のみをデプロイします。

```bash
cd ansible

ansible-playbook playbooks/salt.yml \
  --limit salt_master \
  --ask-vault-pass
```

> **注意:** `ansible.cfg` ファイルでデフォルトのインベントリと Vault パスワードファイルが設定されているため、`ansible.cfg` が設定済みであれば `-i` は不要です。Vault パスワードの入力プロンプトを省略したい場合は、`ansible.cfg` で `vault_password_file = ~/.vault_pass` を設定してください。

このプレイブックは以下を実行します。

1. SaltStack パッケージリポジトリ（`packages.broadcom.com` から）を追加し、`salt-master` と `salt-api` をインストールします。RHEL の場合は EPEL と Salt の内蔵 Python への `pygit2` のインストール（`salt-pip` 経由）も行います。
2. API 認証用の PAM ユーザー（`rails_salt_user`）を作成します。
3. `/etc/salt/master.d/` 配下に設定ファイルをデプロイします。
   - `api.conf` -- REST API 設定（ポート 8000、SSL、Tornado）
   - `gitfs.conf` -- このリポジトリを指す GitFS バックエンド
   - `auth.conf` -- 関数レベルの権限付き PAM 外部認証
   - `reactor.conf` -- Reactor のイベントから SLS へのマッピング
4. Reactor SLS ファイルを `/srv/salt/reactor/` にデプロイします。
5. `salt-master` と `salt-api` サービスを有効化して起動します。

master が稼働していることを確認します。

```bash
ssh salt-master-01 'sudo systemctl status salt-master salt-api'
```

---

### ステップ 5: Salt Minion のデプロイ

```bash
cd ansible

ansible-playbook playbooks/salt.yml \
  --limit salt_minions \
  --ask-vault-pass
```

このプレイブックは以下を実行します。

1. SaltStack パッケージリポジトリを追加し、`salt-minion` をインストールします。
2. `/etc/salt/minion.d/master.conf` をデプロイし、minion を master アドレスに向けます。
3. `salt-minion` サービスを有効化して起動します。

> **注意:** `--limit` を省略すると、master と minion の両方を一度にデプロイできます。プレイブックは master プレイを最初に実行し、その後 minion プレイを実行します。

---

### ステップ 6: Minion 鍵の受け入れ

minion が起動すると、公開鍵を master に送信します。master が minion と通信するには、これらの鍵を受け入れる必要があります。

Salt master 上で以下を実行します。

```bash
# 保留中の鍵を一覧表示
sudo salt-key --list unaccepted

# 特定の minion を受け入れ
sudo salt-key --accept compute-01

# または保留中の全鍵を一括受け入れ
sudo salt-key --accept-all
```

受け入れ済みの minion に到達できることを確認します。

```bash
sudo salt '*' test.ping
```

期待される出力：

```
compute-01:
    True
compute-02:
    True
compute-03:
    True
```

> **注意:** `test.ping` が出力なしまたはタイムアウトになる場合は、master と minion 間でポート 4505 および 4506 が開放されていることを確認してください。詳細は[トラブルシューティング](#トラブルシューティング)を参照してください。

---

### ステップ 7: カスタムモジュールの同期

カスタム実行モジュール（`inventory` と `benchmark`）はこのリポジトリの `salt/_modules/` にあります。master は GitFS 経由でこれらを取得しますが、使用する前に各 minion にダウンロードする必要があります。

```bash
# 全 minion にモジュールを同期
sudo salt '*' saltutil.sync_modules
```

期待される出力：

```
compute-01:
    - modules.inventory
    - modules.benchmark
compute-02:
    - modules.inventory
    - modules.benchmark
```

> **注意:** モジュール同期は master の再起動時（Ansible ハンドラー経由）に自動的に実行されますが、初回デプロイ後やモジュールコードを更新した際は手動で実行してください。

---

### ステップ 8: セットアップの検証

すべてが正しく動作していることを確認するため、いくつかのコマンドを実行します。

```bash
# 全 minion が応答するか確認
sudo salt '*' test.ping

# カスタム inventory モジュールが利用可能か確認
sudo salt 'compute-01' sys.doc inventory

# 単一ノードから DMI 情報を収集
sudo salt 'compute-01' inventory.collect_dmi

# 全ノードから CPU トポロジーを収集
sudo salt '*' inventory.collect_cpu

# grains（Salt 組み込みのシステム情報）を確認
sudo salt 'compute-01' grains.items
```

`inventory.collect_dmi` が `dmidecode not found` のエラーを返す場合は、minion 上に `dmidecode` がインストールされていることを確認してください（`sudo apt install dmidecode`）。

---

## テスト

### ユニットテストのローカル実行

ユニットテストは `salt/_tests/` にあり、pytest と unittest.mock を使用してシステムコールをシミュレートします。実行に Salt のインストールは不要です。

```bash
# リポジトリルートから実行
python -m pytest salt/_tests/ -v
```

期待される出力：

```
salt/_tests/test_inventory.py::TestCollectDmi::test_collect_dmi_returns_structured_data PASSED
salt/_tests/test_inventory.py::TestCollectDmi::test_collect_dmi_handles_missing_dmidecode PASSED
salt/_tests/test_inventory.py::TestCollectNuma::test_collect_numa_returns_topology PASSED
salt/_tests/test_inventory.py::TestCollectNuma::test_collect_numa_handles_no_numa PASSED
salt/_tests/test_inventory.py::TestCollectNetworkV2::test_collect_network_v2_returns_devices PASSED
salt/_tests/test_inventory.py::TestCollectNetworkV2::test_collect_network_v2_handles_lshw_failure PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_returns_list_of_devices PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_handles_empty_output PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_handles_no_devices PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_collect_meminfo_parses_proc_meminfo PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_parse_proc_meminfo_handles_empty PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_parse_proc_meminfo_handles_plain_integers PASSED
salt/_tests/test_benchmark.py::TestRunHpcg::test_run_hpcg_returns_results PASSED
salt/_tests/test_benchmark.py::TestRunHpcg::test_run_hpcg_handles_failure PASSED
salt/_tests/test_benchmark.py::TestCancel::test_cancel_sends_sigterm PASSED
salt/_tests/test_benchmark.py::TestCancel::test_cancel_returns_error_when_no_process PASSED
```

### 実環境の Minion でのインベントリ収集テスト

Salt master と minion がデプロイされたら、各インベントリ関数をテストします。

```bash
# DMI データ（BIOS、システム、ベースボード、メモリ DIMM）
sudo salt 'compute-01' inventory.collect_dmi

# /proc/meminfo からのメモリ統計
sudo salt 'compute-01' inventory.collect_meminfo

# NUMA トポロジー（ノード数、CPU リスト、ノードごとのメモリ）
sudo salt 'compute-01' inventory.collect_numa

# CPU トポロジー（ソケット、コア、スレッド、モデル名、フラグ）
sudo salt 'compute-01' inventory.collect_cpu

# lshw によるネットワークデバイス情報（名前、ドライバー、速度、MAC、ベンダー）
sudo salt 'compute-01' inventory.collect_network_v2
```

### ベンチマーク実行のテスト

> **注意:** ベンチマークバイナリ（`hpcg` と `mlc`）は事前に minion にインストールされ、`$PATH` にある必要があります（MLC の場合は `binary_path` でフルパスを指定することもできます）。

```bash
# 単一ノードで HPCG ベンチマークを実行
sudo salt 'compute-01' benchmark.run_hpcg \
  work_dir=/tmp/hpcg \
  run_id=test-run-001

# クイックプロファイルで MLC ベンチマークを実行
sudo salt 'compute-01' benchmark.run_mlc \
  work_dir=/tmp/mlc \
  run_id=test-run-002 \
  binary_path=/opt/mlc/mlc \
  profile=quick
```

---

## カスタムモジュールリファレンス

### inventory モジュール

| 関数 | 説明 | 主なシステム依存 |
|---|---|---|
| `inventory.collect_dmi()` | `dmidecode -t 0,1,2,17` を使用して BIOS、システム、ベースボード、メモリ DIMM の詳細を収集します。`bios`、`system`、`baseboard`、`memory`（DIMM のリスト）をキーとする辞書を返します。 | `dmidecode` |
| `inventory.collect_meminfo()` | `/proc/meminfo` を解析し、kB 単位のメモリ値の辞書を返します（例: `MemTotal`、`MemFree`、`SwapTotal`）。 | なし（`/proc/meminfo` を読み取り） |
| `inventory.collect_numa()` | `/sys/devices/system/node/` から NUMA トポロジーを読み取ります。`node_count` と、ノード番号から `cpulist` および `memory_kb` へのマッピングを含む `nodes` 辞書を返します。 | なし（`/sys` を読み取り） |
| `inventory.collect_cpu()` | `/proc/cpuinfo` を解析して CPU トポロジーを抽出します。`model_name`、`sockets`、`cores`、`cores_per_socket`、`threads`、`threads_per_core`、`flags` を返します。 | なし（`/proc/cpuinfo` を読み取り） |
| `inventory.collect_network_v2()` | `lshw -class network -json` を使用して NIC 情報を収集します。各インターフェースの `name`、`product`、`vendor`、`mac`、`driver`、`speed`、`link`、`pci_slot` を含む `devices` リストを返します。 | `lshw` |

### benchmark モジュール

| 関数 | 説明 | パラメータ |
|---|---|---|
| `benchmark.run_hpcg(work_dir, run_id, timeout=3600)` | 指定された作業ディレクトリで `hpcg` バイナリを実行します。ステータス（`PASS`/`FAIL`）、解析されたメトリクス（例: `gflops`）、タイムスタンプ、ログ内容、成果物ファイルパスのリストを返します。 | `work_dir` (str), `run_id` (str), `timeout` (int, 秒) |
| `benchmark.run_mlc(work_dir, run_id, binary_path='mlc', profile='quick', timeout=3600)` | MLC を実行します。`quick` プロファイルでは、アイドルレイテンシとピーク注入帯域幅を測定します。MLC 固有のメトリクス（例: `idle_latency_ns`）を含む `run_hpcg` と同じ構造を返します。 | `work_dir` (str), `run_id` (str), `binary_path` (str), `profile` (str), `timeout` (int, 秒) |
| `benchmark.cancel()` | `pgrep` で実行中の `hpcg` または `mlc` プロセスを検索し、SIGTERM を送信します。`{success: True, pid: ...}` またはエラー辞書を返します。 | なし |

---

## ベンチマークオーケストレーション

ベンチマークは、実行モジュールを直接呼び出すか、ワークフロー全体（prepare、execute、collect）をオーケストレーションする Salt ステートを適用して実行できます。

### Salt ステート経由での実行（推奨）

`salt/benchmark/` 配下のステートファイルは、3 フェーズのワークフローを提供します。

1. **Prepare（準備）** -- 作業ディレクトリを作成し、ベンチマークバイナリがインストールされていることを確認します。
2. **Execute（実行）** -- カスタム実行モジュール経由でベンチマークを実行します。
3. **Collect（収集）** -- `cp.push_dir` を使用して、minion から master に出力成果物を送信します。

#### HPCG

```bash
sudo salt 'compute-01' state.apply benchmark.hpcg \
  pillar='{"run_id": "hpcg-20260131-001", "work_dir": "/tmp/hpcg"}'
```

#### MLC

```bash
sudo salt 'compute-01' state.apply benchmark.mlc \
  pillar='{"run_id": "mlc-20260131-001", "work_dir": "/tmp/mlc", "binary_path": "/opt/mlc/mlc", "profile": "quick"}'
```

### 複数ノードでの実行

グロブまたはリストターゲットを使用して、複数ノードでベンチマークを実行できます。

```bash
# 全コンピュートノード
sudo salt 'compute-*' state.apply benchmark.hpcg \
  pillar='{"run_id": "hpcg-batch-001", "work_dir": "/tmp/hpcg"}'

# 特定のノード
sudo salt -L 'compute-01,compute-02' state.apply benchmark.mlc \
  pillar='{"run_id": "mlc-batch-001", "work_dir": "/tmp/mlc", "binary_path": "mlc"}'
```

### 成果物の保存先

collect フェーズの後、成果物は master に送信され、以下のパスに保存されます。

```
/var/cache/salt/master/minions/<minion-id>/files/<work_dir>/
```

例えば、`compute-01` で `work_dir=/tmp/hpcg` の場合：

```
/var/cache/salt/master/minions/compute-01/files/tmp/hpcg/
```

---

## Reactor イベント

Salt master はイベントバス上の 2 つのイベントパターンを監視し、HTTP POST 経由で Rails アプリケーションに転送します。

### プレゼンス変更

- **イベントタグ:** `salt/presence/change`
- **トリガー:** minion が master に接続または切断したとき。
- **Reactor ファイル:** `/srv/salt/reactor/presence_change.sls`
- **Rails に送信されるペイロード:**

```json
{
  "tag": "salt/presence/change",
  "new": ["compute-03"],
  "lost": []
}
```

これにより、Rails アプリケーションはどのノードがオンラインかを追跡できます。

### ベンチマークジョブのリターン

- **イベントタグ:** `salt/job/ret/*`
- **トリガー:** minion 上でジョブが完了したとき。Reactor は関数名に `benchmark` が含まれるジョブ、または適用されたステートに `benchmark` が含まれるジョブをフィルタリングします。
- **Reactor ファイル:** `/srv/salt/reactor/job_return.sls`
- **Rails に送信されるペイロード:**

```json
{
  "tag": "salt/job/ret/20260131120000000000",
  "fun": "benchmark.run_hpcg",
  "id": "compute-01",
  "jid": "20260131120000000000",
  "retcode": 0,
  "return": { "status": "PASS", "metrics": { "gflops": 45.67 }, "..." : "..." }
}
```

両方の Reactor は、master 設定（`rails_api_token`）から読み取った Bearer トークンを使用して Rails に認証します。

---

## トラブルシューティング

このセクションでは、実際のデプロイで遭遇した問題と、段階的な解決策を記載しています。

### デプロイチェックリスト

初回デプロイ時は、以下の順序で問題が発生する傾向があります。次のステップに進む前に、各項目を確認してください。

```
1. Ansible プレイブックがエラーなく実行される
   - [ ] Salt パッケージがインストールされる（DNS 失敗時はリポジトリ URL を確認）
   - [ ] group_vars が正しく読み込まれる（ディレクトリ構成を確認）
   - [ ] PAM ユーザーが作成される

2. salt-master サービスが起動する
   - [ ] 設定ファイルの所有者が salt:salt である（root:root ではない）
   - [ ] SSL 証明書が /etc/salt/pki/api/ に存在する
   - [ ] ポート 4505、4506、8000 がリッスンしている

3. salt-minion が接続する
   - [ ] ファイアウォールがポート 4505 と 4506 を許可している
   - [ ] minion の設定が正しい master アドレスを指している
   - [ ] minion の鍵が master で受け入れられている（salt-key -A）

4. カスタムモジュールが動作する
   - [ ] GitFS がファイルを提供する（salt-run fileserver.file_list）
   - [ ] pygit2 が Salt の Python にインストールされている（システム Python ではない）
   - [ ] モジュールが minion に同期されている（salt '*' saltutil.sync_modules）

5. Salt API が応答する
   - [ ] PAM 認証が動作する（RHEL での shadow グループ権限）
   - [ ] API ログインがトークンを返す
   - [ ] API コマンドが結果を返す（master が完全に初期化済み）
```

各主要ステップの後に `sudo salt '*' test.ping` を使用して接続性を確認してください。

### Salt リポジトリ URL: "Could not resolve host: repo.saltproject.io"

**症状:** Ansible のインストールタスクが `repo.saltproject.io` からパッケージをダウンロードしようとした際に、DNS またはコネクションエラーで失敗します。

**原因:** Salt Project は 2024 年 10 月に `repo.saltproject.io` を停止し、Broadcom のインフラに移行しました。旧 URL は名前解決できなくなっています。

**修正:** このリポジトリの Ansible ロールはすでに新しい URL を使用しています。このエラーが表示される場合は、古いバージョンのロールを実行している可能性があります。正しいリポジトリソースは以下の通りです。

| OS ファミリー | リポジトリ URL |
|---|---|
| RHEL / Rocky | `https://packages.broadcom.com/artifactory/saltproject-rpm/` |
| Debian / Ubuntu | `https://packages.broadcom.com/artifactory/saltproject-deb/` |
| GPG キー | `https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public` |

RHEL の場合、最も簡単な方法は公式のリポジトリファイルをダウンロードすることです。

```bash
curl -fsSL https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.repo \
  | sudo tee /etc/yum.repos.d/salt.repo
```

---

### group_vars が読み込まれない: "'salt_api_password' is undefined"

**症状:** プレイブックが `'salt_api_password' is undefined` または `group_vars/` に明確に定義されている変数に関する同様のエラーで失敗します。`ansible -m debug -a "var=salt_api_password" salt_master` は正常に動作するのに、`ansible-playbook` では動作しません。

**原因:** Ansible は **インベントリディレクトリ**または**プレイブックディレクトリ**を基準に `group_vars/` を解決します。プロジェクトルートからの相対パスではありません。`group_vars/` が `ansible/group_vars/` にあるのにインベントリが `ansible/inventory/hosts.yml` にある場合、プレイブックは変数を見つけられません。

**修正:** `group_vars/` を `inventory/` ディレクトリ内に配置してください。

```
ansible/inventory/
├── hosts.yml
└── group_vars/
    ├── salt_minions.yml
    └── salt_master/
        ├── main.yml            # シークレット以外の変数
        ├── vault.yml           # 暗号化されたシークレット
        └── vault.yml.example
```

また、同じ階層に `group_vars/salt_master.yml`（ファイル）と `group_vars/salt_master/`（ディレクトリ）の両方を置かないでください。Ansible はどちらか一方しか読み込まない場合があります。ファイルをディレクトリ内に `main.yml` として移動してください。

---

### group_vars のファイルとディレクトリの競合

**症状:** `group_vars/salt_master.yml` の一部の変数は読み込まれるが、`group_vars/salt_master/vault.yml` の Vault 変数は読み込まれない（またはその逆）。

**原因:** ファイル `group_vars/salt_master.yml` とディレクトリ `group_vars/salt_master/` の両方が存在すると競合が発生します。Ansible はどちらか一方しか処理しない場合があります。

**修正:** ディレクトリ形式のみを使用してください。

```bash
# ファイルをディレクトリ内に移動
mv group_vars/salt_master.yml group_vars/salt_master/main.yml
```

---

### 設定ファイルの権限エラー: salt-master が起動に失敗する

**症状:** `systemctl status salt-master` が `failed` と表示され、`PermissionError: [Errno 13] Permission denied: '/etc/salt/master.d/api.conf'` が出力されます。

**原因:** RHEL/Rocky では、`salt-master` サービスは `salt` ユーザー（root ではない）として実行されます。`/etc/salt/master.d/` 内の設定ファイルが `root:root` 所有でモード `0640` の場合、`salt` ユーザーは読み取りできません。

**修正:** `/etc/salt/master.d/` にデプロイされる全設定ファイルは `salt:salt` 所有にする必要があります。

```bash
# master 上での応急処置
sudo chown salt:salt /etc/salt/master.d/*.conf
sudo systemctl restart salt-master
```

このリポジトリの Ansible ロールは、全テンプレートタスクで `owner: salt` と `group: salt` を設定しています。このエラーが発生する場合は、ロールファイルが以下を使用しているか確認してください。

```yaml
- name: Deploy configuration
  ansible.builtin.template:
    src: some_config.j2
    dest: /etc/salt/master.d/some_config.conf
    owner: salt
    group: salt
    mode: '0640'
```

---

### SSL 証明書がない: salt-api がポート 8000 でリッスンしていない

**症状:** `ss -tlnp | grep 8000` で何も表示されません。`salt-api` サービスは実行中でも、REST エンドポイントに到達できません。

**原因:** `api.conf` が存在しない SSL 証明書/鍵ファイルを参照しています。

```yaml
rest_tornado:
  ssl_crt: /etc/salt/pki/api/cert.crt
  ssl_key: /etc/salt/pki/api/key.key
```

**修正:** 自己署名証明書を生成します（テスト用に適しています）。

```bash
sudo mkdir -p /etc/salt/pki/api
sudo openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/salt/pki/api/key.key \
  -out /etc/salt/pki/api/cert.crt \
  -subj "/CN=$(hostname)/O=SaltStack"
sudo chown salt:salt /etc/salt/pki/api/cert.crt /etc/salt/pki/api/key.key
sudo chmod 640 /etc/salt/pki/api/cert.crt /etc/salt/pki/api/key.key
sudo systemctl restart salt-api
```

Ansible ロールは自己署名証明書を自動的に生成します。本番環境では、組織の認証局（CA）の証明書に置き換えてください。

---

### pygit2 が見つからない: "gitfs is configured but could not be loaded"

**症状:** master ログに以下が表示されます。

```
[ERROR   ] gitfs is configured but could not be loaded, are pygit2 and libgit2 installed?
[CRITICAL] No suitable gitfs provider module is installed.
```

GitFS がファイルを返さず、`salt-run fileserver.file_list` が空になります。

**原因:** Salt 3006 以降（onedir パッケージ）は `/opt/saltstack/salt/bin/python3` に独自の Python をバンドルしています。システムの `python3-pygit2` パッケージは Salt から見えません。Salt はシステム Python を使用しないためです。

**修正:** Salt のバンドル Python に pygit2 をインストールします。

```bash
# RHEL: まず patchelf をインストール（pygit2 ホイールに必要）
sudo dnf install -y patchelf

# Salt の Python に pygit2 をインストール
sudo /opt/saltstack/salt/bin/pip3 install pygit2

# 新しいモジュールを読み込むために再起動
sudo systemctl restart salt-master

# 確認
sudo salt-run fileserver.update
sudo salt-run fileserver.file_list
```

> **注意:** システムの `python3-pygit2` パッケージ（`dnf` や `apt` でインストールしたもの）は Salt 3006 以降では使用されません。Salt の pip 経由でインストールする必要があります。

---

### PAM 認証の失敗: "Could not authenticate using provided credentials"

**症状:** Salt API ログインが 401 を返します。master ログに以下が表示されます。

```
unix_chkpwd: password check failed for user (rails_salt_user)
pam_unix(login:auth): authentication failure ... user=rails_salt_user
[ERROR   ] Pam auth failed for rails_salt_user
```

**原因:** RHEL/Rocky では、`salt-master` は `salt` ユーザー（root ではない）として実行されます。PAM は `unix_chkpwd` を使用して `/etc/shadow` に対するパスワード検証を行いますが、`/etc/shadow` のデフォルトモードは `0000` であり、`salt` ユーザーは読み取りできません。

さらに、PAM ユーザーのシェルが `/usr/sbin/nologin` の場合、PAM が認証を完全に拒否する可能性があります。

**修正（2 つの手順）:**

1. shadow グループ経由で `salt` ユーザーに `/etc/shadow` の読み取りアクセスを付与します。

```bash
sudo groupadd -f shadow
sudo usermod -aG shadow salt
sudo chgrp shadow /etc/shadow
sudo chmod g+r /etc/shadow
sudo systemctl restart salt-master
```

2. PAM ユーザーに有効なシェルを設定します。

```bash
sudo usermod -s /bin/bash rails_salt_user
```

このリポジトリの Ansible ロールは、これらの両方を自動的に処理します。

---

### Salt API コマンドがタイムアウト: "The master is not responding"

**症状:** API ログインは成功（トークンを返す）しますが、コマンド実行（`test.ping`、`get_minions` など）で以下が返されます。

```
Salt request timed out. The master is not responding.
```

**原因:** 以下の場合に発生する可能性があります。

- `salt-master` プロセスが完全に初期化されていない（起動後、全ワーカーが準備完了するまで 60〜90 秒かかります）。
- `MWorkerQueue` プロセスが CPU スピンループに陥っている（Salt 3006 の既知の ZMQ の問題）。確認方法: `ps aux | grep MWorkerQueue`
- master の初期化が完了する前に salt-api が起動された。

**修正:**

1. salt-api を停止し、salt-master を再起動して待機した後、salt-api を起動します。

```bash
sudo systemctl stop salt-api
sudo systemctl restart salt-master
sleep 60    # master が完全に初期化されるまで待機
sudo systemctl start salt-api
```

2. API を起動する前に master が正常であることを確認します。

```bash
# salt-api を起動する前に全ポートがリッスンしていること
sudo ss -tlnp | grep -E '4505|4506'

# CLI での ping が動作すること
sudo salt '*' test.ping --timeout=15
```

3. `MWorkerQueue` が高 CPU 使用率（50% 以上）の場合、停止してクリーンスタートします。

```bash
sudo systemctl stop salt-api
sudo systemctl stop salt-master
sudo rm -f /var/run/salt/master/*.ipc
sudo systemctl start salt-master
sleep 60
sudo systemctl start salt-api
```

> **注意:** `rest_tornado` バックエンド（このデプロイで使用）は、Salt 3006 では `rest_cherrypy` よりも推奨されます。CherryPy 関連のビジーループの問題を回避できるためです。

---

### ファイアウォールによる minion 接続のブロック

**症状:** minion の鍵が master に表示されません（`salt-key -L` で未承認の鍵が表示されない）。minion ログにタイムアウトエラーが表示されます。

**原因:** master のファイアウォールがポート 4505 と 4506 をブロックしています。

**修正（RHEL/Rocky の firewalld の場合）:**

```bash
# Salt master 上で実行
sudo firewall-cmd --permanent --add-port=4505/tcp
sudo firewall-cmd --permanent --add-port=4506/tcp
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload

# 確認
sudo firewall-cmd --list-ports
```

**必要なポート:**

| ポート | 方向 | プロトコル | 用途 |
|---|---|---|---|
| 4505 | Minion から Master | TCP | Salt パブリッシュ（ZeroMQ） |
| 4506 | Minion から Master | TCP | Salt リターン（ZeroMQ） |
| 8000 | Rails から Master | TCP | Salt REST API (HTTPS) |

> **注意:** 環境で `firewalld` を使用している場合は、Ansible ロールにファイアウォールタスクを追加することを検討してください。現在のロールはファイアウォールルールを管理していません。

> **注意：** Ansible の `salt_master` ロールには `firewall.yml` タスクが含まれており、
> firewalld がアクティブな場合にこれらのポートを自動的に開放します。playbook を
> 再実行するだけでファイアウォールの問題を修正でき、手動操作は不要です。

---

### SELinux が Salt 通信をブロック

**症状：** Salt コマンドが `Message timed out` や `Unable to connect to the salt
master publisher` でタイムアウトし、`ausearch -m AVC` で Salt 関連の拒否が表示される。

**原因：** SELinux が Enforcing モードの場合、Salt の ZeroMQ IPC ソケット、ポート
バインド、または `/opt/saltstack/salt/` のバンドル Python の実行がブロックされる
可能性があります。

**診断：**

```bash
# SELinux モードを確認
sudo getenforce

# Salt 関連の AVC 拒否を検索
sudo ausearch -m AVC -ts today | grep -i salt

# 拒否の原因を分析
sudo ausearch -m AVC -ts today | grep salt | audit2why
```

**修正 — Ansible playbook（推奨）：**

Ansible の `salt_master` および `salt_minion` ロールには `selinux.yml` タスクが
含まれており、SELinux が Enforcing の場合にカスタム SELinux ポリシーモジュールを
自動的にデプロイします。playbook が処理する項目：

- SELinux 管理ツールのインストール（`policycoreutils-python-utils`、`checkpolicy`）
- ポート 8000 を salt-api 用に `http_port_t` としてラベル付け
- `httpd_can_network_connect` SELinux ブール値の有効化
- Salt ディレクトリのファイルコンテキスト復元（`/etc/salt`、`/var/cache/salt`、
  `/var/run/salt`、`/var/log/salt`、`/opt/saltstack/salt`）
- カスタム Type Enforcement ポリシーモジュールのコンパイルとインストール
  （`salt_master_selinux`、`salt_minion_selinux`）

playbook を再実行して適用：

```bash
cd ansible/
ansible-playbook playbooks/salt.yml --tags selinux
```

**手動修正：**

```bash
# カスタムポリシーがインストールされているか確認
sudo semodule -l | grep salt

# インストールされていない場合、一時的に permissive に設定して拒否を収集
sudo setenforce 0

# Salt 機能を実行後、監査ログからポリシーを生成
sudo ausearch -m AVC -ts recent | grep salt | audit2allow -M salt_local
sudo semodule -i salt_local.pp

# enforcing を再有効化
sudo setenforce 1
```

**カスタムポリシーモジュールの対象：**

| 権限 | 用途 |
|---|---|
| ZeroMQ ポートバインド（4505/4506） | Master パブリッシュおよびリターンチャネル |
| IPC ソケット管理（`/var/run/salt/`） | プロセス間通信 |
| バンドル Python 実行（`/opt/saltstack/salt/`） | Salt onedir パッケージランタイム |
| HTTP ポートバインド（8000） | Salt API（master のみ） |
| SSL 証明書アクセス | Salt API HTTPS |

---

### Minion の鍵が表示されない

**症状:** minion を起動した後、`salt-key --list unaccepted` に保留中の鍵が表示されません。

**考えられる原因:**

- minion がポート 4505 で master に到達できない。ファイアウォールルールを確認してください（上記参照）。
- minion の設定にある `salt_master_address` が名前解決できない。確認方法: `ssh compute-01 'getent hosts <master-address>'`
- minion サービスが実行されていない: `ssh compute-01 'sudo systemctl status salt-minion'`

```bash
# minion 上で接続エラーのログを確認
sudo journalctl -u salt-minion --no-pager -n 50
```

---

### カスタムモジュールが見つからない

**症状:** `salt 'compute-01' inventory.collect_dmi` を実行すると `'inventory.collect_dmi' is not available` が返されます。

**修正:** モジュールを同期します。

```bash
sudo salt '*' saltutil.sync_modules
```

同期で空のリストが返される場合、master がまだ Git からモジュールを取得していない可能性があります。GitFS の更新を強制します。

```bash
sudo salt-run fileserver.update
sudo salt '*' saltutil.sync_modules
```

---

### ベンチマークバイナリが見つからない

**症状:** `benchmark.run_hpcg` またはステート適用で、バイナリが見つからないというエラーが返されます。

**修正:** minion にベンチマークバイナリをインストールし、システムの `$PATH` にあることを確認するか、MLC の場合は `binary_path` パラメータでフルパスを指定してください。

```bash
sudo salt 'compute-01' benchmark.run_mlc \
  work_dir=/tmp/mlc \
  run_id=test \
  binary_path=/usr/local/bin/mlc
```

---

### Reactor が発火しない

**症状:** Rails が webhook イベントを受信していません。

**確認方法:**

```bash
# Salt イベントバスをリアルタイムで監視
sudo salt-run state.event pretty=True

# master ログで Reactor エラーを検索
sudo grep -i reactor /var/log/salt/master | tail -20
```

master の group vars で `rails_webhook_url` が正しく設定されていること、および Rails アプリケーションが master から到達可能であることを確認してください。

---

## セキュリティに関する注意事項

### Ansible Vault

全シークレット（GitHub トークン、Salt API パスワード）は `ansible/inventory/group_vars/salt_master/vault.yml` の Ansible Vault 暗号化ファイルに保存されています。暗号化されていないサンプルファイル（`vault.yml.example`）には期待される変数名が記載されていますが、プレースホルダー値のみが含まれています。

- プレイブック実行時は必ず `--ask-vault-pass`（または `--vault-password-file`）を使用してください。
- 復号化されたシークレットを Git にコミットしないでください。

### PAM 認証

Salt API は PAM 外部認証を使用します。Ansible ロールはシステムユーザー（デフォルトでは `rails_salt_user`）を `no_log: true` で作成し、パスワードハッシュが Ansible の出力に表示されないようにしています。

ユーザーは RHEL システムでの PAM 認証を可能にするため、シェルとして `/bin/bash` で作成されます。ユーザーにはホームディレクトリがなくシステムアカウントであるため、対話的な SSH アクセスは意図していません。

### 関数レベルの権限

PAM ユーザーには、以下の Salt 関数のホワイトリストへのアクセスが付与されています。

- `grains.items`
- `inventory.*`
- `benchmark.run_hpcg`, `benchmark.run_mlc`, `benchmark.cancel`
- `test.ping`
- `state.apply`
- `cmd.run`
- `cp.push`, `cp.push_dir`
- `saltutil.sync_modules`
- Runner: `manage.status`

これにより、API ユーザーはこのリスト外の任意の Salt 関数を実行できなくなります。

### SSL/TLS

Salt REST API は、設定で指定された証明書と鍵を使用して Tornado 経由の HTTPS で構成されています。本番環境では必ず有効な証明書を使用してください。

### SELinux ポリシー

Salt には公式の SELinux ポリシーが付属していません。Ansible playbook がカスタム
Type Enforcement モジュール（`salt_master_selinux.te`、`salt_minion_selinux.te`）
をデプロイし、SELinux Enforcing モードで Salt が動作するために必要な最小限の権限を
付与します。ポリシーモジュールが許可する項目：

- ZeroMQ ポートバインドと IPC ソケット管理
- `/opt/saltstack/salt/` からの Salt バンドル Python の実行
- Salt CLI（`unconfined_t`）から master/minion IPC ソケットへの接続

新しい Salt モジュールや state 操作が追加の AVC 拒否をトリガーした場合、
`audit2allow` でポリシーを拡張できます：

```bash
sudo ausearch -m AVC -ts today | grep salt | audit2allow -M salt_custom
sudo semodule -i salt_custom.pp
```

### 制限された API クライアント

API 設定では、許可される netapi クライアントタイプを以下に制限しています。

- `local` -- minion 上で関数を実行
- `local_async` -- 非同期で関数を実行
- `runner` -- master 上で Runner 関数を実行

これにより、`wheel`（鍵や設定を変更できる）などの他のクライアントタイプの使用が防止されます。
