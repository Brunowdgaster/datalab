# modelo.mojo — mínimos quadrados em Mojo, pelos DOIS algoritmos.
#
#     pixi run mojo run mojo/modelo.mojo bem
#     pixi run mojo run mojo/modelo.mojo bem normal
#
# ## Três coisas que o Mojo 1.2 mudou, e que invalidam quase todo material público
#
# Medidas nesta máquina em 2026-11-17, contra Mojo 1.2.0 (2016d0cd). Qualquer
# tutorial de Mojo escrito antes disso usa a forma antiga nas três:
#
# **1. `fn` foi REMOVIDO.** A mensagem é literal:
#
#     error: 'fn' has been removed; use 'def' instead
#
# Todo exemplo de Mojo que existe na internet começa com `fn main()`. Nenhum
# compila aqui.
#
# **2. `def` não implica mais `raises`.** No Mojo antigo a distinção era o
# assunto do par `fn`/`def`: `def` podia levantar exceção, `fn` não. Agora `fn`
# não existe **e** `def` também não implica — é preciso escrever `raises`:
#
#     error: cannot call function that may raise in a context that cannot raise
#     note: or mark surrounding function as 'raises'
#
# Então a mudança não foi só de palavra-chave: a semântica foi junto.
#
# **3. A biblioteca padrão está sob `std`.** `bitcast` vinha de `memory`; hoje
# é `std.memory`. O compilador diz qual, o que ajuda:
#
#     note: did you mean to import it from 'std.memory'?
#
# ## E uma coisa que NÃO mudou, mas que me surpreendeu: literais são exatos
#
# Esta é a mais importante para um projeto de aritmética, e foi medida antes de
# uma linha deste arquivo ser escrita:
#
#     var lit: Float64 = 0.1 + 0.2     ->  0.3
#     var a = 0.1; var b = 0.2; a + b  ->  0.30000000000000004
#     lit == exe                       ->  False
#
# O Mojo avalia `0.1 + 0.2` em **precisão arbitrária em tempo de compilação** e
# arredonda **uma vez** para Float64, dando exatamente `0.3`. Em execução, dois
# Float64 somados dão `0.30000000000000004` — que é o que Python, C, Java e
# todo o resto dão.
#
# As duas estão certas, e **são números diferentes**. A consequência prática
# para este arquivo: nenhuma constante numérica aqui participa da conta. Tudo
# vem do CSV, parseado em execução, e por isso a comparação mede a aritmética
# IEEE 754 e não a álgebra do compilador.
#
# Se algum dia alguém escrever `var meia: Float64 = 1.0 / 3.0` aqui e usar na
# conta, o resultado vai divergir das outras dez implementações por um motivo
# que não é numérico. É a armadilha que este comentário existe para evitar.
#
# ## Por que a saída usa `String(x)` e não um formato com precisão
#
# `String(Float64)` no Mojo dá a representação **mais curta que volta ao bit
# exato** — medido: `atof(String(x)) == x` e os bits idênticos, inclusive para
# `1/3` e para `0.1+0.2`.
#
# Isso é melhor que o `%.17g` que as outras implementações usam: 17 dígitos é
# uma garantia *suficiente* de ida-e-volta, e a mais curta é a *mínima*. As
# duas identificam o mesmo `double`, e o `compara.py` faz `float()` em cima --
# então o que importa é voltar exato, e volta.

from std.math import sqrt
from std.sys import argv


