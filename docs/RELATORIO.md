# Relatório — Rota Livre · Deploy Blindado

Secure DevOps Tools & Cloud Computing · Global Solution 2026.2 · FIAP · 4ES

> Versão em texto do relatório. O **PDF da entrega, com todos os prints**, está em
> [`Entrega-DevOps-RotaLivre.pdf`](Entrega-DevOps-RotaLivre.pdf).

## 1. Integrantes

| Nome completo | RM |
|---|---|
| Gabriel Gomes Catanzaro | RM93445 |
| Lucas Gomes Alcantara | RM98766 |
| Henrique Canali Cuzato | RM551326 |

## 2. Links

- **URL pública do MVP:** http://34.193.105.165 (sessão de 18/11/2026 no AWS Academy Sandbox)
- **Repositório:** https://github.com/GabrielCatanzaro/tapa-buraco-devops
- **Repositório da IA (componente Inteligência):** https://github.com/GabrielCatanzaro/tapa-buraco-ia

## 3. Diagrama da arquitetura

[PRINT do diagrama Mermaid do README renderizado no GitHub, ou imagem exportada]

Fluxo: `git push` → GitHub Actions (build, Gitleaks, Semgrep, Trivy) → deploy SSH →
EC2 (Terraform) rodando docker compose com app (porta 80 pública), Prometheus (9090)
e Grafana (3000) restritos ao IP do time.

## 4. Container e IaC

- **Dockerfile**: python:3.12-slim, única camada de dependências, usuário não root
  (`appuser`), sem segredos na imagem, HEALTHCHECK. [PRINT do Dockerfile]
- **docker compose**: app + Prometheus + Grafana, senha do Grafana via ambiente.
  [PRINT de `docker compose ps` na EC2 com os 3 serviços saudáveis]
- **Terraform**: EC2 t3.small + EIP + Security Group na VPC padrão do Learner Lab.
  `terraform.tfvars` e state fora do repo. Porta 80 pública; 22/3000/9090 apenas
  `ip_admin` — com `validation` que **recusa 0.0.0.0/0**.
  [PRINT do `terraform apply` com os outputs]
  [PRINT do Security Group no console AWS mostrando as regras]

## 5. Pipeline DevSecOps

A cada push: **Gitleaks** (segredos) + **Semgrep** (SAST, barra achados de severidade alta)
+ **build e Trivy** (vulnerabilidades da imagem, barra CRITICAL/HIGH com correção disponível).
Deploy automático só na main, via SSH, com segredos em **GitHub Secrets**
(`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `EC2_SSH_KEY`,
`GRAFANA_SENHA`). Para não abrir a porta 22, o job libera o SSH apenas para o IP do
próprio runner (/32) durante o deploy e revoga a regra ao final.

**Bloqueio do GitHub Actions.** Na conta do repositório, o Actions não inicia nenhum job:
todos falham em 2 s com *"The job was not started because your account is locked due to a
billing issue"*, um bloqueio de cobrança do GitHub (conta Free, repositório público, uso zero).
Com autorização do professor, evidenciamos o erro e executamos as mesmas etapas do workflow
na EC2 com `scripts/pipeline-local.sh`, com as mesmas ferramentas e os mesmos critérios.

- [PRINT 05a: execução do Actions com as annotations de *billing issue*]
- [PRINT 05: execução **barrada**: Gitleaks encontra um segredo falso e o deploy não roda]
- [PRINT 06: execução **corrigida**: segredo removido, as 4 etapas passam e o deploy é feito]

## 6. Observabilidade

Dashboard Grafana provisionado com as **4 métricas de ouro**:

| Métrica | Consulta |
|---|---|
| Latência | `histogram_quantile(0.95, ...http_request_duration_seconds_bucket...)` (p95 e p50) |
| Tráfego | `sum(rate(http_requests_total[1m]))` |
| Erros | `% de respostas 5xx` |
| Saturação | memória residente e CPU do app |

- [PRINT do dashboard com tráfego real]
- **Alerta disparado**: regra `TaxaDeErroAlta` (>5% de 5xx por 1 min). Demonstração:
  acessos a `/erro-demo` → [PRINT do Prometheus em `/alerts` com estado FIRING]

## 7. Responsabilidade compartilhada

| Camada | Responsável |
|---|---|
| Segurança física dos datacenters, hardware, rede e hipervisor | AWS |
| Patches do SO da EC2, Docker, firewall (Security Group) | Equipe (nós) |
| Configuração segura do app, segredos, HTTPS/portas, dados | Equipe (nós) |
| Disponibilidade da infraestrutura global | AWS |

No modelo IaaS (EC2), a AWS responde **pela segurança DA nuvem** e a equipe
**pela segurança NA nuvem** — por isso o pipeline barra segredos/vulnerabilidades,
a imagem roda sem root e as portas admin são restritas por IP.

## 8. LGPD — onde ficam os dados pessoais

O MVP foi desenhado para **minimização**: não há cadastro, login, CPF nem telefone.
O relato guarda apenas endereço do problema, descrição, triagem e data — armazenados
no SQLite, em volume Docker na EC2 (us-east-1), acessível só via SSH restrito por IP.
A interface orienta o cidadão a não incluir dados pessoais na descrição. A IA roda
localmente (nenhum dado vai para APIs externas). Logs de acesso não guardam corpo
das requisições.

## 9. Estimativa de custo (us-east-1, 24/7)

| Item | Valor/mês (aprox.) |
|---|---|
| EC2 t3.small (US$ 0,0208/h) | US$ 15,20 |
| EBS gp3 16 GB | US$ 1,30 |
| IPv4 público/EIP (US$ 0,005/h) | US$ 3,60 |
| Tráfego de saída (baixo volume) | ~US$ 1,00 |
| **Total** | **~US$ 21/mês** |

No AWS Academy o custo sai dos créditos do Learner Lab e a instância pode ficar
parada fora dos horários de avaliação (custo cai para ~US$ 5/mês, só EBS + EIP).

## 10. Conclusão

O MVP foi colocado no ar em infraestrutura criada inteiramente por Terraform, em container sem
root e sem segredos, monitorado com as 4 métricas de ouro e um alerta real disparado. O pipeline
mostrou valor na prática: além do segredo vazado de propósito (barrado pelo Gitleaks), o Trivy
barrou duas vulnerabilidades HIGH reais da imagem base (zlib1g e setuptools embutido no pip),
corrigidas nos commits 56be6be e 8018035. Com o GitHub Actions bloqueado por cobrança da plataforma,
as mesmas etapas e critérios rodaram na EC2 com `scripts/pipeline-local.sh`, sem pular nenhuma
verificação antes do deploy.
