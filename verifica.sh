#!/usr/bin/env bash
# verifica.sh — a suíte do p05-datalab.
#
# A tese é que **a diferença entre algoritmos é maior que a diferença entre
# linguagens**, e esta suíte é o que torna isso verificável.
#
# Ela faz duas coisas que as outras suítes do portfólio não fazem:
#
#   1. compara **com tolerância**, porque ponto flutuante não é associativo e
#      exigir igualdade byte a byte reprovaria implementações corretas. As
#      tolerâncias vêm do número de condição MEDIDO -- ver TOLERANCIA.md;
#
#   2. **exige que algumas implementações divirjam.** As que usam equações
#      normais TÊM de perder dígitos no caso mal-condicionado: é a previsão do
#      projeto, e se uma delas passasse a concordar, a tese estaria errada e
#      este teste é que avisaria.
#
# Nunca `set -e`: ele aborta no primeiro `[ ]` falso e a suíte vira "para no
# primeiro erro" em vez de "relata todos".
set -uo pipefail

cd "$(dirname "$0")"

OK=0
FALHOU=0
PULADO=0

EXIGE="${P05_EXIGE:-0}"

verde()    { printf '\033[32m%s\033[0m' "$1"; }
vermelho() { printf '\033[31m%s\033[0m' "$1"; }
cinza()    { printf '\033[90m%s\033[0m' "$1"; }

passa() { printf '  %s    %s\n' "$(verde ok)" "$1"; OK=$((OK+1)); }
falha() { printf '  %s %s\n' "$(vermelho FALHA)" "$1"; FALHOU=$((FALHOU+1)); }
pula()  {
    if [ "$EXIGE" = "1" ]; then
        printf '  %s %s\n' "$(vermelho FALHA)" "$1 (P05_EXIGE=1)"
        FALHOU=$((FALHOU+1))
    else
        printf '  %s  %s\n' "$(cinza pulado)" "$1"
        PULADO=$((PULADO+1))
    fi
}
secao() { printf '\n%s\n' "$(cinza "$1")"; }
tem()   { command -v "$1" >/dev/null 2>&1; }

printf '\n%s\n' '=============================================================='
printf '%s\n' 'datalab — o mesmo modelo, e o que o algoritmo custa'
printf '%s\n' '=============================================================='

# ---------------------------------------------------------------------------
secao 'toolchains'

for par in "python3:Python" "Rscript:R" "octave:Octave" \
           "gfortran:Fortran" "gretlcli:hansl" "sqlite3:SQL"; do
    cmd="${par%%:*}"; nome="${par##*:}"
    if tem "$cmd"; then
        passa "$nome ($cmd) presente"
    else
        pula "$nome: $cmd ausente"
    fi
done

if ! tem python3 || ! python3 -c 'import numpy' 2>/dev/null; then
    falha 'numpy ausente: a REFERÊNCIA não pode rodar, e sem ela não há o que comparar'
    printf '\n  %s passaram, %s falharam\n\n' "$(verde "$OK")" "$FALHOU"
    exit 1
fi

# ---------------------------------------------------------------------------
secao 'fortran/ — os dois algoritmos, mesmo compilador, mesmas flags'

if ! tem gfortran; then
    pula 'gfortran ausente'
else
    # `-Wall -Wextra` e a saida tem de ser VAZIA. Dois avisos de
    # `-Wcompare-reals` apareceram na primeira versao (comparar real com zero
    # exato na guarda do Householder), e a correcao foi usar `tiny()`.
    saida=$(gfortran -O2 -std=f2008 -Wall -Wextra -o fortran/modelo \
              fortran/modelo.f90 2>&1)
    if [ -z "$saida" ] && [ -x fortran/modelo ]; then
        passa 'o Fortran compila sem um único aviso com -Wall -Wextra'
    else
        falha 'o Fortran não compila limpo'
        printf '%s\n' "$saida" | head -4 | sed 's/^/        /'
    fi
fi

# ---------------------------------------------------------------------------
secao 'dados/ — os números de condição que justificam as tolerâncias'

