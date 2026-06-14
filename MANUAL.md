# Manual

## 重いVLMモデルを外部マウントする

このイメージには BuildKit / containerd の容量不足を避けるため、以下の重いモデルを同梱していません。

- `granite_vision`
- `granitedocling`
- `granite_chart_extraction_v4` または `granite_chart_extraction`
- `smolvlm`
- `smoldocling`

Dockerfile でプリダウンロードするのは、軽量な基本モデルだけです。

- `layout`
- `code_formula`
- `tableformer` または `tableformerv2`
- `picture_classifier`

`DOCLING_SERVE_ARTIFACTS_PATH` 全体を bind mount すると、イメージ内の基本モデルもマウント元で隠れます。そのため、マウントするディレクトリには基本モデルと追加VLMモデルをまとめてダウンロードしてください。

### 1. モデル保存ディレクトリを作る

```bash
mkdir -p ./models
```

### 2. 基本モデルだけをダウンロードする

ローカルに Python / docling がない場合でも、ビルド済みイメージを使ってダウンロードできます。

```bash
docker run --rm \
  -u 0 \
  --entrypoint sh \
  -e HF_HUB_OFFLINE=0 \
  -e TRANSFORMERS_OFFLINE=0 \
  -v "$PWD/models:/models" \
  ghcr.io/k5-mot/docling-serve-jp:v1.23.0 \
  -lc '
    set -eu
    HELP="$(docling-tools models download --help 2>&1)"
    if echo "$HELP" | grep -q "tableformerv2"; then
      TABLE_MODEL="tableformerv2"
    else
      TABLE_MODEL="tableformer"
    fi
    docling-tools models download \
      -o /models \
      layout code_formula "$TABLE_MODEL" picture_classifier
    chown -R 1001:0 /models
    chmod -R g=u /models
  '
```

### 3. Granite 系VLMを追加する

`granite_chart_extraction_v4` は docling のバージョンによっては存在しないため、なければ `granite_chart_extraction` を使います。

```bash
docker run --rm \
  -u 0 \
  --entrypoint sh \
  -e HF_HUB_OFFLINE=0 \
  -e TRANSFORMERS_OFFLINE=0 \
  -v "$PWD/models:/models" \
  ghcr.io/k5-mot/docling-serve-jp:v1.23.0 \
  -lc '
    set -eu
    HELP="$(docling-tools models download --help 2>&1)"
    if echo "$HELP" | grep -q "granite_chart_extraction_v4"; then
      CHART_MODEL="granite_chart_extraction_v4"
    else
      CHART_MODEL="granite_chart_extraction"
    fi
    docling-tools models download \
      -o /models \
      granite_vision granitedocling "$CHART_MODEL"
    chown -R 1001:0 /models
    chmod -R g=u /models
  '
```

### 4. Smol 系VLMを追加する

```bash
docker run --rm \
  -u 0 \
  --entrypoint sh \
  -e HF_HUB_OFFLINE=0 \
  -e TRANSFORMERS_OFFLINE=0 \
  -v "$PWD/models:/models" \
  ghcr.io/k5-mot/docling-serve-jp:v1.23.0 \
  -lc '
    set -eu
    docling-tools models download \
      -o /models \
      smolvlm smoldocling
    chown -R 1001:0 /models
    chmod -R g=u /models
  '
```

### 5. docker-compose.yml でマウントする

```yaml
services:
  docling:
    image: ghcr.io/k5-mot/docling-serve-jp:v1.23.0
    environment:
      DOCLING_SERVE_ARTIFACTS_PATH: /opt/app-root/src/.cache/docling/models
      DOCLING_ARTIFACTS_PATH: /opt/app-root/src/.cache/docling/models
      HF_HUB_OFFLINE: "1"
      TRANSFORMERS_OFFLINE: "1"
    volumes:
      - ./models:/opt/app-root/src/.cache/docling/models
```

### 6. ローカルビルド時

重いVLMはイメージに含めないため、通常は追加の build arg は不要です。

```bash
docker build \
  --build-arg BASE_TAG=v1.23.0 \
  -t docling-serve-jp .
```

ビルド後は同じように `./models` をマウントして起動します。

```yaml
services:
  docling:
    image: docling-serve-jp
    environment:
      DOCLING_SERVE_ARTIFACTS_PATH: /opt/app-root/src/.cache/docling/models
      DOCLING_ARTIFACTS_PATH: /opt/app-root/src/.cache/docling/models
      HF_HUB_OFFLINE: "1"
      TRANSFORMERS_OFFLINE: "1"
    volumes:
      - ./models:/opt/app-root/src/.cache/docling/models
```

### 補足

- Granite 系と Smol 系を両方使わない場合は、必要な方だけ追加ダウンロードしてください。
- `./models` を削除すると、次回起動時にマウント先が空になり、基本モデルも見えなくなります。その場合は手順 2 から再実行してください。
- コンテナ内のモデル参照先は `/opt/app-root/src/.cache/docling/models` です。
