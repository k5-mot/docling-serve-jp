# https://github.com/docling-project/docling-serve/blob/main/Containerfile
# https://quay.io/repository/docling-project/docling-serve
ARG BASE_TAG=latest
FROM quay.io/docling-project/docling-serve:${BASE_TAG}

USER root

# VLM; Vision Language Model をダウンロード.
# RUN docling-tools models download smolvlm

# 日本語 Tesseract 言語パックを追加.
RUN dnf install -y --best --nodocs --setopt=install_weak_deps=False \
    tesseract-langpack-jpn google-noto-sans-cjk-jp-fonts google-noto-serif-cjk-ttc-fonts \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && fc-cache -f -v

# tessdata_best (高精度モデル) で jpn / jpn_vert / eng を上書き。
RUN TESSDATA_DIR=$(find /usr /opt -name "tessdata" -type d 2>/dev/null | head -1) && \
    echo "tessdata dir: ${TESSDATA_DIR}" && \
    curl -fsSL -o "${TESSDATA_DIR}/jpn.traineddata" \
    https://github.com/tesseract-ocr/tessdata_best/raw/main/jpn.traineddata && \
    curl -fsSL -o "${TESSDATA_DIR}/jpn_vert.traineddata" \
    https://github.com/tesseract-ocr/tessdata_best/raw/main/jpn_vert.traineddata && \
    curl -fsSL -o "${TESSDATA_DIR}/eng.traineddata" \
    https://github.com/tesseract-ocr/tessdata_best/raw/main/eng.traineddata
ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata/
RUN tesseract --list-langs 2>&1 | grep -E "jpn|eng" || echo "WARNING: language check failed"

# RapidOCR の ONNX モデルをビルド時にダウンロード.
RUN python3 -c "from rapidocr import RapidOCR; RapidOCR()"

# HuggingFace Hub のオフラインモードを有効化.
USER 1001
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

# WORKDIR /opt/app-root/src
# EXPOSE 5001
# CMD ["docling-serve", "run"]
