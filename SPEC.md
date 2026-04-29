# docling-serve-jp — 仕様書

## 概要

`quay.io/docling-project/docling-serve` の公式イメージをベースに、
**Tesseract 日本語パック（tessdata_best）** を追加した派生イメージを自動ビルドし、
`ghcr.io/<owner>/docling-serve-jp` として公開する GitHub Actions リポジトリを作成する。

---

## リポジトリ構成

```
docling-serve-jp/
├── .github/
│   └── workflows/
│       ├── build.yml          # メインビルドワークフロー
│       └── check-upstream.yml # 上流タグ監視（定期実行）
├── Dockerfile
├── README.md
└── .gitignore
```

---

## Dockerfile 仕様

### ベースイメージ

```
ARG BASE_TAG=latest
FROM quay.io/docling-project/docling-serve:${BASE_TAG}
```

- `BASE_TAG` はビルド時引数で渡す（例: `v1.17.0`, `latest`）

### 追加処理（root で実行）

1. **パッケージマネージャの判定と Tesseract 日本語パックインストール**

   ベースイメージは UBI (RHEL) 系のため `microdnf` または `dnf` を使用。
   フォールバックとして `apt-get` も試みる。

   ```dockerfile
   USER root

   RUN (microdnf install -y tesseract-langpack-jpn 2>/dev/null || \
        dnf install -y tesseract-langpack-jpn 2>/dev/null || \
        (apt-get update && apt-get install -y --no-install-recommends tesseract-ocr-jpn)) \
       && (microdnf clean all 2>/dev/null || dnf clean all 2>/dev/null || apt-get clean) \
       && rm -rf /var/lib/apt/lists/*
   ```

2. **tessdata_best の jpn.traineddata で上書き**

   apt/dnf で入る標準データより高精度な `tessdata_best` に差し替える。

   ```dockerfile
   RUN TESSDATA_DIR=$(find /usr /opt -name "tessdata" -type d 2>/dev/null | head -1) && \
       echo "tessdata dir: ${TESSDATA_DIR}" && \
       curl -fsSL -o "${TESSDATA_DIR}/jpn.traineddata" \
         https://github.com/tesseract-ocr/tessdata_best/raw/main/jpn.traineddata && \
       curl -fsSL -o "${TESSDATA_DIR}/jpn_vert.traineddata" \
         https://github.com/tesseract-ocr/tessdata_best/raw/main/jpn_vert.traineddata && \
       curl -fsSL -o "${TESSDATA_DIR}/eng.traineddata" \
         https://github.com/tesseract-ocr/tessdata_best/raw/main/eng.traineddata
   ```

3. **TESSDATA_PREFIX 環境変数をセット**

   ```dockerfile
   ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/
   ```

   ※ 実際のパスはビルド時に `find` で確認し、必要に応じて調整する。

4. **元のユーザーに戻す**

   ```dockerfile
   USER 1001
   ```

### ビルド確認コマンド（Dockerfile 内 RUN で実施）

```dockerfile
RUN tesseract --list-langs 2>&1 | grep -E "jpn|eng" || echo "WARNING: language check failed"
```

---

## GitHub Actions ワークフロー仕様

### 1. `build.yml` — メインビルド

#### トリガー

| トリガー | 条件 |
|---------|------|
| `workflow_dispatch` | 手動実行。`base_tag` 入力で上流タグを指定 |
| `push` (tags) | `v*` 形式のタグをプッシュ時 |
| `schedule` | `check-upstream.yml` から `repository_dispatch` で呼ばれる |

#### 入力パラメータ（`workflow_dispatch` 時）

| パラメータ名 | 型 | デフォルト | 説明 |
|---|---|---|---|
| `base_tag` | string | `latest` | ベースにする上流タグ（例: `v1.17.0`） |

#### 処理ステップ

```
1. Checkout
2. Docker Buildx のセットアップ
3. GHCR へのログイン（GITHUB_TOKEN 使用）
4. イメージタグの決定
   - base_tag が "latest" → ghcr.io/<owner>/docling-serve-jp:latest
   - base_tag が "vX.Y.Z" → ghcr.io/<owner>/docling-serve-jp:vX.Y.Z
                             ghcr.io/<owner>/docling-serve-jp:latest（同時付与）
5. docker buildx build --push
   --build-arg BASE_TAG=<base_tag>
   --platform linux/amd64,linux/arm64
   -t <tags>
6. イメージのダイジェスト出力（サマリーに記録）
```

#### タグ命名規則

上流タグ `vX.Y.Z` に対して以下のタグを付与:

