"""Rota Livre — MVP (Secure DevOps & Cloud).

App do cidadão: registrar relatos de buracos/obstáculos, acompanhar a lista e
tirar dúvidas no chat. A triagem e o chat usam a IA local do repositório `llm`
quando IA_URL estiver configurada; sem ela, caem num modo de regras + busca
simples na mesma base de conhecimento (sem LLM), para o MVP público na nuvem
continuar funcionando. Expõe /metrics para o Prometheus (4 métricas de ouro).
"""

import json
import os
import re
import sqlite3
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

import requests
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field

AQUI = Path(__file__).resolve().parent
DB_PATH = os.environ.get("DB_PATH", str(AQUI / "dados" / "relatos.db"))
IA_URL = os.environ.get("IA_URL", "").rstrip("/")  # ex.: http://192.168.0.10:8000

app = FastAPI(title="Rota Livre", version="1.0")
Instrumentator().instrument(app).expose(app)  # /metrics para o Prometheus


# ----------------------------- banco (SQLite) -----------------------------

def conexao():
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def iniciar_banco():
    with conexao() as con:
        con.execute("""
            CREATE TABLE IF NOT EXISTS relatos (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                criado_em TEXT NOT NULL,
                tipo TEXT NOT NULL,
                gravidade TEXT NOT NULL,
                endereco TEXT NOT NULL,
                descricao TEXT NOT NULL,
                orgao_sugerido TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'registrado'
            )
        """)


iniciar_banco()


# ------------------------- triagem (IA ou regras) -------------------------

def _norm(s: str) -> str:
    s = (s or "").lower()
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def triagem_por_regras(texto: str) -> dict:
    """Plano B sem LLM: regras simples derivadas da base de conhecimento."""
    t = _norm(texto)
    if re.search(r"corredor|faixa (de )?onibus|exclusiva", t):
        tipo, orgao = "buraco_corredor_onibus", "SPTrans"
    elif re.search(r"calcada|passeio|guia", t):
        tipo, orgao = "calcada", "Responsável pelo imóvel"
    elif re.search(r"entulho|cacamba|objeto|galho|obstacul", t):
        tipo, orgao = "obstaculo", "Subprefeitura"
    elif re.search(r"luz|lampada|ilumina|poste", t):
        tipo, orgao = "iluminacao", "Subprefeitura"
    else:
        tipo, orgao = "buraco_via", "Subprefeitura"
    alta = re.search(r"acidente|cai|caiu|quase|perigo|fundo|enorme|moto|crianca|idoso", t)
    media = re.search(r"grande|carro|pneu|roda", t)
    gravidade = "alta" if alta else ("media" if media else "baixa")
    return {"tipo": tipo, "gravidade": gravidade, "orgao_sugerido": orgao, "origem": "regras"}


def triagem(texto: str) -> dict:
    if IA_URL:
        try:
            r = requests.post(f"{IA_URL}/triagem", json={"texto": texto}, timeout=60)
            r.raise_for_status()
            obj = r.json().get("triagem", {})
            return {
                "tipo": obj.get("tipo", "outro"),
                "gravidade": obj.get("gravidade", "media"),
                "orgao_sugerido": obj.get("orgao_sugerido", "Subprefeitura"),
                "origem": "ia_local",
            }
        except requests.RequestException:
            pass
    return triagem_por_regras(texto)


# ------------------------- chat (IA ou busca local) ------------------------

BASE = json.loads((AQUI / "base_conhecimento.json").read_text(encoding="utf-8"))["trechos"]


def resposta_por_busca(pergunta: str) -> dict:
    """Plano B sem LLM: devolve o trecho da base com maior sobreposição de
    palavras significativas (ignora palavras curtas/comuns); recusa fora do tema."""
    def tokens(s):
        # \w+ separa as palavras da pontuação ("calçada?" -> "calcada")
        return {p for p in re.findall(r"\w+", _norm(s)) if len(p) > 3}

    q = tokens(pergunta)
    melhor, melhor_pontos = None, 0.0
    for t in BASE:
        pontos = len(q & tokens(t["fonte"] + " " + t["texto"])) / (len(q) or 1)
        if pontos > melhor_pontos:
            melhor, melhor_pontos = t, pontos
    if melhor is None or melhor_pontos < 0.34:
        return {"resposta": "não consta", "fonte": None, "origem": "busca_local"}
    return {"resposta": melhor["texto"], "fonte": melhor["fonte"], "origem": "busca_local"}


# --------------------------------- rotas ----------------------------------

class NovoRelato(BaseModel):
    endereco: str = Field(min_length=3, max_length=200)
    descricao: str = Field(min_length=5, max_length=1000)


class PerguntaChat(BaseModel):
    pergunta: str = Field(min_length=3, max_length=500)


@app.get("/health")
def health():
    return {"app": "ok", "ia_local_configurada": bool(IA_URL)}


@app.post("/relatos")
def criar_relato(r: NovoRelato):
    t = triagem(r.descricao)
    with conexao() as con:
        cur = con.execute(
            "INSERT INTO relatos (criado_em, tipo, gravidade, endereco, descricao, orgao_sugerido) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (datetime.now(timezone.utc).isoformat(timespec="seconds"), t["tipo"],
             t["gravidade"], r.endereco.strip(), r.descricao.strip(), t["orgao_sugerido"]),
        )
        novo_id = cur.lastrowid
    return {"id": novo_id, "triagem": t}


@app.get("/relatos")
def listar_relatos():
    with conexao() as con:
        linhas = con.execute(
            "SELECT * FROM relatos ORDER BY id DESC LIMIT 100").fetchall()
    return {"relatos": [dict(l) for l in linhas]}


@app.post("/chat")
def chat(p: PerguntaChat):
    if IA_URL:
        try:
            r = requests.post(f"{IA_URL}/perguntar",
                              json={"pergunta": p.pergunta, "modo": "agente"}, timeout=120)
            r.raise_for_status()
            dados = r.json()
            obj = dados.get("resposta") or {}
            return {"resposta": obj.get("resposta", "não consta"),
                    "fonte": dados.get("fonte"), "origem": "ia_local"}
        except requests.RequestException:
            pass
    return resposta_por_busca(p.pergunta)


@app.get("/erro-demo")
def erro_demo():
    """Gera um erro 500 de propósito, para demonstrar o alerta de taxa de erro."""
    raise RuntimeError("erro proposital para o alerta do Prometheus")


@app.get("/", response_class=HTMLResponse)
def pagina():
    return (AQUI / "index.html").read_text(encoding="utf-8")