cond=$(python3 python/referencia.py --condicao 2>&1)
if printf '%s' "$cond" | grep -q 'bem: condicao'; then
    passa 'os números de condição são medidos, não supostos'
    printf '%s\n' "$cond" | sed 's/^/        /'
else
    falha 'não consegui medir o número de condição'
fi

# O caso MAL tem de ser severo: `k(XtX)` acima de `1/eps`. Se alguem
# "melhorar" os dados e isso deixar de valer, a demonstracao inteira perde o
# sentido -- e este teste e que avisa.
if python3 - <<'PY'
import subprocess
import sys

out = subprocess.run(["python3", "python/referencia.py", "--condicao"],
                     capture_output=True, text=True).stdout
for linha in out.splitlines():
    if linha.startswith("mal:"):
        k = float(linha.split("condicao(X)=")[1].split()[0])
        k2 = k * k
        limite = 1.0 / 2.220446049250313e-16
        if k2 > limite:
            print(f"        k(XtX)={k2:.2e} > 1/eps={limite:.2e}")
            sys.exit(0)
        print(f"        k(XtX)={k2:.2e} NAO passa de 1/eps={limite:.2e}")
        sys.exit(1)
sys.exit(1)
PY
then
    passa 'o caso mal é severo: XᵗX é numericamente singular'
else
    falha 'o caso mal deixou de ser severo: a demonstração perde o sentido'
fi

# ---------------------------------------------------------------------------
secao 'a comparação, com as tolerâncias de TOLERANCIA.md'

MEDIDO="$(mktemp)"
trap 'rm -f "$MEDIDO"' EXIT

if ! python3 compara.py --json > "$MEDIDO" 2>"$MEDIDO.err"; then
    falha 'o comparador falhou'
    head -5 "$MEDIDO.err" | sed 's/^/        /'
else
    # Os limiares, e a origem de cada um:
    #
    #   bem: 1e-10 para TODAS. Medido: pior caso 2,1e-14 -- quatro ordens de
    #        margem. `k*eps` do caso bem e 5,0e-15.
    #
    #   mal, familia QR/SVD: 1e-6. Medido: pior caso 1,4e-08. O limite teorico
    #        `k*eps` e 1,7e-06, entao 1e-6 e o proprio limite do problema.
    #
    #   mal, familia equacoes normais: tem de DIVERGIR acima de 1e-4. Medido:
    #        3,4e-03 (Gauss), 2,4e-02 (Cholesky do Julia) e 4,0e-01 (Cramer).
    #        Isto nao e tolerancia: e asserção da previsão.
    #
    #        E a ORDEM entre as tres e informativa: a mesma familia de
    #        algoritmo, com tres fatoracoes diferentes, erra por uma ordem de
    #        grandeza de diferenca entre si. Nao e so "equacoes normais sao
    #        ruins": QUAL fatoracao se usa depois tambem importa.
    python3 - "$MEDIDO" <<'PY'
import json
import sys

QR_SVD = {"python", "R", "octave", "fortran-qr", "hansl", "julia-qr"}
NORMAIS = {"fortran-nrm", "sql", "julia-nrm"}

TOL_BEM = 1e-10
TOL_MAL_QR = 1e-6
DIVERGE_MIN = 1e-4

dados = json.load(open(sys.argv[1]))
falhou = 0


def ok(msg):
    print(f"  \033[32mok\033[0m    {msg}")


def bad(msg):
    global falhou
    print(f"  \033[31mFALHA\033[0m {msg}")
    falhou += 1


