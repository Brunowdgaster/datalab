-- modelo.sql — o mesmo OLS, em SQL ANSI, e o que isso custa.
--
--     sqlite3 :memory: < sql/carrega.sql < sql/modelo.sql
--
-- ## O papel do SQL neste projeto não é ser mais uma linguagem
--
-- É ser a que **não tem escolha de algoritmo**.
--
-- SQL agrega: ele soma, conta e multiplica colunas. Não há decomposição QR em
-- SQL, não há SVD, não há reflexão de Householder — nada que trabalhe com a
-- matriz `X` inteira de uma vez. O que SQL faz bem é exatamente o que as
-- equações normais pedem: somas de produtos.
--
--     Σ1, Σx1, Σx2, Σx1², Σx2², Σx1x2, Σy, Σx1y, Σx2y
--
-- Nove agregações, e o sistema 3×3 está montado. Depois é resolver.
--
-- E resolver um sistema 3×3 em SQL se faz por **regra de Cramer**: três
-- determinantes divididos pelo determinante da matriz. É fechado, é exato em
-- aritmética exata, e é numericamente o pior dos mundos — porque já parte do
-- `XᵗX`, cujo número de condição é o quadrado do original.
--
-- ## A previsão, antes de medir
--
-- `TOLERANCIA.md` mede `κ(XᵗX) ≈ 5,5e+19` para o caso mal-condicionado, e
-- `1/ε ≈ 4,5e+15`. Então a previsão é:
--
--   * caso BEM-condicionado: o SQL concorda com todos os outros;
--   * caso MAL-condicionado: o SQL **diverge**, e deve divergir de forma
--     parecida com as equações normais em Fortran — porque é o mesmo
--     algoritmo.
--
-- A suíte **testa a previsão**, e não a esconde. Se o SQL passasse a
-- concordar no caso mal-condicionado, a tese do projeto estaria errada e esse
-- teste é que avisaria.
--
-- ## Por que isto não é um defeito do SQL
--
-- É um limite do modelo, e vale conhecê-lo: toda vez que alguém escreve
-- regressão em SQL puro — e isso acontece em relatório de banco de dados,
-- em dashboard, em ETL — está usando equações normais sem saber. Com dados
-- bem-condicionados funciona; com preditores correlacionados, que é o caso
-- comum em dados reais, os coeficientes podem estar errados em dígitos
-- significativos.
--
-- Roda sem alteração em SQLite e em PostgreSQL. `CAST(... AS REAL)` em vez de
-- `::float8` por isso.

WITH somas AS (
    SELECT
        CAST(COUNT(*)        AS REAL) AS s0,
        CAST(SUM(x1)         AS REAL) AS s1,
        CAST(SUM(x2)         AS REAL) AS s2,
        CAST(SUM(x1 * x1)    AS REAL) AS s11,
        CAST(SUM(x1 * x2)    AS REAL) AS s12,
        CAST(SUM(x2 * x2)    AS REAL) AS s22,
        CAST(SUM(y)          AS REAL) AS t0,
        CAST(SUM(x1 * y)     AS REAL) AS t1,
        CAST(SUM(x2 * y)     AS REAL) AS t2,
        CAST(SUM(y * y)      AS REAL) AS tyy
    FROM obs
),

-- A matriz XᵗX, por extenso. É simétrica, e escrever as nove posições em vez
-- de seis deixa a regra de Cramer legível abaixo.
--
--     | a11 a12 a13 |     | b1 |
--     | a21 a22 a23 | b = | b2 |
--     | a31 a32 a33 |     | b3 |
sistema AS (
    SELECT
        s0  AS a11, s1  AS a12, s2  AS a13,
        s1  AS a21, s11 AS a22, s12 AS a23,
        s2  AS a31, s12 AS a32, s22 AS a33,
        t0  AS b1,  t1  AS b2,  t2  AS b3,
        s0, t0, tyy
    FROM somas
),

-- Os determinantes de Cramer.
--
-- `det` é o da matriz; `d0`, `d1`, `d2` substituem a coluna correspondente
-- pelo lado direito. Cada um é a expansão 3×3 completa -- seis produtos de
-- três fatores.
--
-- E aqui está o custo numérico à vista: cada determinante soma seis produtos
-- que, no caso mal-condicionado, têm magnitudes muito diferentes e sinais
-- opostos. É cancelamento catastrófico escrito em SQL.
determinantes AS (
    SELECT
        a11 * (a22 * a33 - a23 * a32)
      - a12 * (a21 * a33 - a23 * a31)
      + a13 * (a21 * a32 - a22 * a31) AS det,

        b1  * (a22 * a33 - a23 * a32)
      - a12 * (b2  * a33 - a23 * b3)
      + a13 * (b2  * a32 - a22 * b3)  AS d0,

        a11 * (b2  * a33 - a23 * b3)
      - b1  * (a21 * a33 - a23 * a31)
      + a13 * (a21 * b3  - b2  * a31) AS d1,

        a11 * (a22 * b3  - b2  * a32)
      - a12 * (a21 * b3  - b2  * a31)
      + b1  * (a21 * a32 - a22 * a31) AS d2,

        s0, t0, tyy
    FROM sistema
),

coeficientes AS (
    SELECT
        d0 / det AS b0,
        d1 / det AS b1,
        d2 / det AS b2,
        s0, t0, tyy
    FROM determinantes
),

-- R² e sigma pedem a soma dos quadrados dos resíduos, que precisa dos
-- coeficientes -- então é uma segunda passagem pelos dados.
--
-- Em Python, R, Octave e Fortran isso é `y - X*b` num vetor. Aqui é um JOIN
-- do conjunto de observações com a linha única de coeficientes: a diferença
-- entre uma linguagem de vetores e uma de relações, no mesmo cálculo.
ajuste AS (
    SELECT
        c.b0, c.b1, c.b2, c.s0,
        SUM((o.y - (c.b0 + c.b1 * o.x1 + c.b2 * o.x2))
          * (o.y - (c.b0 + c.b1 * o.x1 + c.b2 * o.x2))) AS sse,
        SUM((o.y - c.t0 / c.s0) * (o.y - c.t0 / c.s0))   AS sst
    FROM obs o
    CROSS JOIN coeficientes c
    GROUP BY c.b0, c.b1, c.b2, c.s0, c.t0
)

-- A saída no formato de TOLERANCIA.md.
--
-- `printf('%.14e', x)` existe no SQLite; no PostgreSQL o equivalente é
-- `to_char`. Esta é a ÚNICA linha deste arquivo que não é ANSI, e ela está
-- isolada no fim de propósito: a álgebra toda acima roda nos dois motores
-- sem alteração, e só a formatação divergiu.
SELECT 'b0=' || printf('%.14e', b0) FROM ajuste
UNION ALL SELECT 'b1=' || printf('%.14e', b1) FROM ajuste
UNION ALL SELECT 'b2=' || printf('%.14e', b2) FROM ajuste
UNION ALL SELECT 'r2=' || printf('%.14e', 1.0 - sse / sst) FROM ajuste
UNION ALL SELECT 'sigma=' || printf('%.14e', sqrt(sse / (s0 - 3.0))) FROM ajuste
UNION ALL SELECT 'gl=' || CAST(CAST(s0 - 3.0 AS INTEGER) AS TEXT) FROM ajuste;
