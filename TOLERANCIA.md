# Por que este projeto não compara byte a byte, e o que ele compara

Os outros projetos deste portfólio comparam saídas **idênticas**:

* no `p01-metal-vm`, sete portes executam o mesmo bytecode e produzem a mesma
  saída, byte a byte;
* no `p14-first-code`, cinco linguagens produzem o mesmo traço de tartaruga,
  byte a byte;
* no `p10-query-lab`, seis implementações respondem a mesma pergunta e o JSON
  é comparado com `diff`.

**Aqui isso não é possível, e insistir nisso seria desonesto.**

## O que acontece quando se tenta

O modelo deste projeto é uma regressão linear por mínimos quadrados. O
coeficiente angular é um número real, e cada implementação o calcula com
aritmética de ponto flutuante de 64 bits — que **não é associativa**:

```
(a + b) + c  ≠  a + (b + c)
```

Isso não é defeito de nenhuma delas. É o IEEE 754 funcionando como
especificado. E as implementações diferem em três coisas que mudam a ordem das
operações:

| diferença | exemplo |
|---|---|
| **o algoritmo** | equações normais (`XᵗX`) ou decomposição QR |
| **a biblioteca** | cada BLAS/LAPACK soma em ordem diferente, e usa blocos de tamanho diferente |
| **o nível de otimização** | `-O2` pode reassociar, vetorizar, ou usar fused multiply-add |

Então duas implementações **corretas** dão resultados que diferem nos últimos
dígitos. Comparar com `diff` reprovaria todas elas.

## O que este projeto faz

Compara **com tolerância declarada**, e a tolerância tem justificativa
numérica — não é um número escolhido até os testes passarem.

```
coeficiente   referência             obtido                |Δ|rel     tolerância
b0            8.80714285714278e-01   8.80714285714279e-01  1.3e-15   1e-10
b1            8.20714285714286e-01   8.20714285714286e-01  0.0e+00   1e-10
```

A tolerância é **relativa**, não absoluta, pelo motivo de sempre: um erro de
`1e-10` num coeficiente de valor 0,8 é desprezível; o mesmo erro num
coeficiente de valor `1e-12` é cem vezes o valor.

### De onde vem o `1e-10`, medido

O número de condição da matriz **é medido** pela referência, a partir dos
valores singulares da própria decomposição:

```
$ python3 python/referencia.py --condicao
bem: condicao(X)=2.249e+01  condicao(XtX)~=5.056e+02  k*eps=5.0e-15
mal: condicao(X)=7.438e+09  condicao(XtX)~=5.533e+19  k*eps=1.7e-06
```

A regra da análise numérica é que o erro relativo no resultado é, no pior
caso, da ordem de `κ · ε`, com `ε ≈ 2.2e-16` em 64 bits. Para o caso
bem-condicionado isso dá **5,0e-15**, e a tolerância de `1e-10` é **cinco
ordens de grandeza mais folgada** — folga deliberada, que cobre o que a
análise não prevê: a ordem interna das somas de cada BLAS, o uso de `fma`, e o
arredondamento da formatação decimal.

Se uma implementação divergir **acima** de `1e-10` no caso bem-condicionado,
não é ruído de ponto flutuante: é bug. Essa é a propriedade que a tolerância
precisa ter para valer como teste.

## O caso mal-condicionado, e por que ele tem OUTRA tolerância

Um projeto que só comparasse o caso fácil não mostraria nada. O segundo
conjunto de dados é construído para ser mal-condicionado: `x2 ≈ x1 × 1000`,
com um desvio de `0,001` que alterna de sinal.

O desvio não é zero de propósito. Colinearidade **perfeita** torna a matriz
singular, o problema deixa de ter solução única, e toda biblioteca detecta e
avisa — caso fácil. O caso difícil é o **quase** singular, em que todas
devolvem um número e os números divergem.

E a medição mostra quão severo ele é:

```
κ(X)      = 7.44e+09
κ(XᵗX)   ≈ 5.53e+19      <- e 1/ε ≈ 4.50e+15
```

