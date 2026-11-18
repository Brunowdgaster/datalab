#!/usr/bin/env bash
# roda.sh — acha o Mojo e executa `modelo.mojo`.
#
#     ./mojo/roda.sh bem           # QR de Householder, à mão
#     ./mojo/roda.sh bem normal    # equações normais + Gauss
#
# ## Por que o binário direto NÃO funciona sozinho
#
# Esta é a parte que custou uma iteração, e está escrita porque a mensagem de
# erro não ajuda:
#
#     error: unable to locate module 'std'
#     error: use of unknown declaration 'len'
#
# `len` desconhecido num arquivo Mojo parece erro de sintaxe, ou versão errada
# da linguagem. **Não é:** é a biblioteca padrão inteira ausente, e `len` mora
# nela. O compilador reporta cada símbolo que falta em vez de dizer "não achei
# a stdlib".
#
# A causa é que o Mojo localiza a stdlib por `MODULAR_HOME`, e quem a define é
# o ambiente do `pixi`. Chamar `.pixi/envs/default/bin/mojo` direto deixa a
# variável vazia:
#
#     MODULAR_HOME=<env>/share/max
#
# Então este runner define a variável, e aí o binário direto funciona — o que
# evita pagar o custo do `pixi run` (que resolve o ambiente a cada chamada) em
# cada uma das quatro invocações do `compara.py`.
#
# ## E uma coisa que foi medida e dispensou uma preocupação
#
# `pixi run` **não** troca o diretório corrente — ele roda onde foi chamado, e
# não no diretório do `pixi.toml`:
#
#     $ cd .../p05-datalab && pixi run --manifest-path ~/ferramentas/mojo/pixi.toml pwd
#     /mnt/c/.../p05-datalab
#
# Isso importa porque o `modelo.mojo` abre `dados/<caso>.csv` relativo ao
# diretório corrente. Se o pixi mudasse de diretório, o arquivo não seria
# encontrado — e o erro falaria de arquivo, não de diretório.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$AQUI")"

# A busca é por existência e com o PATH primeiro, pela mesma razão dos runners
# de Julia e Scala: um caminho fixo descreveria esta máquina em vez do projeto,
# e foi assim que o CI do Assembly quebrou numa sessão anterior.
achar_mojo() {
    if command -v mojo >/dev/null 2>&1; then
        command -v mojo
        return 0
    fi
    if [ -n "${MOJO:-}" ] && [ -x "$MOJO" ]; then
        printf '%s\n' "$MOJO"
        return 0
    fi
    local cand
    for cand in "$HOME/ferramentas/mojo/.pixi/envs/default/bin/mojo" \
                "$HOME/.modular/bin/mojo" \
                /opt/mojo/bin/mojo; do
        [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
    done
    # Último recurso: um ambiente pixi em qualquer lugar sob ~/ferramentas.
    cand="$(find "$HOME/ferramentas" -maxdepth 6 -type f -name mojo \
            -path '*/bin/mojo' 2>/dev/null | head -1)"
    [ -n "$cand" ] && [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
    return 1
}

MJ="$(achar_mojo)" || {
    echo 'mojo não encontrado (PATH, $MOJO, ~/ferramentas/mojo)' >&2
    exit 127
}

# `MODULAR_HOME` derivado DO BINÁRIO, e não escrito à mão: o binário está em
# `<prefixo>/bin/mojo`, e a stdlib em `<prefixo>/share/max`. Assim o runner
# funciona para qualquer prefixo — pixi, conda, instalação manual — sem saber
# qual é.
#
# Se o `mojo` vier do PATH já com o ambiente configurado (um runner de CI, por
# exemplo), a variável que já existe é preservada.
if [ -z "${MODULAR_HOME:-}" ]; then
    prefixo="$(cd "$(dirname "$MJ")/.." && pwd)"
    if [ -d "$prefixo/share/max" ]; then
        export MODULAR_HOME="$prefixo/share/max"
    fi
fi

# `cd` para a raiz: o `modelo.mojo` abre `dados/<caso>.csv` relativo ao
# diretório corrente, e o runner garante o contrato em vez de confiar em quem
# chama.
cd "$RAIZ" || exit 1

exec "$MJ" run "$AQUI/modelo.mojo" "$@"
