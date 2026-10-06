#!/usr/bin/env python3
"""Troca os placeholders <NOME> de um JSON de workflow pelos valores do .env.local (stdout).

Uso: python3 scripts/preparar_json.py workflows/<pasta>/<arquivo>.json [.env.local] > /tmp/importar.json
Não grava nada no repositório; mande a saída para fora dele (ex.: /tmp) e importe no n8n.
"""
import json, re, sys

CHAVES = ["PHONE_NUMBER_ID", "RESPONSAVEL_PHONE", "EMAIL_REMETENTE", "EMAIL_RESPONSAVEL",
          "ID_DO_WORKFLOW_NOTIFICACAO_DE_ERROS"]

def ler_env(caminho):
    valores = {}
    for linha in open(caminho, encoding="utf-8"):
        linha = linha.strip()
        if linha and not linha.startswith("#") and "=" in linha:
            k, v = linha.split("=", 1)
            valores[k.strip()] = v.strip().strip('"').strip("'")
    return valores

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    arquivo = sys.argv[1]
    env = ler_env(sys.argv[2] if len(sys.argv) > 2 else ".env.local")
    texto = open(arquivo, encoding="utf-8").read()
    usados = [k for k in CHAVES if f"<{k}>" in texto]
    faltando = [k for k in usados if not env.get(k)]
    if faltando:
        sys.exit("Faltam valores no .env.local para: " + ", ".join(faltando))
    for k in usados:
        # json.dumps cuida de aspas/barras; [1:-1] tira as aspas externas
        texto = texto.replace(f"<{k}>", json.dumps(env[k], ensure_ascii=False)[1:-1])
    json.loads(texto)  # garante que o resultado continua sendo JSON válido
    restantes = sorted(set(re.findall(r"<[A-Z_]{4,}>", texto)))
    if restantes:
        print("Aviso: placeholders sem valor definido: " + ", ".join(restantes), file=sys.stderr)
    sys.stdout.write(texto)

main()
