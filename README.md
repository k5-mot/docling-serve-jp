# docling-serve-jp

[quay.io/docling-project/docling-serve](https://quay.io/repository/docling-project/docling-serve) の公式イメージをベースに、**Tesseract 日本語パック（tessdata_best）** と **AIモデルのプリダウンロード** を追加した派生 Docker イメージを自動ビルドし、GHCR へ公開するリポジトリです。

---

## 提供イメージ

| タグ                                       | 説明                   |
| ------------------------------------------ | ---------------------- |
| `ghcr.io/<owner>/docling-serve-jp:latest`  | 上流 latest ベース     |
| `ghcr.io/<owner>/docling-serve-jp:vX.Y.Z` | 上流タグ対応バージョン |

> `<owner>` はこのリポジトリのオーナー名に置き換えてください。

---

## イメージの特徴

- Tesseract 日本語パック（tessdata_best: `jpn` / `jpn_vert` / `eng`）を追加
- AIモデルをビルド時にプリダウンロード済み（起動時のダウンロード不要・高速起動）
- HuggingFace オフラインモード（コンテナが外部に接続しない）

---

## モデルプロファイル

ビルド時に `MODEL_PROFILE` ビルド引数で取り込むモデルセットを選択できます（デフォルト: `high`）。

| プロファイル | 取り込まれるモデル |
| ------------ | ----------------- |
| `high` | layout, code_formula, tableformer, picture_classifier, granite_vision, granitedocling, granite_chart_extraction |
| `light` | layout, code_formula, tableformer, picture_classifier, smolvlm, smoldocling |
| `base` | layout, code_formula, tableformer, picture_classifier |

---

## docker-compose.yml での使い方

### GHCR の公開イメージを使う場合

```yaml
services:
  docling:
    image: ghcr.io/<owner>/docling-serve-jp:v1.17.0
    container_name: docling-jp
    restart: unless-stopped
    environment:
      DOCLING_SERVE_HOST: 0.0.0.0
      DOCLING_SERVE_PORT: 5001
      DOCLING_SERVE_ENABLE_UI: "true"
      DOCLING_SERVE_API_KEY: "sk-docling-serve-api-key"
      DOCLING_SERVE_ARTIFACTS_PATH: /opt/app-root/src/.cache/docling/models
      DOCLING_SERVE_LOAD_MODELS_AT_BOOT: "false"
      DOCLING_SERVE_MAX_SYNC_WAIT: 36000
    ports:
      - 50001:5001
    volumes:
      - docling-data:/data
    ulimits:
      nofile:
        soft: 65535
        hard: 65535

volumes:
  docling-data:
```

### ローカルでビルドして使う場合

```yaml
services:
  docling:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        BASE_TAG: v1.17.0
        MODEL_PROFILE: high
    container_name: docling-jp
    restart: unless-stopped
    environment:
      DOCLING_SERVE_HOST: 0.0.0.0
      DOCLING_SERVE_PORT: 5001
      DOCLING_SERVE_ENABLE_UI: "true"
      DOCLING_SERVE_API_KEY: "sk-docling-serve-api-key"
      DOCLING_SERVE_ARTIFACTS_PATH: /opt/app-root/src/.cache/docling/models
      DOCLING_SERVE_LOAD_MODELS_AT_BOOT: "false"
      DOCLING_SERVE_MAX_SYNC_WAIT: 36000
    ports:
      - 50001:5001
    volumes:
      - docling-data:/data
    ulimits:
      nofile:
        soft: 65535
        hard: 65535

volumes:
  docling-data:
```

Open WebUI 側の `DOCLING_PARAMS`（`MODEL_PROFILE=high` 向け全機能有効例）:

```yaml
DOCLING_PARAMS: >-
  {
    "do_ocr": true,
    "ocr_engine": "tesseract",
    "ocr_lang": ["jpn", "jpn_vert", "eng"],
    "do_table_structure": true,
    "table_mode": "accurate",
    "do_code_enrichment": true,
    "do_formula_enrichment": true,
    "do_picture_classification": true,
    "do_picture_description": true,
    "picture_description_preset": "granite_vision",
    "do_chart_extraction": true
  }
```

| パラメータ | 対応モデル |
| --------- | --------- |
| `ocr_engine`, `ocr_lang` | tesseract (`jpn` / `jpn_vert` / `eng`) |
| `do_table_structure`, `table_mode` | tableformer / tableformerv2 |
| `do_code_enrichment`, `do_formula_enrichment` | code_formula |
| `do_picture_classification` | picture_classifier |
| `do_picture_description`, `picture_description_preset` | granite_vision |
| `do_chart_extraction` | granite_chart_extraction_v4 |

Open WebUI 側の `DOCLING_PARAMS`（外部 OpenAI 互換 API / LiteLLM・vLLM 経由で VLM を使う場合）:

VLM を外部にオフロードするため、`MODEL_PROFILE=base` の軽量イメージでも利用できます。

```yaml
DOCLING_PARAMS: >-
  {
    "do_ocr": true,
    "ocr_engine": "tesseract",
    "ocr_lang": ["jpn", "jpn_vert", "eng"],
    "do_table_structure": true,
    "table_mode": "accurate",
    "do_code_enrichment": true,
    "do_formula_enrichment": true,
    "do_picture_classification": true,
    "do_picture_description": true,
    "picture_description_api": {
      "url": "http://litellm:4000/v1/chat/completions",
      "headers": {"Authorization": "Bearer YOUR_API_KEY"},
      "params": {
        "model": "gpt-4o",
        "max_completion_tokens": 200
      }
    }
  }
```

`picture_description_api` の各フィールド:

| フィールド | 説明 |
| --------- | ---- |
| `url` | `/v1/chat/completions` エンドポイント（vLLM は `:8000`、LM Studio は `:1234`、Ollama は `:11434`） |
| `headers` | 認証ヘッダー（LiteLLM の API キーなど） |
| `params.model` | API 側のモデル名（例: `gpt-4o`、`ibm-granite/granite-vision-3.3-2b`） |
| `params.max_completion_tokens` | 最大生成トークン数 |

---

## ビルド手動実行

1. GitHub リポジトリの **Actions** タブを開く
2. **Build and Push Image** ワークフローを選択
3. **Run workflow** をクリック
4. `base_tag` に上流タグ（例: `v1.17.0`）または `latest` を入力して実行

Docker CLI で直接ビルドする場合:

```bash
docker build \
  --build-arg BASE_TAG=v1.17.0 \
  --build-arg MODEL_PROFILE=high \
  -t docling-serve-jp .
```

---

## タグ命名規則

上流タグ `vX.Y.Z` に対して以下のタグが付与されます:

- `ghcr.io/<owner>/docling-serve-jp:vX.Y.Z`
- `ghcr.io/<owner>/docling-serve-jp:latest`

上流の `latest` タグでビルドした場合は `latest` のみ付与されます。

毎日 JST 11:00 に上流の新しいタグを自動検出し、未ビルドのタグがあれば自動でビルド・公開します。

---

## 必要なシークレット

| シークレット名    | 説明                                                                       |
| ----------------- | -------------------------------------------------------------------------- |
| `GITHUB_TOKEN`    | 自動提供（GHCR への push に使用）                                          |
| `DISPATCH_TOKEN`  | `repo` スコープを持つ PAT（上流監視ワークフローからのビルド起動に使用）    |

---

## References

- [docling-project/docling-serve](https://github.com/docling-project/docling-serve)
- [Quay.io Repository](https://quay.io/repository/docling-project/docling-serve)
- [tesseract-ocr/tessdata_best](https://github.com/tesseract-ocr/tessdata_best)

---

## License

MIT — 上流リポジトリのライセンスに準拠します。
