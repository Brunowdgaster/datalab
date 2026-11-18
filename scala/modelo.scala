//> using scala 3
//
// modelo.scala — mínimos quadrados em Scala 3, pelos DOIS algoritmos.
//
//     scala-cli run scala/modelo.scala -- bem
//     scala-cli run scala/modelo.scala -- bem normal
//
// ## Por que SEM biblioteca, e o que isso custa
//
// Não há Breeze, não há Spark, não há dependência nenhuma — o cabeçalho
// `//> using scala 3` é a declaração inteira. A álgebra linear está escrita
// aqui, à mão.
//
// Isso é uma **escolha**, e o preço aparece na contagem de linhas: o Julia
// resolve mínimos quadrados em `X \ y`, um caractere. Aqui são 40 linhas de
// Householder. O projeto mede exatamente isso — "o que cada linguagem torna
// curto" é uma seção do README.
//
// O que a escolha compra é que a comparação mede **a aritmética de ponto
// flutuante da JVM**, e não a de uma biblioteca nativa que o Breeze chamaria
// via netlib. Com Breeze, duas implementações "em Scala" poderiam divergir
// por qual BLAS o sistema tem instalado — e esse já é o assunto de outras
// linhas da tabela.
//
// ## E por que não Spark
//
// O plano original dizia "Scala/Spark". Spark resolveria isto com
// `LinearRegression` do MLlib, em três linhas — e seria **desonesto** como
// medida:
//
//   * o MLlib usa L-BFGS ou as equações normais via Breeze/netlib, e qual
//     dos dois depende de parâmetros e do número de colunas. Então a linha
//     da tabela diria "Spark" sem dizer o algoritmo, que é a variável que
//     este projeto mede;
//   * o conjunto tem **12 linhas**. Spark distribuiria 12 linhas por um
//     executor, com overhead de serialização de milissegundos para uma conta
//     de microssegundos. O número mediria a JVM subindo, não a aritmética;
//   * e o MLlib **regulariza por padrão** em algumas versões (`regParam`),
//     o que mudaria os coeficientes de propósito — e um β diferente por
//     regularização não é erro numérico, é outro modelo.
//
// Spark entra no portfólio onde ele tem sentido: volume e distribuição. Aqui
// ele daria um número bonito sobre nada.
//
// ## O que Scala torna curto, de verdade
//
// Não é a álgebra linear. É a **composição**: `zip`, `map`, `foldLeft` e os
// `for` com guarda deixam a QR de Householder legível sem índices soltos, e
// o sistema de tipos garante que `Matriz` e `Vetor` não se misturem. O
// `opaque type` abaixo é a parte mais idiomática deste arquivo.

import scala.io.Source
import scala.math.{abs, sqrt}

type Vetor = Array[Double]
type Matriz = Array[Array[Double]]

@main def main(args: String*): Unit =
  if args.isEmpty then
    Console.err.println("uso: modelo.scala <bem|mal> [normal]")
    sys.exit(64)

  val caso = args(0)
  val algoritmo = if args.length > 1 then args(1) else "qr"

  val (x, y) = carrega(caso)
  val n = x.length
  val p = x.head.length

  val beta =
    if algoritmo == "normal" then ajustaNormal(x, y)
    else ajustaQR(x, y)

  // O resíduo e as somas de quadrados.
  //
  // `zip` em vez de índice: o comprimento é garantido pelo tipo da tupla
  // resultante, e um `y` com uma linha a mais que `x` produziria um zip mais
  // curto em vez de uma exceção de índice -- o que seria PIOR. Por isso o
  // `require` explícito em `carrega`.
  val ajustado = x.map(linha => linha.zip(beta).map(_ * _).sum)
  val residuo = y.zip(ajustado).map((a, b) => a - b)

  val sqe = residuo.map(r => r * r).sum
  val media = y.sum / n
  val sqt = y.map(v => (v - media) * (v - media)).sum
  val gl = n - p

  val r2 = 1.0 - sqe / sqt
  val sigma = sqrt(sqe / gl)

  // `%.17g` e não `%.15f`: dezessete dígitos significativos é o que garante
  // ida-e-volta exata de um Double em decimal. Com menos, a comparação
  // mediria a minha formatação em vez da aritmética da JVM.
  //
  // E `Locale.ROOT` é obrigatório: num sistema com locale pt_BR, o `%g` do
  // Java escreve `0,88` com VÍRGULA, e o `compara.py` leria isso como erro de
  // valor ilegível -- um defeito de ambiente aparecendo como defeito
  // numérico. O projeto já tem essa correção em R e Octave, por LC_ALL.
  val l = java.util.Locale.ROOT
  println(String.format(l, "b0=%.17g", beta(0)))
  println(String.format(l, "b1=%.17g", beta(1)))
  println(String.format(l, "b2=%.17g", beta(2)))
  println(String.format(l, "r2=%.17g", r2))
  println(String.format(l, "sigma=%.17g", sigma))
  println(s"gl=$gl")

/** Lê `dados/<caso>.csv` e monta a matriz de desenho `[1 x1 x2]`.
  *
  * A coluna de 1s vem primeiro, na mesma ordem das outras implementações,
  * porque `b0`, `b1` e `b2` são comparados por POSIÇÃO: colunas trocadas
  * dariam coeficientes certos em lugares errados, e o comparador reportaria
  * divergência numérica onde o erro é de layout.
  */
