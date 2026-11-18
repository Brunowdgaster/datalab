#!/usr/bin/env bash
# roda.sh — acha o Julia e executa `modelo.jl`.
#
#     ./julia/roda.sh bem           # QR, via o operador \
#     ./julia/roda.sh bem normal    # equações normais
#
# ## Por que um runner, e não `julia` direto no compara.py
#
# Porque o Julia **não está no PATH** desta máquina: ele foi instalado por
# tarball em `~/ferramentas/julia`, e não pelo apt.
#
# A tentação seria pôr esse caminho no `compara.py`. **Já fiz isso neste
# portfólio e custou um CI:** o `verifica.sh` do Assembly listava
# `build-goto/fvm build/fvm c/build/fvm` — os diretórios que existiam na minha
# máquina — e o CI falhou porque o `build.sh` produz `build-linux-goto/`. A
# lista estava certa sobre a máquina de quem a escreveu e errada sobre o
# projeto.
#
# Então a busca é por ORDEM DE PREFERÊNCIA e por EXISTÊNCIA, com o PATH
# primeiro: num runner do GitHub, a action oficial põe o `julia` no PATH, e é
# ele que deve ganhar.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$AQUI")"

achar_julia() {
    # 1. o PATH, que é onde um CI bem configurado o põe
    if command -v julia >/dev/null 2>&1; then
        command -v julia
        return 0
    fi
    # 2. a variável explícita, para quem tem em lugar incomum
    if [ -n "${JULIA:-}" ] && [ -x "$JULIA" ]; then
        printf '%s\n' "$JULIA"
        return 0
    fi
    # 3. os lugares onde um tarball costuma cair
    local cand
    for cand in "$HOME/ferramentas/julia/bin/julia" \
                "$HOME/.juliaup/bin/julia" \
                "$HOME/julia/bin/julia" \
                /opt/julia/bin/julia \
                /usr/local/julia/bin/julia; do
        [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
    done
    return 1
}

JL="$(achar_julia)" || {
    echo 'julia não encontrado (PATH, $JULIA, ~/ferramentas/julia, /opt/julia)' >&2
    exit 127
}

# `--startup-file=no` porque um `~/.julia/config/startup.jl` do usuário pode
# carregar pacotes, mudar o número de threads de BLAS ou imprimir em stdout --
# e qualquer um dos três mudaria o que esta medição mede. Numa suíte que
# compara aritmética, o ambiente do usuário é uma variável a eliminar.
#
# `--project=@.` NÃO é usado de propósito: este arquivo só depende da
# biblioteca padrão (`LinearAlgebra`, `Printf`, `DelimitedFiles`), e declarar
# um projeto faria o Julia procurar um `Project.toml` que não existe.
exec "$JL" --startup-file=no --color=no "$AQUI/modelo.jl" "$@"
