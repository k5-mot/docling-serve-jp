# https://github.com/docling-project/docling-serve/blob/main/Containerfile
# https://quay.io/repository/docling-project/docling-serve
ARG BASE_TAG=latest
FROM quay.io/docling-project/docling-serve:${BASE_TAG}

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
#
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
# docling-serve が参照するモデル格納先を明示.
# - https://huggingface.co/docling-project
#
ENV DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models
ENV HF_HOME=/opt/app-root/src/.cache/huggingface
ENV TRANSFORMERS_CACHE=/opt/app-root/src/.cache/huggingface
RUN mkdir -p "${DOCLING_SERVE_ARTIFACTS_PATH}" "${HF_HOME}" && \
    chown -R 1001:0 /opt/app-root/src/.cache && \
    chmod -R g=u /opt/app-root/src/.cache

#
# docling-serve が使う各種モデルを事前ダウンロード.
#
#   0. DOCX/PPTX/PDF
#   1. layout                     : 文書構造解析モデル
#   2. tesseract                  : OCRエンジン
#   3. code_formula               : 数式・コード抽出モデル
#   4. tableformerv2              : 表解析モデル
#   5. picture_classifier         : 図・画像分類モデル
#   6. granite_vision             : 画像理解VLM
#   7. granite_chart_extraction_v4: グラフ数値抽出VLM
#   8. granitedocling             : 文書解析VLM
#   X. Markdown/DocTags
#
USER 1001
ENV DOCLING_SERVE_LOAD_MODELS_AT_BOOT=false

# 高性能版カスタム.
ARG MODELS_LIST="layout code_formula tableformerv2 picture_classifier granite_vision granite_chart_extraction_v4 granitedocling"
# 軽量版カスタム.
# ARG MODELS_LIST="layout code_formula tableformerv2 picture_classifier smolvlm smoldocling"

RUN echo "Downloading models..." && \
    HF_HUB_DOWNLOAD_TIMEOUT="90" \
    HF_HUB_ETAG_TIMEOUT="90" \
    docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}" ${MODELS_LIST} && \
    chown -R 1001:0 ${DOCLING_SERVE_ARTIFACTS_PATH} && \
    chmod -R g=u ${DOCLING_SERVE_ARTIFACTS_PATH} && \
    test -d "${DOCLING_SERVE_ARTIFACTS_PATH}/docling-project--docling-layout-heron"

#
# HuggingFace Hub のオフラインモードを有効化.
#
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

#
# WORKDIR/EXPOSE/CMDはベースイメージを継承.
# - https://github.com/docling-project/docling-serve/blob/main/Containerfile
#
