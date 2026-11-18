# datalab — o mesmo modelo, e o que o algoritmo custa

Uma regressão linear por mínimos quadrados, implementada em **Python, R,
Octave, Fortran, hansl e SQL** — sete implementações, porque o Fortran traz
duas — sobre o mesmo conjunto de dados, comparadas com **tolerância
justificada** em vez de `diff`.

> **Status:** 8 das 10 linguagens previstas, com **11 verificações** e **11
> implementações** (algumas linguagens entram com os dois algoritmos). Python,
> R, Octave (dialeto MATLAB), Fortran, hansl e SQL estão completos. Ver
> [Roadmap](#roadmap).

## O resultado, antes de tudo

```
=== caso bem-condicionado ===
implementação  algoritmo                     pior |Δ|rel   campo     ajuste
----------------------------------------------------------------------------
python         SVD (LAPACK gelsd)                0.0e+00   sigma    0.0e+00
R              QR (LINPACK dqrdc2)               1.2e-14      b0    6.8e-15
octave         QR (operador \)                   0.0e+00   sigma    0.0e+00
fortran-qr     QR Householder, à mão             5.7e-15   sigma    5.7e-15
hansl          gretl                             8.5e-15      b1    4.6e-15
fortran-nrm    equações normais + Gauss          1.5e-14      b1    3.5e-15
sql            equações normais + Cramer         2.1e-14      b1    1.2e-14

=== caso mal-condicionado ===
python         SVD (LAPACK gelsd)                0.0e+00   sigma    0.0e+00
octave         QR (operador \)                   1.8e-13   sigma    1.8e-13
hansl          gretl                             9.6e-11      b0    1.6e-11
R              QR (LINPACK dqrdc2)               1.4e-08      b1    3.6e-12
fortran-qr     QR Householder, à mão             1.4e-08      b1    1.2e-12
fortran-nrm    equações normais + Gauss          3.4e-03      b1    5.5e-09
sql            equações normais + Cramer         4.0e-01   sigma    4.0e-01
```

No caso bem-condicionado, **as sete concordam em 14 dígitos**. No
mal-condicionado, elas se separam em quatro faixas — e a ordem **não é por
linguagem, é por algoritmo**:

> **A diferença entre algoritmos é 13 ordens de grandeza maior que a diferença
> entre linguagens.** Duas linguagens rodando QR concordam em `1,4e-08`; a
> mesma linguagem — Fortran, mesmo compilador, mesmas flags — rodando equações
> normais em vez de QR erra `3,4e-03`.

Isso é o oposto do que um projeto de "N linguagens" costuma concluir, e é o
que faz a comparação valer a pena.

## Por que este projeto não compara byte a byte

Os outros deste portfólio comparam saídas **idênticas**: sete portes do
`p01-metal-vm` executam o mesmo bytecode, cinco linguagens do
`p14-first-code` produzem o mesmo traço de tartaruga.

Aqui isso é impossível, porque ponto flutuante de 64 bits **não é
associativo** — `(a+b)+c ≠ a+(b+c)` — e as implementações diferem na ordem das
operações. Duas implementações corretas divergem nos últimos dígitos.

A tolerância é derivada do **número de condição medido**, e o cálculo inteiro
está em **[TOLERANCIA.md](TOLERANCIA.md)**:

```
$ python3 python/referencia.py --condicao
bem: condicao(X)=2.249e+01  condicao(XtX)~=5.056e+02  k*eps=5.0e-15
mal: condicao(X)=7.438e+09  condicao(XtX)~=5.533e+19  k*eps=1.7e-06
```

E há um teste que **falha se o caso mal deixar de ser severo**:

```
  ok    o caso mal é severo: XᵗX é numericamente singular
        k(XtX)=5.53e+19 > 1/eps=4.50e+15
```

`κ(XᵗX)` é quatro ordens de grandeza maior que `1/ε`. A matriz `XᵗX` é
numericamente singular — resolver o sistema por ela não é resolver o problema
com menos precisão, é resolver um problema diferente.

## O Fortran implementa os dois algoritmos, à mão

Esta é a decisão que faz o experimento valer.

As outras implementações usam bibliotecas diferentes: numpy chama `gelsd`
(SVD), o R chama `dqrdc2` (QR com pivotamento), o Octave resolve com `\`.
Comparar as três mede **biblioteca contra biblioteca**, e a diferença se
confunde com a diferença de linguagem.

Em `fortran/modelo.f90` as duas rotinas estão no **mesmo arquivo**, compiladas
pelo **mesmo compilador** com as **mesmas flags**, rodando na **mesma
máquina**. A única variável que muda é o algoritmo. Sem LAPACK, sem BLAS — 80
linhas de álgebra à vista, porque um `call dgels(...)` esconderia exatamente o
que se quer mostrar.

Dois detalhes que a implementação à mão obriga a acertar:

**O sinal da reflexão de Householder.** `alpha = -sign(normx, R(k,k))` evita
cancelamento: somar valores de mesmo sinal nunca subtrai números próximos.
Escolher o outro sinal funciona em aritmética exata e perde dígitos em ponto
flutuante — é o erro clássico da rotina.

**O pivotamento nas equações normais.** Está lá de propósito: sem ele, parte
da perda seria da eliminação e não do `XᵗX`, e a comparação seria injusta.
Com ele, a eliminação está tão boa quanto dá, e o erro que sobra é atribuível
ao algoritmo que o projeto acusa.

## O Julia mostrou que "equações normais" não é uma categoria

A tese deste projeto é que **o algoritmo é a variável, não a linguagem**. O
Julia entrou com as duas famílias — o operador `\`, que despacha para QR com
pivotamento de colunas, e as equações normais com Cholesky, montadas à mão —
e o resultado refinou a tese.

No caso mal-condicionado (número de condição 7,4e+09), o erro relativo nos
coeficientes:

| implementação | fatoração | pior Δ relativo |
|---|---|---|
| octave | QR (operador `\`) | **1,8e-13** |
| hansl (gretl) | QR | 9,6e-11 |
| julia-qr | QR pivotada (`dgeqp3`) | 1,3e-08 |
| R | QR (LINPACK `dqrdc2`) | 1,4e-08 |
| fortran-qr | QR Householder, à mão | 1,4e-08 |
| **scala-qr** | **QR Householder, à mão (JVM)** | **1,4e-08** |
| | | |
| fortran-nrm | equações normais + **Gauss** | 3,4e-03 |
| **scala-nrm** | equações normais + **Gauss (JVM)** | **3,4e-03** |
| julia-nrm | equações normais + **Cholesky** | 2,4e-02 |
| sql | equações normais + **Cramer** | 4,0e-01 |

A linha horizontal é a fronteira entre as famílias, e ela **separa cinco ordens
de grandeza** — que é o ponto que o projeto já fazia.

O que o Julia acrescentou é a leitura da metade de baixo: **as três
implementações de equações normais erram por uma ordem de grandeza de
diferença entre si.** Gauss, Cholesky e Cramer resolvem o *mesmo* sistema
`(XᵗX)β = Xᵗy`, e o quanto cada uma perde depende da fatoração.

Então "não use equações normais" é um conselho incompleto. O conselho completo
é: **elevar o número de condição ao quadrado é o erro principal, e qual
fatoração se usa depois ainda muda o resultado por 100×.**

### E o Scala fechou o experimento pela outra ponta

> Nota de contagem: o Scala **não acrescenta** uma linguagem nova ao
> portfólio — ele já aparecia no `p03-otp-mesh`. O `registro.lua` do
> `p12-toolbelt` desduplica, e foi ele que me corrigiu quando eu já havia
> escrito "67 linguagens" no índice. Aqui o Scala entra pelo que ele
> **mede**, não pelo que ele soma.



As duas linhas em negrito são o controle que faltava. O `scala/modelo.scala`
implementa **os mesmos dois algoritmos** que o `fortran/modelo.f90` — QR de
Householder e equações normais com eliminação de Gauss e pivotamento parcial —
escritos independentemente, numa linguagem diferente, rodando numa máquina
virtual em vez de código nativo.

E os números batem:

| algoritmo | Fortran (nativo) | Scala (JVM) |
|---|---|---|
| QR Householder | 1,4e-08 | **1,4e-08** |
| eq. normais + Gauss | 3,4e-03 | **3,4e-03** |

Até a coluna de ajuste bate: 5,5e-09 nos dois, para as equações normais.

Com isso a tese está demonstrada **nas duas direções**:

* **mesmo algoritmo, linguagens diferentes → mesmo erro.** Fortran nativo e
  Scala na JVM, dois autores de código distintos (eu, em dois dias
  diferentes), e o resultado é indistinguível na precisão que importa;
* **mesma família, fatorações diferentes → erros a 100× de distância.**
  Gauss, Cholesky e Cramer resolvem o mesmo sistema e perdem quantidades
  diferentes de dígitos.

O que **não** explica a divergência, portanto: a linguagem, o compilador, a
máquina virtual, o sistema de tipos. O que explica: **a sequência de operações
aritméticas que o algoritmo escolhe.**

E a metade de cima também tem leitura: o `\` do Octave fica em 1,8e-13,
cinco ordens melhor que o `\` do Julia e o QR do R, que são 1,3e-08. Os três
são "QR". Nenhum dos três está errado — o limite teórico do problema é
`k·eps ≈ 1,7e-06`, e todos estão bem abaixo dele.

## Uma verificação que o Julia me obrigou a escrever

Para classificar as duas novas implementações, o `verifica.sh` tem dois
conjuntos:

```python
QR_SVD  = {"python", "R", "octave", "fortran-qr", "hansl", "julia-qr"}
NORMAIS = {"fortran-nrm", "sql", "julia-nrm"}
```

E as checagens do caso `mal` **iteram sobre esses conjuntos**. Uma
implementação que não esteja em nenhum dos dois não é verificada ali — e a
suíte passa verde, porque nada reclamava de um conjunto incompleto.

Era exatamente o risco de acrescentar o Julia: registrá-lo no `compara.py` e
esquecer aqui daria dois números bonitos na tabela e **zero verificação sobre
eles**.

Agora a suíte verifica a si mesma:

```
ok    as 9 implementações estão todas classificadas por família
```

E se eu tirar uma implementação de sua família, ela reprova — medido:

```
FALHA implementações sem família declarada: julia-nrm
      -- elas NÃO seriam verificadas no caso mal
```

É a mesma falha que este portfólio registrou onze vezes com outro nome: **o
instrumento que esconde o próprio sinal.** A diferença é que aqui ela está
fechada por construção, e não por lembrança.

## O achado que eu não previa: o SQL erra o ajuste em 40%

O SQL tem um papel especial aqui: **ele não tem escolha de algoritmo.**

Não existe decomposição QR em SQL. O que SQL faz é agregar — somas de
produtos — que é exatamente o que as equações normais pedem. Nove agregações
montam o sistema 3×3, e resolver um 3×3 em SQL se faz por **regra de Cramer**.

A previsão era que o SQL divergisse como o Fortran com equações normais. Ele
divergiu **duas ordens de grandeza pior**:

| | coeficientes | ajuste (`R²`, `sigma`) |
|---|---|---|
| Fortran, equações normais + Gauss | 3,4e-03 | 5,5e-09 |
| **SQL, equações normais + Cramer** | **4,0e-01** | **4,0e-01** |

O erro padrão residual reportado pelo SQL é `7,458e-02` contra `5,325e-02` da
referência: **40% de erro numa estatística de qualidade de ajuste.**

E a parte que importa:

> **Nem o R nem o Octave emitem aviso algum** no caso mal-condicionado — foi
> medido. Eles devolvem números sem ressalva. No SQL, nada na saída diz que o
> `sigma` está 40% errado.

Toda vez que alguém escreve regressão em SQL puro — e isso acontece em
relatório de banco, em *dashboard*, em ETL — está usando equações normais sem
saber. Com dados bem-condicionados funciona. Com preditores correlacionados,
que é o caso comum em dados reais, o resultado pode estar errado em dígitos
significativos, **e a ferramenta não avisa**.

## O que cada linguagem torna curto

A tabela que explica por que são seis e não uma:

| linguagem | o OLS, nela | o que a linguagem oferece |
|---|---|---|
| **R** | `lm(y ~ x1 + x2, data = d)` | `~` é **operador da linguagem**, e a fórmula é objeto de primeira classe — guardável em variável, passável a função |
| **Octave** | `b = X \ y` | a barra invertida não é divisão: é "resolva o sistema", e para matriz retangular resolve por mínimos quadrados. **A álgebra linear é a sintaxe** |
| **hansl** | `ols y const x1 x2` | não há matriz, nem vetor, nem variável de resultado: o conjunto de dados está **sempre aberto** e os comandos operam sobre ele |
| **Python** | `np.linalg.lstsq(X, y)` | montagem explícita, e a biblioteca mais estável das três (SVD) |
| **Fortran** | 80 linhas | nada é escondido, e é de onde LAPACK e BLAS vieram |
| **SQL** | 9 agregações + Cramer | sem escolha de algoritmo — e o projeto mede o que isso custa |

## hansl, e por que não é Stata

O plano original pedia **Stata**. O Stata não tem edição gratuita, nem versão
de comunidade, nem trial aberto — e a regra declarada do portfólio é *nenhum
recurso pago*.

O `hansl` é a linguagem do **gretl** (GNU Regression, Econometrics and
Time-series Library), livre sob GPL e no apt. Ele cobre o **terreno** do
Stata: análise econométrica dirigida por comando, centrada num conjunto de
dados sempre aberto, com acessores de resultado implícitos (`$coeff`, `$rsq`).

**E não é Stata.** A sintaxe é outra (`ols y const x1 x2` contra `regress y x1
x2`), o acessor é outro (`$coeff` contra `_b[]`), e um `.do` não roda. Está
rotulado como hansl pelo mesmo motivo que a macro do `p12-toolbelt` está
rotulada como LibreOffice Basic e não como VBA.

### Duas coisas que o `gretlcli` faz diferente de todo o resto

**Ele tem diretório de trabalho próprio.** `open dados/bem.csv` não resolve
contra o diretório de onde o comando foi invocado — resolve contra o `workdir`
do gretl. O sintoma é cruel: o `open` falha, o `ols` seguinte não tem dados, e
o erro que aparece é sobre a estimação, não sobre o arquivo.

**E ele não recebe argumento de script.** `gretlcli -b arquivo` não tem como
passar parâmetro, então o caso vem por variável de ambiente.

## A formatação é uma decisão, e quatro coisas quebrariam a comparação

Os números saem com 15 dígitos significativos, em notação científica, com
ponto decimal e sinal no expoente. Cada parte evita uma divergência que **não
é numérica**:

| decisão | o que ela evita |
|---|---|
| 15 dígitos, não 17 | 17 é o mínimo para *round-trip* de um `double`, e expõe os bits que diferem entre implementações corretas |
| notação científica | `0.000513` e `5.13e-04` são o mesmo número com dois textos, e cada linguagem escolhe sozinha |
| ponto decimal | R, Octave e gretl respeitam a *locale*: em `pt_BR` imprimiriam `2,47` |
| sinal no expoente | `e+00` e `e00` aparecem em implementações diferentes do mesmo `printf` |

E duas armadilhas concretas que apareceram:

* o `Sys.setlocale` do R **devolve** a locale escolhida, e o R imprime o valor
  de toda expressão de nível superior num script — então sem `invisible()` a
  saída ganhava uma linha `[1] "C"`;
* o Octave usa Qt, que emite um aviso de quatro linhas em `stderr` quando a
  locale não é UTF-8. `LC_ALL=C.UTF-8` mantém o ponto decimal e cala o aviso;
  `LC_ALL=C` não.

## Por que o Scala não usa Spark

O plano original dizia **"Scala/Spark"**. O `scala/modelo.scala` não tem
dependência nenhuma — o cabeçalho é só `//> using scala 3`, e a QR de
Householder está escrita à mão, em 40 linhas.

Spark resolveria isto com `LinearRegression` do MLlib, em três. E seria
**desonesto como medida**, por três motivos:

* **o algoritmo ficaria escondido.** O MLlib escolhe entre L-BFGS e as
  equações normais via Breeze/netlib dependendo de parâmetros e do número de
  colunas. A linha da tabela diria "Spark" sem dizer qual — e o algoritmo é
  justamente a variável que este projeto mede;

* **o conjunto tem 12 linhas.** Spark distribuiria 12 linhas por um executor,
  com serialização de milissegundos para uma conta de microssegundos. O número
  mediria a JVM subindo;

* **o MLlib regulariza** por padrão em algumas configurações (`regParam`), e um
  β diferente por regularização não é erro numérico — é outro modelo. A tabela
  reportaria como divergência algo que é uma escolha estatística.

Spark tem lugar neste portfólio onde ele faz sentido: volume e distribuição.
Aqui ele daria um número bonito sobre nada.

### E o que Scala tornou curto não foi a álgebra

Foi a **composição**. `zip`, `map` e `foldLeft` deixam o resíduo e as somas de
quadrados legíveis sem um índice solto:

```scala
val ajustado = x.map(linha => linha.zip(beta).map(_ * _).sum)
val residuo  = y.zip(ajustado).map((a, b) => a - b)
```

O custo está na outra ponta, e é o assunto da seção
[O que cada linguagem torna curto](#o-que-cada-linguagem-torna-curto): o Julia
resolve o mesmo problema com `X \ y` — **um caractere** — porque o operador
despacha para LAPACK. O Scala escolheu não ter isso, e pagou 40 linhas.

### Uma suspeita que eu tive e que a medição descartou

A primeira saída do Scala foi `b0=0.88071428571428000`, com três zeros no fim,
contra `b0=0.8807142857142839` do Julia. Suspeitei do `%.17g` do Java — que o
meu próprio comentário no arquivo avisa ser capaz de medir a formatação em vez
da aritmética.

Então medi, em vez de supor. Os três caminhos de formatação do Java, sobre o
**mesmo** double:

```
%.17g      -> 0.88071428571428390     volta exato? true
toString   -> 0.8807142857142839      volta exato? true
BigDecimal -> 0.88071428571428390     volta exato? true
```

O `%.17g` arredonda corretamente e **volta ao bit exato**. Os zeros não eram
formatação: o valor que o Scala calcula **é** outro `double`, a ~4e-15
relativo do de Julia — Householder à mão contra QR pivotada do LAPACK.

É o resultado que o projeto espera, e está escrito aqui porque a suspeita era
razoável e descartá-la exigiu evidência, não confiança.

## Rodando

```bash
sudo apt-get install -y python3-numpy r-base-core octave gfortran gretl sqlite3
./verifica.sh
```

A suíte **pula** o que não está instalado, e `P05_EXIGE=1` transforma todo
"pulado" em falha — que é o que o CI liga.

```
  ok    caso bem: 7 implementações dentro de 1e-10 (pior 2.1e-14, em sql)
  ok    caso mal: a família QR/SVD fica dentro de 1e-06 (pior 1.4e-08)
  ok    caso mal: fortran-nrm perde dígitos como previsto (3.4e-03 ≥ 1e-04)
  ok    caso mal: no SQL até o AJUSTE erra 4.0e-01 -- e nada na saída avisa
  11 passaram, 0 falharam
```

Note o terceiro: a suíte **exige que algumas implementações divirjam**. Se uma
delas passasse a concordar no caso mal-condicionado, a tese do projeto estaria
errada — e esse teste é que avisaria.

### E o projeto ensinou a própria lição ao seu autor

O teste *"a referência gravada está em dia?"* comparava o JSON do instantâneo
com o recalculado **como texto**. Passou aqui e **falhou no CI**.

A causa é exatamente o assunto do projeto: o LAPACK do runner do GitHub não é
o mesmo build do desta máquina, e a SVD devolve bits diferentes nos últimos
dígitos. O arquivo gravado é um instantâneo de ponto flutuante, e exigir
igualdade textual dele é o mesmo erro que exigir `diff` entre as
implementações.

A disciplina de tolerância valia para as sete implementações e não para o
instantâneo — que é produzido pela mesma aritmética. Hoje ele também é
comparado com `1e-10`, e o teste distingue as duas causas possíveis: acima da
tolerância, os dados ou o modelo mudaram; abaixo, é a mesma diferença de BLAS
que o projeto existe para medir.

## Roadmap

| linguagem | o que mostra | situação |
|---|---|---|
| **Python** | a referência, por SVD | ✅ feito |
| **R** | a fórmula como objeto de primeira classe | ✅ feito |
| **Octave** | álgebra linear como sintaxe | ✅ feito |
| **Fortran** | **os dois algoritmos**, à mão, no mesmo arquivo | ✅ feito |
| **hansl** | econometria dirigida por comando (no lugar do Stata) | ✅ feito |
| **SQL** | o que custa não ter escolha de algoritmo | ✅ feito |
| **Julia** | que **qual fatoração** se usa muda o erro por 100×, dentro da mesma família | ✅ feito |
| **Scala** | álgebra linear **sem biblioteca**, e por que Spark seria desonesto aqui | ✅ feito |
| **Mojo** | a promessa de "Python com desempenho de C" | a fazer — SDK da Modular |
| **Wolfram** | solução simbólica, e não numérica — o único que pode dar a resposta exata | a fazer — Wolfram Engine, livre para desenvolvedor |
| **SAS** | o dialeto de `PROC` que ainda roda a indústria farmacêutica e bancária | a fazer — SAS OnDemand, nuvem com cadastro gratuito |
| ~~Stata~~ | — | **substituído por hansl**, ver acima |

O **Wolfram** é o mais interessante do que falta: ele pode resolver o sistema
**simbolicamente** e dar os coeficientes como frações exatas, o que torna o
caso mal-condicionado trivial — e expõe que o problema inteiro deste projeto é
de aritmética de máquina, não de matemática.

## Licença

MIT, em `LICENSE`.
