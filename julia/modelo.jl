#!/usr/bin/env julia
# modelo.jl — mínimos quadrados em Julia, pelos DOIS algoritmos.
#
#     julia julia/modelo.jl bem          # QR, via o operador \
#     julia julia/modelo.jl bem normal   # equações normais, à mão
#
# ## Por que esta implementação faz os dois
#
# A variável que este projeto mede não é a linguagem: é o **algoritmo**. Duas
# linguagens com o mesmo algoritmo concordam até a última casa útil; a mesma
# linguagem com dois algoritmos **divergem**, e o quanto divergem é previsto
# pelo número de condição.
#
# O Fortran já faz os dois à mão, e serve de controle. O Julia entra porque
# ele é o caso mais interessante do conjunto: a forma idiomática de resolver
# mínimos quadrados é um **único caractere**.
#
# ## O que `A \ b` faz quando A não é quadrada
#
#     beta = X \ y
#
# Em Julia, `\` é resolução de sistema, e para uma matriz **retangular** ele
# não "inverte" nada: despacha para `qr(X, ColumnNorm()) \ y`, isto é
# decomposição QR **com pivotamento de colunas**, via LAPACK `dgeqp3`.
#
# Isso é relevante para este projeto por dois motivos:
#
# 1. é o mesmo algoritmo de família que o R usa (`dqrdc2` do LINPACK) e que o
#    Octave usa com o `\` dele — então os três devem concordar bem mais entre
#    si do que com as equações normais;
#
# 2. **o pivotamento** é o que torna o caso `mal.csv` tratável. Com número de
#    condição 7,4e+09, as equações normais perdem metade dos dígitos; a QR
#    pivotada perde bem menos, e é por isso que o `TOLERANCIA.md` separa as
#    duas famílias em vez de exigir uma tolerância única.
#
# ## O que `rank` devolve, e por que não é `size(X, 2)`
#
# `rank(X)` faz uma SVD e conta valores singulares acima de uma tolerância.
# Para `mal.csv` ele ainda devolve 3 — a matriz é quase singular, não
# singular — e essa distinção é exatamente o que o projeto quer mostrar: o
# posto é cheio, e o resultado é ruim mesmo assim.
#
# ## Uma diferença de Julia que vale notar
#
# `sum(v)` em Julia usa **soma por pares** (*pairwise summation*), não soma
# sequencial. O erro cresce com `O(log n)` em vez de `O(n)`, o que é melhor —
# e é mais uma razão para este projeto não comparar byte a byte: duas
# implementações corretas somando a mesma coluna de números em ordens
# diferentes dão resultados diferentes nos últimos dígitos, e a de Julia não é
# a sequencial.

using LinearAlgebra
using Printf
using DelimitedFiles

"""
    carrega(caso) -> (X, y)

Lê `dados/<caso>.csv` e monta a matriz de desenho com a coluna de 1s na
frente, na mesma ordem das outras implementações: `[1 x1 x2]`.

A ordem importa porque `b0`, `b1` e `b2` são comparados por posição, e uma
matriz com as colunas trocadas daria coeficientes certos em lugares errados --
e o `compara.py` reportaria divergência numérica onde o erro é de layout.
"""
function carrega(caso::AbstractString)
    aqui = dirname(dirname(abspath(@__FILE__)))
    caminho = joinpath(aqui, "dados", "$(caso).csv")

    # `header=true` descarta a primeira linha (x1,x2,y) e devolve os nomes
    # separados. Sem isso, o `readdlm` tentaria converter "x1" em Float64 e
    # devolveria uma matriz de `Any` -- que funciona, e silenciosamente passa
    # strings para a álgebra linear.
    bruto, _ = readdlm(caminho, ',', Float64, '\n'; header=true)

    n = size(bruto, 1)
    X = hcat(ones(n), bruto[:, 1], bruto[:, 2])
    y = bruto[:, 3]
    return X, y
end

"""
    ajusta_qr(X, y) -> beta

O caminho idiomático: um caractere.

`\\` numa matriz retangular despacha para QR com pivotamento de colunas
(LAPACK `dgeqp3`). É a mesma FAMÍLIA de algoritmo do R e do Octave, e é por
isso que os três concordam muito mais entre si do que com as equações
normais.
"""
ajusta_qr(X, y) = X \ y

"""
    ajusta_normal(X, y) -> beta

As equações normais, montadas à mão: resolve `(XᵗX) β = Xᵗy`.

Este caminho existe para **divergir**, não para concordar. Ele eleva o número
de condição ao quadrado, e no caso `mal.csv` -- condição 7,4e+09 -- isso
significa perder cerca de metade dos dígitos de um Float64.

A fatoração usada é `cholesky`, que é a decomposição natural para uma matriz
simétrica positiva-definida como `XᵗX`. Ela **falha** se a matriz não for
positiva-definida, e falhar é o comportamento certo: uma Cholesky que
"funciona" numa matriz indefinida devolveria números sem significado. O
`Symmetric` diz ao Julia para olhar só um triângulo, o que evita que erro de
arredondamento em `XᵗX` torne a matriz assimétrica por 1e-16 e faça a
fatoração reclamar de algo que não é o problema.
"""
function ajusta_normal(X, y)
    XtX = Symmetric(X' * X)
    Xty = X' * y
    return cholesky(XtX) \ Xty
end

function main()
    if length(ARGS) < 1
        println(stderr, "uso: modelo.jl <bem|mal> [normal]")
        return 64
    end
    caso = ARGS[1]
    algoritmo = length(ARGS) >= 2 ? ARGS[2] : "qr"

    X, y = carrega(caso)
    n, p = size(X)

    beta = algoritmo == "normal" ? ajusta_normal(X, y) : ajusta_qr(X, y)

    residuo = y .- X * beta
    sqe = sum(abs2, residuo)                      # soma dos quadrados do erro
    sqt = sum(abs2, y .- sum(y) / n)              # soma total
    gl = n - p                                    # graus de liberdade

    r2 = 1 - sqe / sqt
    sigma = sqrt(sqe / gl)

    # `cond(X)` é a razão entre o maior e o menor valor singular, calculada
    # por SVD -- a MESMA definição que a referência em Python usa. Medir a
    # condição com uma definição diferente daria uma tolerância derivada de
    # um número que não é comparável, e o `TOLERANCIA.md` deriva a tolerância
    # exatamente deste valor.
    condicao = cond(X)

    # `%.17g` e não `%.15f`: dezessete dígitos significativos é o que garante
    # ida-e-volta exata de um Float64 em decimal. Com menos, a comparação
    # mediria a minha formatação em vez da aritmética da linguagem.
    @printf("b0=%.17g\n", beta[1])
    @printf("b1=%.17g\n", beta[2])
    @printf("b2=%.17g\n", beta[3])
    @printf("r2=%.17g\n", r2)
    @printf("sigma=%.17g\n", sigma)
    @printf("gl=%d\n", gl)
    @printf("rank=%d\n", rank(X))
    @printf("condicao=%.17g\n", condicao)
    return 0
end

exit(main())
