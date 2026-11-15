#!/usr/bin/env bash
# roda.sh — executa o modelo em hansl e devolve só os números.
#
#     ./hansl/roda.sh bem
#
# ## O que este script tira do caminho
#
# O `gretlcli` imprime, antes de qualquer coisa, um bloco de banner com versão,
# autores, licença e data da sessão — e, nesta máquina, mais um aviso de que o
# gretl foi compilado com OpenMP e linkado contra um OpenBLAS com pthreads.
#
# Nada disso é dado, e o projeto compara saída posicional. Então o filtro aqui
# **mantém apenas as linhas no formato `chave=valor`** em vez de tentar remover
# as linhas de banner uma por uma.
#
# A diferença importa: uma lista de exclusões quebra quando o gretl acrescenta
# uma linha nova de aviso. Uma lista de INCLUSÕES quebra só se o formato dos
# dados mudar — e o formato é definido por este projeto, não pelo gretl.
#
# ## E o que ele fornece
#
# O caminho absoluto do repositório e o caso, por variável de ambiente, porque
# o `gretlcli -b` não aceita argumento de script e tem diretório de trabalho
# próprio. Está explicado em `modelo.inp`.

set -uo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(dirname "$AQUI")"

if [ $# -ne 1 ] || { [ "$1" != "bem" ] && [ "$1" != "mal" ]; }; then
    echo "uso: roda.sh {bem|mal}" >&2
    exit 64
fi

if ! command -v gretlcli >/dev/null 2>&1; then
    echo "gretlcli ausente: sudo apt-get install gretl" >&2
    exit 69
fi

TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT

# `LC_ALL=C.UTF-8`, e nao `C`: o gretl usa Qt, que reclama de locale sem UTF-8
# com um aviso de quatro linhas em stderr. O `C.UTF-8` mantem o PONTO decimal
# -- que e o que a comparacao exige -- e cala o aviso.
if ! LC_ALL=C.UTF-8 \
     P05_BASE="$RAIZ" \
     P05_CASO="$1" \
     gretlcli -b "$AQUI/modelo.inp" </dev/null >"$TMP/saida.txt" 2>"$TMP/erro.txt"; then
    echo "o gretlcli falhou:" >&2
    tail -5 "$TMP/erro.txt" "$TMP/saida.txt" >&2
    exit 1
fi

# Só as linhas `chave=valor`. Ver o comentário acima sobre inclusão vs exclusão.
NUMEROS="$(grep -E '^(b[0-9]+|r2|sigma|gl)=' "$TMP/saida.txt" || true)"

# Falha ALTO se não veio número nenhum.
#
# Sem isto, um erro de hansl (que o gretl reporta em stdout junto com o banner)
# viraria saída vazia, e a suíte acusaria "divergência numérica" em vez de "o
# script não rodou".
if [ -z "$NUMEROS" ]; then
    echo "o hansl não produziu números para o caso $1." >&2
    echo "--- saída do gretlcli ---" >&2
    tail -12 "$TMP/saida.txt" >&2
    exit 1
fi

printf '%s\n' "$NUMEROS"
