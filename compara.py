#!/usr/bin/env python3
"""compara.py — roda todas as implementações e mede a divergência.

    python3 compara.py              # tabela das duas casos
    python3 compara.py --json

## Por que um comparador separado, e não só o verifica.sh

Porque a pergunta deste projeto não é "passou ou falhou": é **quanto cada
implementação diverge, e por quê**. Um script de teste responde a primeira; a
tabela que este programa imprime responde a segunda, e é ela que vai no
README.

O `verifica.sh` usa este módulo e aplica os limiares. A separação é a mesma do
`p03-otp-mesh`, onde o `cruzado.sh` mede e o `verifica.sh` decide.
"""

import json
import os
import subprocess
import sys

RAIZ = os.path.dirname(os.path.abspath(__file__))

# Cada implementação, com o algoritmo que ela usa POR BAIXO.
#
# A coluna do algoritmo não é decoração: é a variável que o projeto mede. Duas
# linguagens com o mesmo algoritmo concordam; a mesma linguagem com dois
# algoritmos não.
IMPLS = [
    ("python",      "SVD (LAPACK gelsd)",      ["python3", "python/referencia.py", "{caso}"]),
    ("R",           "QR (LINPACK dqrdc2)",     ["Rscript", "r/modelo.R", "{caso}"]),
    ("octave",      "QR (operador \\)",         ["octave", "--no-gui", "--quiet", "octave/modelo.m", "{caso}"]),
    ("fortran-qr",  "QR Householder, à mão",   ["./fortran/modelo", "{caso}", "qr"]),
    ("hansl",       "gretl (ver abaixo)",      ["bash", "hansl/roda.sh", "{caso}"]),
    ("fortran-nrm", "equações normais + Gauss", ["./fortran/modelo", "{caso}", "normal"]),
    ("sql",         "equações normais + Cramer", ["bash", "sql/roda.sh", "{caso}"]),
]

CAMPOS = ("b0", "b1", "b2", "r2", "sigma")

AMBIENTE = dict(os.environ)
# `C.UTF-8` e nao `C`: o Octave usa Qt, que emite aviso de quatro linhas em
# stderr com locale sem UTF-8. O `C.UTF-8` mantem o PONTO decimal, que e o que
# a comparacao textual exige, e cala o aviso.
AMBIENTE["LC_ALL"] = "C.UTF-8"


def roda(cmd, caso):
    """Executa uma implementação e devolve {campo: valor}."""
    args = [a.replace("{caso}", caso) for a in cmd]
    p = subprocess.run(args, capture_output=True, text=True, cwd=RAIZ,
                       env=AMBIENTE)
    if p.returncode != 0:
        return None, f"retorno {p.returncode}: {p.stderr.strip()[:120]}"

    d = {}
    for linha in p.stdout.splitlines():
        if "=" not in linha:
            continue
        k, v = linha.split("=", 1)
        k = k.strip()
        if k in CAMPOS:
            try:
                d[k] = float(v)
            except ValueError:
                return None, f"valor ilegível em {k}: {v!r}"

    faltando = [c for c in CAMPOS if c not in d]
    if faltando:
        return None, f"campos faltando: {', '.join(faltando)}"
    return d, None


def relativo(a, b):
    """|a-b| / |a|, com o caso de a == 0 tratado.

    Relativo e nao absoluto pelo motivo de TOLERANCIA.md: um erro de 1e-10
    num coeficiente de valor 0,8 e desprezivel; o mesmo erro num coeficiente
    de valor 1e-12 e cem vezes o valor.
    """
    if a == 0.0:
        return abs(b)
    return abs(a - b) / abs(a)


def mede(caso):
    """Roda tudo e devolve a divergência de cada implementação."""
    ref, erro = roda(IMPLS[0][2], caso)
    if ref is None:
        raise SystemExit(f"a REFERÊNCIA falhou no caso {caso}: {erro}")

    linhas = []
    for nome, algoritmo, cmd in IMPLS:
        got, erro = roda(cmd, caso)
        if got is None:
            linhas.append({"impl": nome, "algoritmo": algoritmo,
                           "erro": erro})
            continue

        # O pior campo, e qual foi. Reportar QUAL campo divergiu mais importa:
        # no caso mal-condicionado os coeficientes divergem e o R2 nao, e essa
        # assimetria e o conteudo estatistico do problema.
        piores = sorted(
            ((relativo(ref[c], got[c]), c) for c in CAMPOS), reverse=True)
        pior, qual = piores[0]

        # O pior SO entre as grandezas de AJUSTE (R2 e sigma), que sao bem
        # determinadas mesmo com colinearidade -- diferente dos coeficientes.
        pior_ajuste = max(relativo(ref[c], got[c]) for c in ("r2", "sigma"))

        linhas.append({
            "impl": nome,
            "algoritmo": algoritmo,
            "pior": pior,
            "campo": qual,
            "pior_ajuste": pior_ajuste,
            "valores": got,
        })

    return {"caso": caso, "referencia": ref, "linhas": linhas}


def imprime(res):
    print(f"\n=== caso {res['caso']} ===")
    print(f"{'implementação':<14} {'algoritmo':<28} "
          f"{'pior |Δ|rel':>12} {'campo':>7} {'ajuste':>10}")
    print("-" * 76)
    for l in res["linhas"]:
        if "erro" in l:
            print(f"{l['impl']:<14} {l['algoritmo']:<28} "
                  f"{'FALHOU: ' + l['erro']:>12}")
            continue
        print(f"{l['impl']:<14} {l['algoritmo']:<28} "
              f"{l['pior']:>12.1e} {l['campo']:>7} {l['pior_ajuste']:>10.1e}")


def main():
    como_json = "--json" in sys.argv
    casos = [a for a in sys.argv[1:] if not a.startswith("-")] or ["bem", "mal"]

    tudo = {c: mede(c) for c in casos}

    if como_json:
        print(json.dumps(tudo, indent=2, sort_keys=True))
        return 0

    for c in casos:
        imprime(tudo[c])
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