# --- os dois conjuntos cobrem TODAS as implementacoes? --------------------
#
# Esta verificacao existe porque sem ela ha um buraco silencioso: no caso
# `mal`, as checagens iteram sobre QR_SVD e NORMAIS. Uma implementacao que nao
# esteja em nenhum dos dois NAO E VERIFICADA ALI -- e a suite passa verde,
# porque nada reclama de um conjunto incompleto.
#
# Foi exatamente o risco ao acrescentar o Julia: registra-lo no `compara.py` e
# esquecer aqui daria dois numeros bonitos na tabela e zero verificacao sobre
# eles.
#
# E a mesma falha que este portfolio registrou onze vezes com outro nome -- o
# instrumento que esconde o proprio sinal. A diferenca e que aqui ela esta
# fechada por construcao: implementacao nova sem familia declarada REPROVA a
# suite, em vez de ser ignorada.
todas = {l["impl"] for caso in dados.values() for l in caso["linhas"]}
classificadas = QR_SVD | NORMAIS
sem_familia = todas - classificadas
sobrando = classificadas - todas

if sem_familia:
    bad(f"implementações sem família declarada: {', '.join(sorted(sem_familia))}"
        f" -- elas NÃO seriam verificadas no caso mal")
elif sobrando:
    # Nao e falha: uma implementacao pode estar declarada e ter sido pulada
    # por falta de ferramenta. Mas o aviso evita que um nome errado numa das
    # listas passe por verificacao que nao acontece.
    print(f"  [90maviso[0m   declaradas mas ausentes da medição: "
          f"{', '.join(sorted(sobrando))}")
else:
    ok(f"as {len(todas)} implementações estão todas classificadas por família")

# --- caso bem: todas concordam ---------------------------------------------
bem = dados["bem"]["linhas"]
piores = [(l["pior"], l["impl"]) for l in bem if "pior" in l]
ausentes = [l["impl"] for l in bem if "pior" not in l]

if piores:
    pior, quem = max(piores)
    if pior <= TOL_BEM:
        ok(f"caso bem: {len(piores)} implementações dentro de {TOL_BEM:.0e} "
           f"(pior {pior:.1e}, em {quem})")
    else:
        bad(f"caso bem: {quem} divergiu {pior:.1e}, acima de {TOL_BEM:.0e}")

for a in ausentes:
    print(f"  \033[90mpulado\033[0m  caso bem: {a} não rodou")

# --- caso mal: a familia QR/SVD concorda ----------------------------------
mal = {l["impl"]: l for l in dados["mal"]["linhas"]}

qr = [(mal[i]["pior"], i) for i in QR_SVD if i in mal and "pior" in mal[i]]
if qr:
    pior, quem = max(qr)
    if pior <= TOL_MAL_QR:
        ok(f"caso mal: a família QR/SVD fica dentro de {TOL_MAL_QR:.0e} "
           f"(pior {pior:.1e}, em {quem})")
    else:
        bad(f"caso mal: {quem} divergiu {pior:.1e} usando QR/SVD")

# --- caso mal: as equacoes normais TEM de divergir ------------------------
#
# Esta e a asserção da previsão do projeto, e nao uma tolerancia. Se uma
# implementacao de equacoes normais passasse a concordar, a tese estaria
# errada.
for i in sorted(NORMAIS):
    if i not in mal or "pior" not in mal[i]:
        print(f"  \033[90mpulado\033[0m  caso mal: {i} não rodou")
        continue
    d = mal[i]["pior"]
    if d >= DIVERGE_MIN:
        ok(f"caso mal: {i} perde dígitos como previsto ({d:.1e} ≥ "
           f"{DIVERGE_MIN:.0e})")
    else:
        bad(f"caso mal: {i} NÃO divergiu ({d:.1e}): a tese do projeto "
            f"depende disso")

# --- e a assimetria entre coeficiente e ajuste ----------------------------
#
# No caso mal-condicionado, as grandezas de AJUSTE (R2, sigma) continuam bem
# determinadas para quem usa QR -- e e isso que torna o problema traicoeiro:
# o modelo preve bem e os coeficientes nao valem nada.
for i in ("R", "fortran-qr"):
    if i in mal and "pior" in mal[i]:
        coef, ajuste = mal[i]["pior"], mal[i]["pior_ajuste"]
        if ajuste < coef / 100:
            ok(f"caso mal: em {i}, o ajuste erra {ajuste:.1e} e os "
               f"coeficientes {coef:.1e}")
        else:
            bad(f"caso mal: em {i} o ajuste errou tanto quanto os "
                f"coeficientes ({ajuste:.1e} vs {coef:.1e})")

