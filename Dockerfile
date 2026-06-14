# https://github.com/docling-project/docling-serve/blob/main/Containerfile
# https://quay.io/repository/docling-project/docling-serve
ARG BASE_TAG=latest
FROM quay.io/docling-project/docling-serve:${BASE_TAG}

ARG BASE_TAG=latest

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
    rm -rf "${DOCLING_SERVE_ARTIFACTS_PATH:?}"/* && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

#
# 対応する tableformer モデルを判定し、基本モデルリストを作成.
#
# 処理の流れ
#   0. DOCX/PPTX/PDF
#   1. layout                     : 文書構造解析モデル
#   2. tesseract/rapidocr/easyocr : OCRエンジン (aptでインストール済)
#   3. code_formula               : 数式・コード抽出モデル
#   4. tableformer                : 表解析モデル
#        - tableformerv2               : v1.20.0
#   5. picture_classifier         : 図・画像分類モデル
#   6. granite_vision             : 画像理解VLM (サイズが大きいため、同梱無し)
#   7. granite_chart_extraction_v4: グラフ数値抽出VLM (サイズが大きいため、同梱無し)
#        - granite_chart_extraction    : v1.13.0-
#        - granite_chart_extraction_v4 : v1.22.0-
#   8. granitedocling             : 文書解析VLM (サイズが大きいため、同梱無し)
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
    MODELS="layout code_formula ${TABLE_MODEL} picture_classifier"; \
    echo "$MODELS" > /tmp/docling-models-list && \
    echo "BASE_TAG=${BASE_TAG}" && \
    echo "TABLE_MODEL=${TABLE_MODEL}" && \
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