**`κ(XᵗX)` é quatro ordens de grandeza maior que `1/ε`.** Em palavras: a
matriz `XᵗX` é numericamente singular. Resolver o sistema por ela não é
resolver o problema com menos precisão — é resolver um problema diferente.

Isso acontece porque formar `XᵗX` **eleva o número de condição ao quadrado**.
A decomposição QR trabalha com `X` diretamente e não eleva. É por isso que
`lm()` em R, `statsmodels` em Python e o operador `\` do Octave usam QR ou
SVD, e não equações normais — e é por isso que este projeto implementa **as
duas** em Fortran e compara.

### A consequência para o teste: duas grandezas, duas tolerâncias

Com `κ · ε ≈ 1.7e-06`, exigir `1e-10` dos coeficientes neste caso seria exigir
precisão que o problema **não tem**. A primeira versão deste documento propôs
uma tolerância única, e a medição a invalidou.

O que se separa:

| grandeza | é bem determinada? | tolerância |
|---|---|---|
| `R²`, `sigma`, valores ajustados | **sim** — o espaço gerado pelas colunas é estável, mesmo quase colinear | `1e-10` nos dois casos |
| coeficientes individuais | **não**, no caso mal-condicionado | `1e-10` no caso bem, `1e-04` no mal |

E essa separação não é concessão: é o conteúdo estatístico da colinearidade.
Os dados do caso `mal` foram gerados de `y = 3 + 2·x1 + 0,001·x2`, e o ajuste
devolve:

```
b0 =  2.96     (verdadeiro: 3)
b1 = -1426.57  (verdadeiro: 2)
b2 =  1.43     (verdadeiro: 0.001)
```

Com `R² = 0,99998`. O modelo **prevê quase perfeitamente** e os coeficientes
**não têm significado individual** — porque `-1426·x1 + 1,43·x2` é
numericamente quase igual a `2·x1 + 0,001·x2` quando `x2 ≈ 1000·x1`.

> É a lição que todo curso de econometria ensina e que nenhum projeto de "N
> linguagens" costuma mostrar: **um `R²` alto não valida os coeficientes.**

A decomposição QR trabalha com `X` diretamente e **não** eleva o número de
condição ao quadrado. É por isso que `lm()` em R, `statsmodels` em Python e o
`\` do Octave usam QR ou SVD, e não as equações normais — e é por isso que
este projeto implementa **as duas** em Fortran e compara.

> O resultado que o projeto mede: **a diferença entre algoritmos é maior que a
> diferença entre linguagens.** Duas linguagens rodando QR concordam em 15
> dígitos; a mesma linguagem rodando equações normais no caso
> mal-condicionado perde 8.

Isso é o oposto do que um projeto de "N linguagens" costuma concluir, e é o
que faz a comparação valer a pena.

## A formatação também é uma decisão

Os números são impressos com **15 dígitos significativos**, em notação
científica, com `.` como separador decimal e sempre com sinal no expoente:

```
2.473684210526316e+00
```

Cada parte dessa escolha evita uma divergência que não é numérica:

* **15 dígitos**, e não 17: 17 é o mínimo para `round-trip` exato de um
  `double`, e expõe exatamente os bits que diferem entre implementações
  corretas. 15 é o máximo que todas garantem reproduzir;
* **notação científica**, porque `0.000513` e `5.13e-04` são o mesmo número
  com dois textos diferentes, e várias linguagens escolhem sozinhas qual usar
  dependendo da magnitude;
* **ponto decimal**, porque R, Octave e gretl respeitam a *locale* do sistema
  — e numa máquina com `LC_NUMERIC=pt_BR` eles imprimiriam `2,47`. Cada
  runner força `LC_ALL=C`;
* **sinal no expoente**, porque `e+00` e `e00` aparecem em implementações
  diferentes da mesma função `printf`.

Nenhuma dessas quatro coisas tem a ver com estatística, e todas as quatro
quebrariam a comparação.