# --- o achado do SQL: ate o AJUSTE erra ----------------------------------
if "sql" in mal and "pior_ajuste" in mal["sql"]:
    a = mal["sql"]["pior_ajuste"]
    if a >= 1e-2:
        ok(f"caso mal: no SQL até o AJUSTE erra {a:.1e} -- e nada na saída avisa")
    else:
        bad(f"caso mal: o ajuste do SQL errou só {a:.1e}; o README afirma ≥1e-2")

sys.exit(1 if falhou else 0)
PY
    if [ $? -eq 0 ]; then
        OK=$((OK+1))
    else
        FALHOU=$((FALHOU+1))
    fi
fi

# ---------------------------------------------------------------------------
secao 'a referência gravada está em dia?'

# ESTE TESTE TAMBEM COMPARA COM TOLERANCIA, e a primeira versao nao comparava.
#
# Ela usava `[ "$atual" = "$(cat dados/esperado/bem.json)" ]` -- comparacao de
# TEXTO -- e passou localmente e FALHOU no CI.
#
# A causa e exatamente o assunto deste projeto: o LAPACK do runner do GitHub
# nao e o mesmo build do LAPACK desta maquina, e a SVD devolve bits diferentes
# nos ultimos digitos. O arquivo gravado e um instantaneo de ponto flutuante,
# e exigir igualdade textual dele e o mesmo erro que exigir `diff` entre as
# implementacoes.
#
# Foi o projeto ensinando a propria licao ao seu autor: a disciplina de
# tolerancia valia para as sete implementacoes e nao para o instantaneo, que e
# produzido pela mesma aritmetica.
#
# O que o teste confere agora: que o gravado esta dentro de 1e-10 do
# recalculado -- a mesma tolerancia do caso bem-condicionado, pelo mesmo
# motivo. Divergencia ACIMA disso significa que os dados ou o modelo mudaram e
# o instantaneo ficou velho; abaixo, e a mesma diferenca de BLAS que o projeto
# existe para medir.
if python3 - <<'PY'
import json
import subprocess
import sys

TOL = 1e-10

atual = json.loads(subprocess.run(
    ["python3", "python/referencia.py", "bem", "--json"],
    capture_output=True, text=True, check=True).stdout)
gravado = json.load(open("dados/esperado/bem.json"))

piores = []
for campo in ("r2", "sigma", "condicao"):
    a, g = atual[campo], gravado[campo]
    piores.append((abs(a - g) / max(abs(g), 1e-300), campo))
for i, (a, g) in enumerate(zip(atual["beta"], gravado["beta"])):
    piores.append((abs(a - g) / max(abs(g), 1e-300), f"beta[{i}]"))

piores.sort(reverse=True)
pior, qual = piores[0]

if atual["gl"] != gravado["gl"] or atual["rank"] != gravado["rank"]:
    print(f"        gl ou rank mudaram: o modelo nao e mais o mesmo",
          file=sys.stderr)
    sys.exit(1)

if pior <= TOL:
    print(f"        pior |delta|rel = {pior:.1e} em {qual}, dentro de {TOL:.0e}")
    sys.exit(0)

print(f"        pior |delta|rel = {pior:.1e} em {qual}, ACIMA de {TOL:.0e}",
      file=sys.stderr)
sys.exit(1)
PY
then
    passa 'dados/esperado/bem.json confere com o recalculado (com tolerância)'
else
    falha 'o esperado gravado divergiu acima da tolerância: rode --gravar'
fi

printf '\n%s\n' '=============================================================='
if [ "$PULADO" -gt 0 ]; then
    printf '  %s passaram, %s falharam, %s pulado(s)\n' \
        "$(verde "$OK")" "$FALHOU" "$(cinza "$PULADO")"
else
    printf '  %s passaram, %s falharam\n' "$(verde "$OK")" "$FALHOU"
fi
printf '%s\n\n' '=============================================================='

[ "$FALHOU" -eq 0 ]
