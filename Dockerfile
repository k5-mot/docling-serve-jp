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
#   URL: https://docling-project.github.io/docling/usage/model_catalog/
#
# 処理の流れ; Standard Pipeline
#   0. DOCX/PPTX/PDF
#   1. 文書構造解析モデル / Object Detection Models (Layout)
#     - layout
#   2. 表構造解析モデル / TableFormer Models
#     - tableformer
#     - tableformerv2              : v1.20.0-
#   3. 画像・図分類モデル / Image & Picture Classifier
#     - picture_classifier
#   4. OCRエンジン / OCR Engines
#     - tesseract (aptでインストール済)
#     - rapidocr
#     - easyocr
#   5. 読上順序決定アルゴリズム / Reading Order
#     - docling内部ロジック
#   6. 視覚言語モデル / Vision-Language Model
#     6.1. [OPTIONAL] 画像説明VLM / Picture Description (サイズが大きいため、同梱無し)
#       - smolvlm
#       - granite_vision
#     6.2. [OPTIONAL] コード・数式VLM / Code & Formula (サイズが大きいため、同梱無し)
#       - code_formula
#     6.3. [OPTIONAL] グラフ数値抽出VLM / Chart Extraction (サイズが大きいため、同梱無し)
#       - granite_chart_extraction    : v1.13.0-
#       - granite_chart_extraction_v4 : v1.22.0-
#   X. Markdown/DocTags
#
# 処理の流れ; VLM Pipeline
#   0. DOCX/PPTX/PDF
#   1. フルページ変換VLM / Full-Page Convert VLM (サイズが大きいため、同梱無し)
#      - VLMが以下を統合的に推定する:
#        - 文書構造
#        - 表構造
#        - 画像・図領域の認識
#        - 読上順序
#        - テキスト認識 (OCR相当)
#     - smoldocling
#     - granitedocling
#   X. Markdown/DocTags
#
# 処理の流れ; Hybrid Pipeline
#   0. DOCX/PPTX/PDF
#   1. フルページ変換VLM / Full-Page Convert VLM
#      - VLMが以下を推定する:
#        - 文書構造
#        - 表構造
#        - 画像・図領域の認識
#        - 読上順序
#        - テキスト領域 (bbox)
#   2. OCRエンジン / OCR Engines
#      - OCR/PDF backend が、VLMが推定した領域内の文字列を取得し、VLM生成テキストを置換する.
#   X. Markdown/DocTags
#
# Commands:
#   docling-tools models download -o ./docling-models tableformerv2 granite_vision code_formula granite_chart_extraction_v4
#   docling-tools models download -o ./docling-models granitedocling
#
USER 1001
ENV HF_HUB_DOWNLOAD_TIMEOUT=90
ENV HF_HUB_ETAG_TIMEOUT=90

#
# モデルを事前ダウンロード.
#
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" layout
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" tableformer
RUN docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" picture_classifier

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