# `Tuple[...]` e nao `(...)`: o Mojo aceita a forma com parenteses para
# CONSTRUIR uma tupla e a recusa para DECLARAR o tipo dela --
#
#     error: expected a type, found a tuple value;
#            use 'Tuple[...]' to write a tuple type
#
# Python nao faz essa distincao (`-> tuple[int, str]` com parenteses
# funciona), e e uma das varias vezes em que a semelhanca com Python e
# superficial.
def le_csv(
    caminho: String, mut x: List[Float64], mut y: List[Float64]
) raises -> Int:
    """Lê o CSV para `x` (achatada, linha-maior) e `y`, e devolve n.

    A matriz de desenho é `[1 x1 x2]`, com a coluna de 1s primeiro, na mesma
    ordem das outras implementações -- `b0`, `b1` e `b2` são comparados por
    POSIÇÃO, e colunas trocadas dariam coeficientes certos em lugares errados.

    X é achatada (`x[i * P + j]`) em vez de `List[List[Float64]]` porque é
    assim que se escreve numérico em Mojo: uma lista de listas custa uma
    indireção por linha, e o ponto da linguagem é não ter essa indireção.
    """
    var conteudo = open(caminho, "r").read()
    var linhas = conteudo.split("\n")

    var n = 0

    for idx in range(len(linhas)):
        # A primeira linha é o cabeçalho `x1,x2,y`. Pular por ÍNDICE e não
        # por tentativa-e-erro de conversão: um `atof` que falha e é engolido
        # transformaria um dado corrompido em linha silenciosamente ausente.
        if idx == 0:
            continue
        var linha = String(linhas[idx]).strip()
        # `byte_length()` e nao `len(linha)`, porque o Mojo RECUSA `len` numa
        # string -- e a mensagem de erro e um argumento de projeto:
        #
        #     error: `len(String/StringSlice)` is not supported because Mojo
        #     strings are UTF-8 encoded, so a single length is ambiguous: it
        #     could mean the number of UTF-8 bytes, the number of Unicode code
        #     points, or the number of user-visible characters (grapheme
        #     clusters).
        #
        # Python responde pontos de codigo, Go e Rust respondem bytes, e os
        # dois estao certos sobre coisas diferentes -- em silencio. Para "a
        # linha esta vazia?" qualquer das tres serve, e e justamente por isso
        # que o erro e facil de ignorar: a ambiguidade so morde em dados com
        # acento ou emoji, bem depois.
        if linha.byte_length() == 0:
            continue

        var campos = linha.split(",")
        if len(campos) != 3:
            raise Error("esperava 3 colunas, achei " + String(len(campos)))

        x.append(1.0)
        x.append(atof(String(campos[0]).strip()))
        x.append(atof(String(campos[1]).strip()))
        y.append(atof(String(campos[2]).strip()))
        n += 1

    if n == 0:
        raise Error("nenhuma linha de dados em " + caminho)
    return n


