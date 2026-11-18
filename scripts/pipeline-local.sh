#!/usr/bin/env bash
# Executa na EC2 as MESMAS etapas do workflow .github/workflows/devsecops.yml,
# com as mesmas ferramentas e os mesmos critérios de bloqueio:
#   1. Gitleaks  -> barra qualquer segredo encontrado
#   2. Semgrep   -> barra achados de severidade ERROR
#   3. Build + Trivy -> barra CVEs CRITICAL/HIGH com correção disponível
#   4. Deploy    -> docker compose up, só se 1, 2 e 3 passarem
#
# Motivo: o GitHub Actions da conta está bloqueado por um problema de cobrança
# do GitHub ("account is locked due to a billing issue"), alheio ao projeto.
# Uso (dentro do repositório clonado na EC2):  bash scripts/pipeline-local.sh
set -uo pipefail

VERMELHO='\033[1;31m'; VERDE='\033[1;32m'; AZUL='\033[1;34m'; FIM='\033[0m'
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

etapa()  { echo -e "\n${AZUL}==> $1${FIM}"; }
barrou() { echo -e "\n${VERMELHO}PIPELINE BARRADO na etapa: $1. Deploy NAO executado.${FIM}"; exit 1; }
passou() { echo -e "${VERDE}OK: $1${FIM}"; }

echo "Pipeline DevSecOps local - commit $(git rev-parse --short HEAD 2>/dev/null || echo '?') - $(date '+%d/%m/%Y %H:%M:%S')"

etapa "1/4 Gitleaks - segredos vazados"
sudo docker run --rm -v "$REPO":/repo zricethezav/gitleaks:latest \
  dir /repo --verbose --redact || barrou "Gitleaks"
passou "nenhum segredo encontrado"

etapa "2/4 Semgrep - analise estatica (barra severidade ERROR)"
sudo docker run --rm -v "$REPO":/src semgrep/semgrep \
  semgrep scan --config auto --severity ERROR --error /src || barrou "Semgrep"
passou "nenhum achado de severidade alta"

etapa "3/4 Build + Trivy - vulnerabilidades da imagem (barra CRITICAL/HIGH com correcao)"
sudo docker build -t tapa-buraco:pipeline . || barrou "Build"
sudo docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest \
  image --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 tapa-buraco:pipeline || barrou "Trivy"
passou "nenhuma vulnerabilidade CRITICAL/HIGH corrigivel"

etapa "4/4 Deploy - docker compose up"
# a senha do Grafana fica FORA da pasta do repositorio (nunca e escaneada nem versionada)
ENV_FILE="$HOME/tapa-buraco.env"
[ -f "$ENV_FILE" ] || barrou "Deploy ($ENV_FILE com GRAFANA_SENHA ausente)"
sudo docker compose --env-file "$ENV_FILE" up -d --build || barrou "Deploy"
sudo docker compose --env-file "$ENV_FILE" ps
echo -e "\n${VERDE}PIPELINE APROVADO: todas as etapas passaram e o deploy foi feito.${FIM}"
