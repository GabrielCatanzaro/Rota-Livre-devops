# Dockerfile enxuto: imagem slim, uma camada de dependências, usuário não root,
# sem segredos na imagem (configuração vem por variáveis de ambiente).
FROM python:3.12-slim

WORKDIR /app

# atualizações de segurança do Debian da imagem base (ex.: zlib1g, CVE-2026-85091)
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY app/requirements.txt .
# pip e setuptools atualizados (setuptools < 78.1.1 tem a CVE-2025-47273)
RUN pip install --no-cache-dir --upgrade pip "setuptools>=78.1.1" \
    && pip install --no-cache-dir -r requirements.txt

COPY app/ .

# usuário não root + diretório de dados gravável (SQLite)
RUN useradd --create-home appuser \
    && mkdir -p /data \
    && chown -R appuser:appuser /data /app
USER appuser
ENV DB_PATH=/data/relatos.db

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