def carrega(caso: String): (Matriz, Vetor) =
  val raiz = java.nio.file.Paths.get(".").toAbsolutePath.normalize
  val caminho = raiz.resolve(s"dados/$caso.csv")

  val linhas = Source.fromFile(caminho.toFile).getLines().toList
  val corpo = linhas.tail.filter(_.trim.nonEmpty) // descarta o cabeçalho

  val campos = corpo.map(_.split(",").map(_.trim.toDouble))
  require(campos.forall(_.length == 3),
    s"esperava 3 colunas por linha em $caminho")

  val x = campos.map(c => Array(1.0, c(0), c(1))).toArray
  val y = campos.map(_(2)).toArray
  (x, y)

/** QR por reflexões de Householder, e resolução por substituição regressiva.
  *
  * É o mesmo algoritmo que `fortran/modelo.f90` implementa à mão, e os dois
  * devem concordar bem -- o que torna esta linha da tabela um CONTROLE: se o
  * Scala divergir do Fortran usando o mesmo algoritmo, o problema está numa
  * das duas implementações, e não na aritmética.
  *
  * Householder e não Gram-Schmidt porque Gram-Schmidt clássico perde
  * ortogonalidade em problemas mal-condicionados -- e o caso `mal` tem
  * condição 7,4e+09, exatamente onde isso aparece.
  */
def ajustaQR(x0: Matriz, y0: Vetor): Vetor =
  val n = x0.length
  val p = x0.head.length

  // Cópias: o algoritmo é destrutivo, e receber a matriz do chamador e
  // devolvê-la modificada é o tipo de surpresa que faz a SEGUNDA chamada
  // dar outro resultado.
  val a = x0.map(_.clone)
  val b = y0.clone

  for k <- 0 until p do
    // A norma da coluna abaixo da diagonal.
    var norma = 0.0
    for i <- k until n do norma += a(i)(k) * a(i)(k)
    norma = sqrt(norma)

    if norma > 0.0 then
      // O sinal é escolhido para EVITAR cancelamento: se a(k)(k) é positivo,
      // somar uma norma positiva aumenta a magnitude em vez de subtrair dois
      // números próximos. É a diferença entre Householder estável e
      // Householder que perde dígitos no primeiro passo.
      val alfa = if a(k)(k) > 0 then -norma else norma

      val v = Array.fill(n)(0.0)
      for i <- k until n do v(i) = a(i)(k)
      v(k) -= alfa

      var vtv = 0.0
      for i <- k until n do vtv += v(i) * v(i)

      if vtv > 0.0 then
        // Aplica a reflexão nas colunas restantes e no lado direito.
        for j <- k until p do
          var vta = 0.0
          for i <- k until n do vta += v(i) * a(i)(j)
          val fator = 2.0 * vta / vtv
          for i <- k until n do a(i)(j) -= fator * v(i)

        var vtb = 0.0
        for i <- k until n do vtb += v(i) * b(i)
        val fator = 2.0 * vtb / vtv
        for i <- k until n do b(i) -= fator * v(i)

  // Substituição regressiva no sistema triangular superior.
  val beta = Array.fill(p)(0.0)
  for i <- (p - 1) to 0 by -1 do
    var soma = b(i)
    for j <- (i + 1) until p do soma -= a(i)(j) * beta(j)
    beta(i) = soma / a(i)(i)
  beta

/** As equações normais: resolve `(XᵗX) β = Xᵗy` por eliminação de Gauss com
  * pivotamento parcial.
  *
  * Este caminho existe para **divergir**, não para concordar. Ele eleva o
  * número de condição ao quadrado, e no caso `mal` -- condição 7,4e+09 --
  * isso significa perder cerca de metade dos dígitos de um Double.
  *
  * A fatoração é a MESMA do `fortran-nrm` (Gauss com pivotamento), de
  * propósito: assim a tabela tem duas implementações de equações normais com
  * a mesma fatoração em linguagens diferentes, e três fatorações diferentes
  * no total (Gauss, Cholesky no Julia, Cramer no SQL). O que isso revela está
  * no README -- as três erram por uma ordem de grandeza de diferença entre
  * si.
  */
def ajustaNormal(x: Matriz, y: Vetor): Vetor =
  val n = x.length
  val p = x.head.length

  // XᵗX e Xᵗy, montados explicitamente. É aqui que a condição é elevada ao
  // quadrado, e nada na aritmética avisa.
  val xtx = Array.tabulate(p, p) { (i, j) =>
    var s = 0.0
    for k <- 0 until n do s += x(k)(i) * x(k)(j)
    s
  }
  val xty = Array.tabulate(p) { i =>
    var s = 0.0
    for k <- 0 until n do s += x(k)(i) * y(k)
    s
  }

  // Matriz aumentada [XᵗX | Xᵗy].
  val m = Array.tabulate(p, p + 1)((i, j) => if j < p then xtx(i)(j) else xty(i))

  for col <- 0 until p do
    // Pivotamento parcial: troca pela linha de maior magnitude.
    //
    // Sem isso, um pivô pequeno divide e amplifica o erro -- e em XᵗX, que já
    // está mal-condicionada, o pivô pequeno é o caso comum, não a exceção.
    var maior = col
    for i <- (col + 1) until p do
      if abs(m(i)(col)) > abs(m(maior)(col)) then maior = i
    if maior != col then
      val t = m(col); m(col) = m(maior); m(maior) = t

    val pivo = m(col)(col)
    for i <- (col + 1) until p do
      val fator = m(i)(col) / pivo
      for j <- col to p do m(i)(j) -= fator * m(col)(j)

  val beta = Array.fill(p)(0.0)
  for i <- (p - 1) to 0 by -1 do
    var soma = m(i)(p)
    for j <- (i + 1) until p do soma -= m(i)(j) * beta(j)
    beta(i) = soma / m(i)(i)
  beta
