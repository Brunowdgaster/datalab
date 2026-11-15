#!/usr/bin/env bash
# roda.sh — carrega o CSV no SQLite e roda o modelo em SQL.
#
#     ./sql/roda.sh bem
#
# A carga usa `.import` do SQLite, que é comando de FERRAMENTA e não de
# linguagem — e por isso está aqui, no runner, e não em `modelo.sql`. Aquele
# arquivo é SQL ANSI e roda também no PostgreSQL; este script é o encanamento
# específico do SQLite.
set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(dirname "$AQUI")"

if [ $# -ne 1 ] || { [ "$1" != "bem" ] && [ "$1" != "mal" ]; }; then
    echo "uso: roda.sh {bem|mal}" >&2
    exit 64
fi

command -v sqlite3 >/dev/null 2>&1 || {
    echo "sqlite3 ausente: sudo apt-get install sqlite3" >&2; exit 69; }

TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT

# `REAL` e não `NUMERIC`: o SQLite tipa por valor, e `NUMERIC` tentaria
# converter para inteiro quando o valor couber -- `1.0` viraria `1`. Isso não
# mudaria a aritmética, mas mudaria a formatação, e a comparação é textual.
{
    echo 'CREATE TABLE obs (x1 REAL, x2 REAL, y REAL);'
    echo '.mode csv'
    echo ".import --skip 1 '$RAIZ/dados/$1.csv' obs"
} > "$TMP/carrega.sql"

saida=$(sqlite3 "$TMP/db.sqlite" < "$TMP/carrega.sql" 2>&1) || {
    echo "a carga falhou: $saida" >&2; exit 1; }

n=$(sqlite3 "$TMP/db.sqlite" 'SELECT COUNT(*) FROM obs;' 2>/dev/null)
# Falha ALTO se a carga não trouxe linhas. Sem isto, as somas dariam NULL e a
# saída viria vazia -- e a suíte acusaria divergência em vez de carga vazia.
if [ "${n:-0}" -lt 2 ]; then
    echo "a carga trouxe $n linha(s) de $RAIZ/dados/$1.csv" >&2
    exit 1
fi

sqlite3 -noheader "$TMP/db.sqlite" < "$AQUI/modelo.sql"
