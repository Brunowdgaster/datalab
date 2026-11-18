#!/usr/bin/env bash
# roda.sh — acha o scala-cli e executa `modelo.scala`.
#
#     ./scala/roda.sh bem           # QR de Householder, à mão
#     ./scala/roda.sh bem normal    # equações normais + Gauss
#
# ## Por que um runner
#
# Dois motivos, e o segundo é o que importa.
#
# **1. Onde está o binário.** O `scala-cli` não vem do apt: foi instalado por
# tarball em `/usr/local/bin` (para o gerador de carga do `p03-otp-mesh`, em
# 2026-11-14 — está registrado no `AMBIENTE.md` do portfólio). Num runner do
# GitHub ele vem de outro lugar. A busca é por existência, e o PATH ganha.
#
# **2. O cache, e por que ele não falseia a medição.** O `scala-cli` compila
# na primeira execução e guarda o resultado em `~/.cache/scala-cli`. As
# execuções seguintes reusam, e isso é correto para este projeto — a medição é
# de **aritmética**, não de tempo de compilação. Nenhum número da tabela do
# `compara.py` é um tempo.
#
# Se algum dia o projeto medir tempo, o cache passa a ser uma variável a
# controlar, e este comentário é o aviso de que ele existe.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$AQUI")"

achar_scala_cli() {
    if command -v scala-cli >/dev/null 2>&1; then
        command -v scala-cli
        return 0
    fi
    if [ -n "${SCALA_CLI:-}" ] && [ -x "$SCALA_CLI" ]; then
        printf '%s\n' "$SCALA_CLI"
        return 0
    fi
    local cand
    for cand in /usr/local/bin/scala-cli \
                "$HOME/.local/share/coursier/bin/scala-cli" \
                "$HOME/ferramentas/bin/scala-cli" \
                /opt/scala-cli/scala-cli; do
        [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
    done
    return 1
}

SC="$(achar_scala_cli)" || {
    echo 'scala-cli não encontrado (PATH, $SCALA_CLI, /usr/local/bin)' >&2
    exit 127
}

# `cd` para a raiz do projeto: o `modelo.scala` resolve `dados/<caso>.csv`
# relativo ao diretório corrente, e não ao do arquivo-fonte.
#
# Isso é deliberado e vale explicar, porque é o oposto do que o `julia/roda.sh`
# faz (lá o caminho sai de `@__FILE__`). O motivo é a JVM: um .scala compilado
# para a JVM não tem nada equivalente a `__FILE__` em tempo de execução --
# a classe pode vir de um JAR, de um diretório de classes ou do cache do
# scala-cli, e nenhum dos três diz onde o fonte estava.
#
# Então o contrato aqui é "rode da raiz", e o runner o garante em vez de
# confiar em quem chama.
cd "$RAIZ" || exit 1

# `--quiet` suprime o "Compiling..." que o scala-cli manda para stderr. Sem
# isso, o `compara.py` -- que captura stderr para mostrar em caso de falha --
# exibiria ruído de compilação como se fosse diagnóstico de erro.
#
# `--power` NÃO é usado: nada aqui precisa de recurso experimental, e um
# arquivo que exige `--power` é um arquivo que a próxima versão pode recusar.
exec "$SC" run --quiet "$AQUI/modelo.scala" -- "$@"
