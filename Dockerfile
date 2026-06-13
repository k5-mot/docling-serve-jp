# https://github.com/docling-project/docling-serve/blob/main/Containerfile
# https://quay.io/repository/docling-project/docling-serve
ARG BASE_TAG=latest
FROM quay.io/docling-project/docling-serve:${BASE_TAG}

ARG BASE_TAG=latest
ARG MODEL_PROFILE=high

ENV DOCLING_SERVE_LOAD_MODELS_AT_BOOT=false

USER root

#
# Tesseract 日本語言語パックを追加.
#
RUN dnf install -y --best --nodocs --setopt=install_weak_deps=False \
    tesseract-langpack-jpn \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && fc-cache -f -v

#
# tessdata_best (高精度モデル) で jpn / jpn_vert / eng を上書き。
# - Most Accurate model: https://github.com/tesseract-ocr/tessdata_best
# - Well-Balanced model: https://github.com/tesseract-ocr/tessdata
# - Fastest small model: https://github.com/tesseract-ocr/tessdata_fast
#
ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/

RUN test -d "${TESSDATA_PREFIX%/}" && \
    echo "tessdata dir: ${TESSDATA_PREFIX%/}" && \
    curl -fsSL -o "${TESSDATA_PREFIX%/}/jpn.traineddata" \
    https://github.com/tesseract-ocr/tessdata_best/raw/main/jpn.traineddata && \
    curl -fsSL -o "${TESSDATA_PREFIX%/}/jpn_vert.traineddata" \
    https://github.com/tesseract-ocr/tessdata_best/raw/main/jpn_vert.traineddata && \
    curl -fsSL -o "${TESSDATA_PREFIX%/}/eng.traineddata" \
    https://github.com/tesseract-ocr/tessdata_best/raw/main/eng.traineddata
RUN tesseract --list-langs 2>&1 | grep -E "jpn|jpn_vert|eng" || echo "WARNING: language check failed"

#
# docling / docling-serve が参照するモデル格納先を明示.
# - モデル一覧: https://huggingface.co/docling-project
#
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models
ENV DOCLING_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models
ENV HF_HOME=/opt/app-root/src/.cache/huggingface
ENV TRANSFORMERS_CACHE=/opt/app-root/src/.cache/huggingface
RUN mkdir -p "${DOCLING_SERVE_ARTIFACTS_PATH}" "${HF_HOME}" && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

#
# 対応モデルを判定し、MODEL_PROFILE に応じたモデルリストを作成.
#
# MODEL_PROFILE:
#   high  : Granite系VLM + chart対応
#   medium: Smol系VLM
#   low   : VLMなしの基本構成
#
# 処理の流れ
#   0. DOCX/PPTX/PDF
#   1. layout                     : 文書構造解析モデル
#   2. tesseract/rapidocr/easyocr : OCRエンジン (aptでインストール済)
#   3. code_formula               : 数式・コード抽出モデル
#   4. tableformer                : 表解析モデル
#        - tableformerv2               : v1.20.0
#   5. picture_classifier         : 図・画像分類モデル
#   6. granite_vision             : 画像理解VLM
#   7. granite_chart_extraction_v4: グラフ数値抽出VLM
#        - granite_chart_extraction    : v1.13.0-
#        - granite_chart_extraction_v4 : v1.22.0-
#   8. granitedocling             : 文書解析VLM
#   X. Markdown/DocTags
#
USER 1001
RUN set -eu; \
    HELP="$(docling-tools models download --help 2>&1)"; \
    \
    if echo "$HELP" | grep -q "tableformerv2"; then \
    TABLE_MODEL="tableformerv2"; \
    else \
    TABLE_MODEL="tableformer"; \
    fi; \
    \
    if echo "$HELP" | grep -q "granite_chart_extraction_v4"; then \
    CHART_MODEL="granite_chart_extraction_v4"; \
    elif echo "$HELP" | grep -q "granite_chart_extraction"; then \
    CHART_MODEL="granite_chart_extraction"; \
    else \
    CHART_MODEL=""; \
    fi; \
    \
    case "$MODEL_PROFILE" in \
    high) \
    MODELS="layout code_formula ${TABLE_MODEL} picture_classifier granite_vision granitedocling"; \
    if [ -n "$CHART_MODEL" ]; then MODELS="$MODELS $CHART_MODEL"; fi; \
    ;; \
    medium) \
    MODELS="layout code_formula ${TABLE_MODEL} picture_classifier smolvlm smoldocling"; \
    ;; \
    low) \
    MODELS="layout code_formula ${TABLE_MODEL} picture_classifier"; \
    ;; \
    *) \
    echo "Unknown MODEL_PROFILE=$MODEL_PROFILE"; \
    exit 1; \
    ;; \
    esac; \
    \
    echo "$MODELS" > /tmp/docling-models-list && \
    echo "BASE_TAG=${BASE_TAG}" && \
    echo "MODEL_PROFILE=${MODEL_PROFILE}" && \
    echo "TABLE_MODEL=${TABLE_MODEL}" && \
    echo "CHART_MODEL=${CHART_MODEL:-none}" && \
    echo "MODELS=${MODELS}"

#
# モデルを事前ダウンロード.
#
RUN set -eu; \
    MODELS="$(cat /tmp/docling-models-list)"; \
    echo "Downloading models: ${MODELS}"; \
    HF_HUB_DOWNLOAD_TIMEOUT=90 \
    HF_HUB_ETAG_TIMEOUT=90 \
    docling-tools models download \
    -o "${DOCLING_SERVE_ARTIFACTS_PATH}" \
    ${MODELS}

#
# モデルキャッシュの権限調整.
#
USER root
RUN chown -R 1001:0 "${DOCLING_SERVE_ARTIFACTS_PATH}" "${HF_HOME}" && \
    chmod -R g=u "${DOCLING_SERVE_ARTIFACTS_PATH}" "${HF_HOME}"

#
# HuggingFace Hub のオフラインモードを有効化.
#
USER 1001
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

#
# WORKDIR/EXPOSE/CMDはベースイメージを継承.
# - https://github.com/docling-project/docling-serve/blob/main/Containerfile
#
