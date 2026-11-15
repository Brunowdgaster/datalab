#!/usr/bin/env python3
"""referencia.py — o modelo de referência, e os números que as outras conferem.

    python3 python/referencia.py bem      # o caso bem-condicionado
    python3 python/referencia.py mal      # o caso mal-condicionado
    python3 python/referencia.py --gravar
    python3 python/referencia.py --condicao

## O modelo

Mínimos quadrados ordinários: `y = b0 + b1·x1 + b2·x2 + e`.

É o modelo mais simples que ainda tem conteúdo numérico de verdade. Qualquer
coisa mais simples (média, variância) seria somar números e não distinguiria
nada entre as implementações; qualquer coisa mais complexa (máxima
verossimilhança, MCMC) introduziria convergência iterativa, e aí a comparação
mediria o critério de parada de cada biblioteca em vez da aritmética.

## Por que Python é a referência

Pelo mesmo motivo que o C é no `p01-metal-vm` e o Pascal no
`p14-first-code`: não é a mais rápida nem a mais elegante — é a que tem a
implementação mais direta e auditável.

`numpy.linalg.lstsq` usa a rotina `gelsd` do LAPACK, que resolve por **SVD**.
É a mais estável numericamente das três abordagens (SVD > QR > equações
normais), e por isso serve de referência para as outras: quando uma delas
divergir, a dúvida é sobre a outra, não sobre esta.

E a escolha é declarada em vez de implícita, porque ela **importa**: se a
referência usasse equações normais, o caso mal-condicionado teria uma
referência errada, e todas as implementações corretas apareceriam como
divergentes.
"""

import csv
import json
import os
import sys

try:
    import numpy as np
except ImportError:
    print("numpy ausente: sudo apt-get install python3-numpy", file=sys.stderr)
    sys.exit(69)

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DADOS = os.path.join(RAIZ, "dados")

CASOS = ("bem", "mal")


def carrega(caso):
    """Lê o CSV e devolve (X com coluna de 1s, y).

    A coluna de 1s é o intercepto, e montá-la à mão em vez de pedir à
    biblioteca é deliberado: cada linguagem deste projeto a monta de um jeito
    (`cbind(1, x)` em R, `ones(n,1)` em Octave, `add_constant` em
    statsmodels), e explicitar aqui deixa claro que o MODELO é o mesmo.
    """
    caminho = os.path.join(DADOS, f"{caso}.csv")
    with open(caminho, encoding="utf-8") as fh:
        linhas = list(csv.DictReader(fh))

    y = np.array([float(l["y"]) for l in linhas], dtype=np.float64)
    x1 = np.array([float(l["x1"]) for l in linhas], dtype=np.float64)
    x2 = np.array([float(l["x2"]) for l in linhas], dtype=np.float64)

    X = np.column_stack([np.ones_like(x1), x1, x2])
    return X, y


def ajusta(X, y):
    """OLS por SVD (LAPACK gelsd), via numpy.linalg.lstsq.

    `rcond=None` pede o comportamento novo do numpy, em que o corte de
    valores singulares é `max(M,N)*eps`. Deixar o padrão antigo emitiria aviso
    de depreciação e, pior, usaria um corte diferente -- mudando o resultado
    no caso mal-condicionado, que é justamente o que o projeto mede.
    """
    beta, _, rank, sv = np.linalg.lstsq(X, y, rcond=None)

    resid = y - X @ beta
    n, p = X.shape

    # Graus de liberdade: n - p, com p incluindo o intercepto. Errar isto por
    # um muda o erro padrao em ~5% num conjunto deste tamanho -- e e o erro
    # mais comum em implementacao de OLS a mao.
    gl = n - p
    sse = float(resid @ resid)
    sst = float(((y - y.mean()) ** 2).sum())

    return {
        "beta": [float(b) for b in beta],
        "r2": 1.0 - sse / sst,
        "sigma": (sse / gl) ** 0.5,
        "gl": gl,
        "rank": int(rank),
        # O numero de condicao da matriz X, que e o que JUSTIFICA a tolerancia
        # -- ver TOLERANCIA.md. Vem dos valores singulares da propria
        # decomposicao, nao de uma conta separada.
        "condicao": float(sv[0] / sv[-1]),
    }


def formata(x):
    """15 dígitos significativos, científico, ponto decimal, sinal no expoente.

    Cada parte evita uma divergência que não é numérica, e as quatro estão
    justificadas em TOLERANCIA.md. A mais traiçoeira é a locale: R, Octave e
    gretl imprimiriam `2,47` numa máquina em pt_BR.
    """
    return f"{x:.14e}"


def imprime(res):
    for i, b in enumerate(res["beta"]):
        print(f"b{i}={formata(b)}")
    print(f"r2={formata(res['r2'])}")
    print(f"sigma={formata(res['sigma'])}")
    print(f"gl={res['gl']}")


def main():
    args = sys.argv[1:]

    if "--condicao" in args:
        for caso in CASOS:
            X, y = carrega(caso)
            res = ajusta(X, y)
            k = res["condicao"]
            print(f"{caso}: condicao(X)={k:.3e}  "
                  f"condicao(XtX)~={k * k:.3e}  "
                  f"k*eps={k * 2.220446049250313e-16:.1e}")
        return 0

    if "--gravar" in args:
        destino = os.path.join(DADOS, "esperado")
        os.makedirs(destino, exist_ok=True)
        for caso in CASOS:
            X, y = carrega(caso)
            res = ajusta(X, y)
            caminho = os.path.join(destino, f"{caso}.json")
            with open(caminho, "w", encoding="utf-8", newline="\n") as fh:
                json.dump(res, fh, indent=2, sort_keys=True)
                fh.write("\n")
            print(f"gravado: dados/esperado/{caso}.json")
        return 0

    caso = next((a for a in args if not a.startswith("-")), None)
    if caso not in CASOS:
        print(f"uso: referencia.py {{{'|'.join(CASOS)}}} [--json]",
              file=sys.stderr)
        print("     referencia.py --gravar | --condicao", file=sys.stderr)
        return 64

    X, y = carrega(caso)
    res = ajusta(X, y)

    if "--json" in args:
        print(json.dumps(res, indent=2, sort_keys=True))
    else:
        imprime(res)
    return 0


if __name__ == "__main__":
    sys.exit(main())
