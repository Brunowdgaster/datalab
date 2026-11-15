#!/usr/bin/env Rscript
# modelo.R — o mesmo OLS, em R.
#
#     Rscript r/modelo.R bem
#
# ## Por que o R está aqui, e por que ele é a referência NATURAL deste domínio
#
# O R não é uma linguagem de propósito geral com biblioteca de estatística: é
# uma linguagem *projetada* para análise de dados, e isso aparece no que ela
# torna curto.
#
# A regressão deste projeto, em R, é UMA linha:
#
#     lm(y ~ x1 + x2, data = d)
#
# O `~` é um operador da linguagem, e `y ~ x1 + x2` é um objeto de primeira
# classe -- uma FÓRMULA, que se pode guardar em variável, passar a função e
# manipular. Em Python o equivalente é uma string que o `patsy` analisa; em
# Octave e Fortran não existe equivalente, e a matriz é montada à mão.
#
# Essa é a diferença que o projeto mede: as outras implementações precisam
# construir a matriz de desenho, e o R a deriva da notação matemática do
# modelo.
#
# ## O que o `lm` usa por baixo
#
# Decomposição QR com pivotamento (a rotina `dqrdc2` do LINPACK, adaptada
# pelos autores do R). NÃO equações normais -- e é por isso que ele sobrevive
# ao caso mal-condicionado, que está documentado em TOLERANCIA.md.

# `LC_ALL=C` no ambiente é o que garante PONTO decimal. Sem isso, numa máquina
# em pt_BR o R imprimiria `0,88` e a comparação com as outras implementações
# falharia por formatação -- não por aritmética.
#
# O runner exporta a variável; esta linha é a segunda defesa, porque depender
# só do ambiente é depender de quem invoca.
#  porque  DEVOLVE a locale escolhida, e o R imprime
# o valor de toda expressao de nivel superior num script -- entao sem ele a
# saida ganha uma linha `[1] "C"` que nao e dado, e a comparacao falha.
invisible(Sys.setlocale("LC_NUMERIC", "C"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1 || !(args[1] %in% c("bem", "mal"))) {
  cat("uso: modelo.R {bem|mal}\n", file = stderr())
  quit(status = 64)
}

caso <- args[1]
raiz <- dirname(dirname(normalizePath(sub("^--file=", "", grep("^--file=",
  commandArgs(trailingOnly = FALSE), value = TRUE)[1]))))

d <- read.csv(file.path(raiz, "dados", paste0(caso, ".csv")))

ajuste <- lm(y ~ x1 + x2, data = d)
s <- summary(ajuste)

# `coef` sai com nome; `unname` tira, porque o formato de saída é posicional.
b <- unname(coef(ajuste))

# 15 dígitos significativos, científico, como TOLERANCIA.md exige.
#
# `formatC` e não `sprintf`: o `sprintf` do R respeita a locale em algumas
# plataformas, e o `formatC` com `format="e"` é consistente. A diferença só
# aparece numa máquina não-C, que é exatamente onde ninguém testa.
fmt <- function(x) formatC(x, format = "e", digits = 14)

for (i in seq_along(b)) cat(sprintf("b%d=%s\n", i - 1L, fmt(b[i])))
cat(sprintf("r2=%s\n", fmt(s$r.squared)))
cat(sprintf("sigma=%s\n", fmt(s$sigma)))
cat(sprintf("gl=%d\n", ajuste$df.residual))