def qr_householder(
    x0: List[Float64], y0: List[Float64], n: Int, p: Int
) raises -> List[Float64]:
    """QR por reflexões de Householder, e substituição regressiva.

    É o MESMO algoritmo de `fortran/modelo.f90` e `scala/modelo.scala`, e os
    três devem concordar. Essa concordância é o controle do projeto: se o Mojo
    divergir dos outros dois usando o mesmo algoritmo, o problema está numa das
    implementações, não na aritmética da linguagem.
    """
    # Cópias: o algoritmo é destrutivo, e devolver a matriz do chamador
    # modificada faria a SEGUNDA chamada dar outro resultado.
    var a = List[Float64]()
    for i in range(len(x0)):
        a.append(x0[i])
    var b = List[Float64]()
    for i in range(len(y0)):
        b.append(y0[i])

    for k in range(p):
        var norma: Float64 = 0.0
        for i in range(k, n):
            norma += a[i * p + k] * a[i * p + k]
        # `sqrt` e NAO `norma ** 0.5`, e a diferenca foi MEDIDA.
        #
        # A primeira versao deste arquivo usava `** 0.5`, e a regressao
        # divergiu das outras dez implementacoes em 1,2e-12 -- contra 1e-14 do
        # Scala, que usa o MESMO algoritmo. A comparacao do projeto achou o
        # defeito; eu nao o teria notado lendo o codigo.
        #
        # A causa, medida em 2000 valores:
        #
        #     v = 650.0000000000001
        #     v ** 0.5  = 25.495097567999917
        #     sqrt(v)   = 25.495097567963928
        #     pior |rel| = 1,4e-12
        #
        # `sqrt` e UMA instrucao IEEE 754, arredondada corretamente a 0,5 ulp.
        # `pow(x, 0.5)` passa por `exp(0.5 * log x)` -- duas funcoes
        # transcendentais, cada uma com seu erro, e nenhuma obrigada a ser
        # exata. Perde ~4 digitos.
        #
        # Nenhum compilador avisa, porque matematicamente as duas sao iguais.
        norma = sqrt(norma)

        if norma > 0.0:
            # O sinal evita cancelamento: se a[k][k] é positivo, somar uma
            # norma positiva aumenta a magnitude em vez de subtrair dois
            # números próximos. É a diferença entre Householder estável e
            # Householder que perde dígitos no primeiro passo.
            var alfa: Float64 = -norma if a[k * p + k] > 0.0 else norma

            var v = List[Float64]()
            for _ in range(n):
                v.append(0.0)
            for i in range(k, n):
                v[i] = a[i * p + k]
            v[k] -= alfa

            var vtv: Float64 = 0.0
            for i in range(k, n):
                vtv += v[i] * v[i]

            if vtv > 0.0:
                for j in range(k, p):
                    var vta: Float64 = 0.0
                    for i in range(k, n):
                        vta += v[i] * a[i * p + j]
                    var fator = 2.0 * vta / vtv
                    for i in range(k, n):
                        a[i * p + j] -= fator * v[i]

                var vtb: Float64 = 0.0
                for i in range(k, n):
                    vtb += v[i] * b[i]
                var fb = 2.0 * vtb / vtv
                for i in range(k, n):
                    b[i] -= fb * v[i]

    var beta = List[Float64]()
    for _ in range(p):
        beta.append(0.0)
    for ii in range(p):
        var i = p - 1 - ii
        var soma = b[i]
        for j in range(i + 1, p):
            soma -= a[i * p + j] * beta[j]
        beta[i] = soma / a[i * p + i]
    # `^` TRANSFERE a propriedade em vez de copiar.
    #
    # O Mojo 1.2 recusa `return beta` com:
    #
    #     error: value of type 'List[Float64]' cannot be implicitly copied,
    #            it does not conform to 'ImplicitlyCopyable'
    #     note: consider transferring the value with '^'
    #     note: you can copy it explicitly with '.copy()'
    #
    # As duas saidas existem e NAO sao equivalentes: `.copy()` aloca e copia
    # os n elementos, `^` move o buffer. Para uma lista de 3 doubles a
    # diferenca e irrelevante; para a matriz achatada de uma regressao com
    # milhoes de linhas, e a diferenca entre O(1) e O(n).
    #
    # O ponto da linguagem e exatamente este: ela NAO escolhe por voce, e o
    # erro de compilacao e a pergunta. Python copia referencia em silencio,
    # C++ copia valor em silencio -- os dois escondem a decisao.
    return beta^


