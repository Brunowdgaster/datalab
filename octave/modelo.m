#!/usr/bin/env octave
% modelo.m — o mesmo OLS, em Octave (dialeto MATLAB).
%
%     octave --no-gui --quiet octave/modelo.m bem
%
% ## Por que Octave, e não MATLAB
%
% O MATLAB é pago. O Octave é livre (GPL) e implementa a mesma linguagem --
% suficientemente que este arquivo roda nos dois sem alteração.
%
% A ressalva honesta: "dialeto MATLAB" não é "MATLAB". Octave aceita
% extensões que o MATLAB recusa (`#` como comentário, `++`, `endfunction`), e
% este arquivo **evita todas elas** de propósito: usa `%` para comentário,
% `end` para fechar bloco, e nada fora do núcleo comum. É o que torna a
% afirmação verificável em vez de otimista.
%
% ## O que a linguagem torna curto
%
% O OLS em Octave é um OPERADOR:
%
%     b = X \ y
%
% A barra invertida não é divisão: é "resolva o sistema", e para matriz
% retangular o Octave resolve por **mínimos quadrados via QR** -- a decisão
% numérica certa, embutida na sintaxe.
%
% Isso é diferente do R, onde `lm` é uma função com fórmula, e do Fortran,
% onde é uma chamada explícita a LAPACK. Aqui a álgebra linear É a linguagem,
% e esse era o argumento do MATLAB desde 1984.

args = argv();
if numel(args) != 1 || !any(strcmp(args{1}, {'bem', 'mal'}))
  fprintf(stderr, 'uso: modelo.m {bem|mal}\n');
  exit(64);
end

caso = args{1};

% O diretório do script, para o caminho dos dados não depender de onde o
% comando foi invocado.
[dir_script, ~, ~] = fileparts(mfilename('fullpath'));
raiz = fileparts(dir_script);

arquivo = fullfile(raiz, 'dados', [caso '.csv']);

% `dlmread` com offset 1 pula o cabeçalho. `csvread` seria mais curto e está
% obsoleto no Octave 9+, e usar função obsoleta num projeto que afirma
% portabilidade seria contraditório.
M = dlmread(arquivo, ',', 1, 0);

x1 = M(:, 1);
x2 = M(:, 2);
y  = M(:, 3);

n = numel(y);
X = [ones(n, 1), x1, x2];

% A resolução por mínimos quadrados. Uma linha, e por QR.
b = X \ y;

p = columns(X);
gl = n - p;

resid = y - X * b;
sse = resid' * resid;
sst = sum((y - mean(y)) .^ 2);

r2 = 1 - sse / sst;
sigma = sqrt(sse / gl);

% O formato de TOLERANCIA.md: 15 dígitos, científico.
%
% `%.14e` no Octave já usa ponto decimal independentemente da locale, porque
% ele não aplica locale a `printf` -- diferente do R. Mas o runner força
% `LC_ALL=C` de todo jeito, porque depender disso seria depender de um detalhe
% de implementação não documentado.
for i = 1:p
  printf('b%d=%.14e\n', i - 1, b(i));
end
printf('r2=%.14e\n', r2);
printf('sigma=%.14e\n', sigma);
printf('gl=%d\n', gl);