- `ghcr.io/<owner>/docling-serve-jp:vX.Y.Z`
- `ghcr.io/<owner>/docling-serve-jp:latest`

#### シークレット・パーミッション

```yaml
permissions:
  contents: read
  packages: write
```

`GITHUB_TOKEN` のみ使用（外部シークレット不要）。

---

### 2. `check-upstream.yml` — 上流タグ監視

#### トリガー

```yaml
schedule:
  - cron: '0 2 * * *'  # 毎日 JST 11:00（UTC 02:00）
workflow_dispatch: {}
```

#### 処理ステップ

```
1. Quay.io API でタグ一覧を取得
   GET https://quay.io/api/v1/repository/docling-project/docling-serve/tag/
       ?limit=10&page=1&onlyActiveTags=true

2. 最新の vX.Y.Z 形式タグを抽出

3. GHCR で既存タグを確認
   GET https://ghcr.io/v2/<owner>/docling-serve-jp/tags/list
   （GITHUB_TOKEN で認証）

4. 未ビルドの新タグがあれば repository_dispatch で build.yml を起動
   event_type: "upstream-new-tag"
   client_payload: { base_tag: "vX.Y.Z" }

5. 新タグがなければスキップ（ログに記録して正常終了）
```

#### シークレット・パーミッション

```yaml
permissions:
  contents: read
  packages: read

# repository_dispatch を送るため PAT が必要
# シークレット: DISPATCH_TOKEN（repo スコープの PAT）
```

> **補足**: `repository_dispatch` は `GITHUB_TOKEN` では同一リポジトリへ発火できないため、
> `repo` スコープを持つ PAT を `DISPATCH_TOKEN` シークレットとして登録する必要がある。
> あるいは `check-upstream.yml` から直接 `build.yml` を `workflow_call` 経由で呼ぶ設計でも可。

---

## docker-compose.yml 側の変更（利用者向け参考）

```yaml
docling:
  image: ghcr.io/<owner>/docling-serve-jp:v1.17.0
  container_name: inferlab-docling
  restart: unless-stopped
  environment:
    DOCLING_SERVE_HOST: 0.0.0.0
    DOCLING_SERVE_PORT: 5001
    DOCLING_SERVE_ENABLE_UI: "true"
    DOCLING_SERVE_API_KEY: "sk-docling-serve-api-key"
    DOCLING_SERVE_ENABLE_REMOTE_SERVICES: "true"
    DOCLING_SERVE_MAX_SYNC_WAIT: 20000
    TESSDATA_PREFIX: /usr/share/tesseract/tessdata/
  ports:
    - 50001:5001
  volumes:
    - docling-data:/data
  networks:
    - llm-internal
```

Open WebUI 側の `DOCLING_PARAMS`:

```yaml
DOCLING_PARAMS: >-
  {
    "do_ocr": true,
    "ocr_engine": "tesseract",
    "ocr_lang": ["jpn", "eng"]
  }
```

---

## README.md に含める内容

- リポジトリの目的（1段落）
- 提供イメージ一覧（ghcr.io タグ表）
- docker-compose.yml での使い方
- ビルド手動実行方法（workflow_dispatch の操作手順）
- 上流との対応関係（タグ命名規則の説明）
- ライセンス（MIT、上流に準拠）

---

## 注意事項・既知の制約

### tessdata_best のダウンロード元
GitHub raw コンテンツ (`github.com/tesseract-ocr/tessdata_best/raw/main/`) から直接 `curl` する。
ファイルサイズは jpn: 約 15 MB、jpn_vert: 約 15 MB、eng: 約 4 MB。

### マルチプラットフォーム
`linux/amd64` および `linux/arm64` の両プラットフォームでビルドする。
ただし tessdata は CPU 非依存のデータファイルのため差異なし。

### TESSDATA_PREFIX のパス
ベースイメージのディストリビューションによってパスが異なる可能性がある。
Dockerfile 内で `find` コマンドにより実パスを確認しており、
もしパスが `/usr/share/tesseract/tessdata/` と異なる場合は `ENV TESSDATA_PREFIX` を修正すること。

### ベースイメージの非 root ユーザー
ベースイメージは `USER 1001` で動作している。
パッケージインストール時のみ `USER root` に切り替え、完了後に `USER 1001` へ戻す。

### tesseract バイナリの存在確認
ベースイメージに `tesseract` バイナリが含まれていない場合、
`ocr_engine: tesseract` は動作しない。
Dockerfile のビルド時に `tesseract --version` を実行して確認する。