def equacoes_normais(
    x: List[Float64], y: List[Float64], n: Int, p: Int
) raises -> List[Float64]:
    """Resolve `(XᵗX) β = Xᵗy` por eliminação de Gauss com pivotamento parcial.

    Este caminho existe para **divergir**, não para concordar: montar XᵗX
    eleva o número de condição ao quadrado, e no caso `mal` -- condição
    7,4e+09 -- isso custa cerca de metade dos dígitos de um Float64.

    A fatoração é a mesma de `fortran-nrm` e `scala-nrm` de propósito, para
    que a tabela tenha TRÊS linguagens com a mesma fatoração e três fatorações
    diferentes no total (Gauss, Cholesky no Julia, Cramer no SQL).
    """
    # Matriz aumentada [XᵗX | Xᵗy], achatada com p+1 colunas.
    var m = List[Float64]()
    for _ in range((p) * (p + 1)):
        m.append(0.0)

    for i in range(p):
        for j in range(p):
            var s: Float64 = 0.0
            for k in range(n):
                s += x[k * p + i] * x[k * p + j]
            m[i * (p + 1) + j] = s
        var sy: Float64 = 0.0
        for k in range(n):
            sy += x[k * p + i] * y[k]
        m[i * (p + 1) + p] = sy

    for col in range(p):
        # Pivotamento parcial. Sem ele, um pivô pequeno amplifica o erro -- e
        # em XᵗX, que já está mal-condicionada, pivô pequeno é o caso comum.
        var maior = col
        for i in range(col + 1, p):
            var ai = m[i * (p + 1) + col]
            var am = m[maior * (p + 1) + col]
            var abs_i = -ai if ai < 0.0 else ai
            var abs_m = -am if am < 0.0 else am
            if abs_i > abs_m:
                maior = i
        if maior != col:
            for j in range(p + 1):
                var t = m[col * (p + 1) + j]
                m[col * (p + 1) + j] = m[maior * (p + 1) + j]
                m[maior * (p + 1) + j] = t

        var pivo = m[col * (p + 1) + col]
        for i in range(col + 1, p):
            var fator = m[i * (p + 1) + col] / pivo
            for j in range(col, p + 1):
                m[i * (p + 1) + j] -= fator * m[col * (p + 1) + j]

    var beta = List[Float64]()
    for _ in range(p):
        beta.append(0.0)
    for ii in range(p):
        var i = p - 1 - ii
        var soma = m[i * (p + 1) + p]
        for j in range(i + 1, p):
            soma -= m[i * (p + 1) + j] * beta[j]
        beta[i] = soma / m[i * (p + 1) + i]
    # `^` TRANSFERE a propriedade em vez de copiar.
    #
    # O Mojo 1.2 recusa `return beta` com:
    #
    #     error: value of type 'List[Float64]' cannot be implicitly copied,
    #            it does not conform to 'ImplicitlyCopyable'
    #     note: consider transferring the value with '^'
    #     note: you can copy it explicitly with '.copy()'
    #
    # As duas saidas existem e NAO sao equivalentes: `.copy()` aloca e copia
    # os n elementos, `^` move o buffer. Para uma lista de 3 doubles a
    # diferenca e irrelevante; para a matriz achatada de uma regressao com
    # milhoes de linhas, e a diferenca entre O(1) e O(n).
    #
    # O ponto da linguagem e exatamente este: ela NAO escolhe por voce, e o
    # erro de compilacao e a pergunta. Python copia referencia em silencio,
    # C++ copia valor em silencio -- os dois escondem a decisao.
    return beta^


def main() raises:
    var args = argv()
    if len(args) < 2:
        print("uso: modelo.mojo <bem|mal> [normal]")
        return

    var caso = String(args[1])
    var algoritmo = String("qr")
    if len(args) > 2:
        algoritmo = String(args[2])

    var p = 3
    # `mut` na assinatura de `le_csv`, e as listas criadas AQUI.
    #
    # A primeira versao devolvia `Tuple[List, List, Int]`, e o Mojo recusou:
    #
    #     var y = dados[1]
    #     error: value of type 'List[Float64]' cannot be implicitly copied
    #
    # Tirar a tupla resolve E fica mais claro: `mut` declara na ASSINATURA que
    # a funcao modifica os argumentos, o que nenhuma das outras dez
    # implementacoes deste projeto consegue dizer. Em Python, C ou Scala, saber
    # se uma funcao muta o que recebe exige ler o corpo dela.
    var x = List[Float64]()
    var y = List[Float64]()
    var n = le_csv("dados/" + caso + ".csv", x, y)

    var beta: List[Float64]
    if algoritmo == "normal":
        beta = equacoes_normais(x, y, n, p)
    else:
        beta = qr_householder(x, y, n, p)

    # Resíduo e somas de quadrados, TODAS em execução -- nenhuma constante
    # participa, pelo motivo da seção sobre literais no cabeçalho.
    var sqe: Float64 = 0.0
    for i in range(n):
        var ajustado: Float64 = 0.0
        for j in range(p):
            ajustado += x[i * p + j] * beta[j]
        var r = y[i] - ajustado
        sqe += r * r

    var soma_y: Float64 = 0.0
    for i in range(n):
        soma_y += y[i]
    var media = soma_y / Float64(n)

    var sqt: Float64 = 0.0
    for i in range(n):
        var d = y[i] - media
        sqt += d * d

    var gl = n - p
    var r2 = 1.0 - sqe / sqt
    var sigma = sqrt(sqe / Float64(gl))   # `sqrt`, pelo motivo acima

    print("b0=" + String(beta[0]))
    print("b1=" + String(beta[1]))
    print("b2=" + String(beta[2]))
    print("r2=" + String(r2))
    print("sigma=" + String(sigma))
    print("gl=" + String(gl))
