! modelo.f90 — o mesmo OLS, em Fortran, pelos DOIS algoritmos.
!
!     gfortran -O2 -std=f2008 -o fortran/modelo fortran/modelo.f90
!     ./fortran/modelo bem normal
!     ./fortran/modelo bem qr
!
! ## Por que o Fortran está neste projeto
!
! Porque ele é de onde a álgebra linear numérica vem. O LAPACK é escrito em
! Fortran; o BLAS é escrito em Fortran; o `lm` do R chama LINPACK em Fortran;
! o `numpy.linalg` chama LAPACK em Fortran. Quando este projeto compara
! implementações, **três delas estão chamando Fortran por baixo** -- e esta é
! a que não chama ninguém.
!
! ## E por que ele implementa os dois algoritmos À MÃO
!
! Esta é a decisão central do projeto, e ela faz o experimento valer.
!
! As outras implementações usam bibliotecas diferentes: numpy chama `gelsd`
! (SVD), o R chama `dqrdc2` (QR com pivotamento), o Octave resolve com `\`
! (QR). Comparar as três mede **biblioteca contra biblioteca**, e a diferença
! de resultado se confunde com a diferença de linguagem.
!
! Aqui as duas rotinas estão no MESMO arquivo, compiladas pelo MESMO compilador
! com as MESMAS flags, rodando na MESMA máquina. A única variável que muda é o
! algoritmo. É um experimento controlado, e não uma comparação de produtos.
!
! Nenhuma biblioteca externa: nem LAPACK, nem BLAS. As ~80 linhas de álgebra
! abaixo são o que o projeto precisa, e tê-las à vista é o ponto -- um `call
! dgels(...)` esconderia exatamente o que se quer mostrar.
!
! ## O que se espera medir
!
!   * caso BEM-condicionado: os dois algoritmos concordam em ~14 dígitos, e os
!     dois concordam com a referência;
!
!   * caso MAL-condicionado: as equações normais perdem dígitos, porque formar
!     `XᵗX` eleva o número de condição ao quadrado -- e o quadrado medido
!     (5,5e+19) é maior que `1/ε` (4,5e+15), ou seja, `XᵗX` é numericamente
!     singular. Ver TOLERANCIA.md.

program modelo
    use, intrinsic :: iso_fortran_env, only: dp => real64, error_unit
    implicit none

    integer, parameter :: NOBS = 12
    integer, parameter :: NPAR = 3

    character(len=32) :: arg_caso, arg_metodo
    real(dp) :: X(NOBS, NPAR), y(NOBS), b(NPAR)
    real(dp) :: r2, sigma
    integer :: i, gl

    if (command_argument_count() /= 2) then
        write (error_unit, '(a)') 'uso: modelo {bem|mal} {normal|qr}'
        stop 64
    end if

    call get_command_argument(1, arg_caso)
    call get_command_argument(2, arg_metodo)

    call le_dados(trim(arg_caso), X, y)

    select case (trim(arg_metodo))
    case ('normal')
        call ols_equacoes_normais(X, y, b)
    case ('qr')
        call ols_householder_qr(X, y, b)
    case default
        write (error_unit, '(a)') 'método deve ser normal ou qr'
        stop 64
    end select

    call estatisticas(X, y, b, r2, sigma, gl)

    ! O formato de TOLERANCIA.md: 15 dígitos significativos, científico.
    !
    ! `es24.14e2` em vez de `e24.14`: o descritor `es` força UM dígito antes do
    ! ponto (notação científica de verdade), enquanto `e` do Fortran escreve
    ! `0.88071...E+00` -- com zero antes do ponto, que é uma convenção que
    ! nenhuma das outras linguagens usa. E `e2` fixa o expoente em dois
    ! dígitos, porque o padrão varia com a magnitude.
    do i = 1, NPAR
        write (*, '(a,i0,a,es24.14e2)') 'b', i - 1, '=', b(i)
    end do
    write (*, '(a,es24.14e2)') 'r2=', r2
    write (*, '(a,es24.14e2)') 'sigma=', sigma
    write (*, '(a,i0)') 'gl=', gl

contains

    subroutine le_dados(caso, X, y)
        character(len=*), intent(in) :: caso
        real(dp), intent(out) :: X(NOBS, NPAR), y(NOBS)

        character(len=256) :: caminho, linha
        integer :: u, io, i
        real(dp) :: x1, x2, yy

        caminho = 'dados/' // caso // '.csv'
        open (newunit=u, file=caminho, status='old', action='read', iostat=io)
        if (io /= 0) then
            write (error_unit, '(a,a)') 'não consegui abrir ', trim(caminho)
            stop 66
        end if

        ! Pula o cabeçalho.
        read (u, '(a)', iostat=io) linha

        do i = 1, NOBS
            read (u, '(a)', iostat=io) linha
            if (io /= 0) then
                write (error_unit, '(a,i0)') 'dados terminaram na linha ', i
                stop 65
            end if
            ! A vírgula do CSV vira espaço, e aí a leitura de lista do Fortran
            ! separa os campos. É o truque padrão para CSV em Fortran, que não
            ! tem leitor de CSV na biblioteca -- e é mais honesto que fingir
            ! que a linguagem tem.
            call troca(linha, ',', ' ')
            read (linha, *, iostat=io) x1, x2, yy
            if (io /= 0) then
                write (error_unit, '(a,i0)') 'linha ilegível: ', i
                stop 65
            end if
            X(i, 1) = 1.0_dp
            X(i, 2) = x1
            X(i, 3) = x2
            y(i) = yy
        end do

        close (u)
    end subroutine le_dados

    subroutine troca(s, de, para)
        character(len=*), intent(inout) :: s
        character, intent(in) :: de, para
        integer :: i
        do i = 1, len(s)
            if (s(i:i) == de) s(i:i) = para
        end do
    end subroutine troca

    ! -----------------------------------------------------------------------
    ! ALGORITMO 1: equações normais.
    !
    ! Resolve `(XᵗX) b = Xᵗy` por eliminação de Gauss com pivotamento parcial.
    !
    ! É o algoritmo que todo livro-texto apresenta primeiro, e o que **não se
    ! deve usar**: formar `XᵗX` eleva o número de condição ao quadrado, e
    ! perde metade dos dígitos significativos antes de a eliminação começar.
    !
    ! O pivotamento parcial está aqui de propósito: sem ele a comparação seria
    ! injusta, porque parte da perda seria da eliminação e não das equações
    ! normais. Com ele, a eliminação está tão boa quanto dá -- e o que sobra de
    ! erro é atribuível ao `XᵗX`.
    ! -----------------------------------------------------------------------
    subroutine ols_equacoes_normais(X, y, b)
        real(dp), intent(in) :: X(NOBS, NPAR), y(NOBS)
        real(dp), intent(out) :: b(NPAR)

        real(dp) :: A(NPAR, NPAR), c(NPAR)
        integer :: i, j, k, piv
        real(dp) :: fator, maxabs, tmp

        ! XᵗX e Xᵗy
        do i = 1, NPAR
            do j = 1, NPAR
                A(i, j) = sum(X(:, i) * X(:, j))
            end do
            c(i) = sum(X(:, i) * y)
        end do

        ! Eliminação de Gauss com pivotamento parcial.
        do k = 1, NPAR - 1
            piv = k
            maxabs = abs(A(k, k))
            do i = k + 1, NPAR
                if (abs(A(i, k)) > maxabs) then
                    maxabs = abs(A(i, k))
                    piv = i
                end if
            end do

            if (piv /= k) then
                do j = 1, NPAR
                    tmp = A(k, j); A(k, j) = A(piv, j); A(piv, j) = tmp
                end do
                tmp = c(k); c(k) = c(piv); c(piv) = tmp
            end if

            do i = k + 1, NPAR
                fator = A(i, k) / A(k, k)
                A(i, k:NPAR) = A(i, k:NPAR) - fator * A(k, k:NPAR)
                c(i) = c(i) - fator * c(k)
            end do
        end do

        ! Substituição retroativa.
        do i = NPAR, 1, -1
            b(i) = (c(i) - sum(A(i, i + 1:NPAR) * b(i + 1:NPAR))) / A(i, i)
        end do
    end subroutine ols_equacoes_normais

    ! -----------------------------------------------------------------------
    ! ALGORITMO 2: QR por reflexões de Householder.
    !
    ! Trabalha com `X` diretamente: nunca forma `XᵗX`, e por isso **não** eleva
    ! o número de condição ao quadrado.
    !
    ! É o que o `lm` do R, o `\` do Octave e o `lstsq` do numpy fazem -- cada
    ! um com variações (pivotamento, SVD), e todos pelo mesmo motivo.
    !
    ! A reflexão de Householder é escolhida em vez de Gram-Schmidt porque
    ! Gram-Schmidt clássico perde ortogonalidade justamente quando as colunas
    ! são quase colineares, que é o caso que este projeto testa. Householder é
    ! ortogonal por construção, em aritmética exata e aproximadamente em ponto
    ! flutuante.
    ! -----------------------------------------------------------------------
    subroutine ols_householder_qr(X, y, b)
        real(dp), intent(in) :: X(NOBS, NPAR), y(NOBS)
        real(dp), intent(out) :: b(NPAR)

        real(dp) :: R(NOBS, NPAR), c(NOBS), v(NOBS)
        real(dp) :: normx, alpha, vtv, vtc
        integer :: k, j, i

        R = X
        c = y

        do k = 1, NPAR
            ! A norma da subcoluna, de k até o fim.
            normx = sqrt(sum(R(k:NOBS, k)**2))
            ! `<= tiny` e nao `== 0`: comparar real com zero exato e o que o
            ! `-Wcompare-reals` do gfortran acusa, e com razao -- uma coluna
            ! numericamente nula raramente da exatamente zero. `tiny(1.0_dp)`
            ! e o menor normalizado positivo, e abaixo dele a reflexao nao tem
            ! o que refletir.
            if (normx <= tiny(1.0_dp)) cycle

            ! O sinal escolhido EVITA cancelamento: somar valores de mesmo
            ! sinal nunca subtrai números próximos. Escolher o outro sinal
            ! funciona em aritmética exata e perde dígitos em ponto flutuante
            ! -- é o erro clássico desta rotina.
            alpha = -sign(normx, R(k, k))

            v = 0.0_dp
            v(k:NOBS) = R(k:NOBS, k)
            v(k) = v(k) - alpha

            vtv = sum(v(k:NOBS)**2)
            if (vtv <= tiny(1.0_dp)) cycle

            ! Aplica a reflexão a cada coluna restante e ao lado direito.
            do j = k, NPAR
                vtc = sum(v(k:NOBS) * R(k:NOBS, j))
                R(k:NOBS, j) = R(k:NOBS, j) - (2.0_dp * vtc / vtv) * v(k:NOBS)
            end do

            vtc = sum(v(k:NOBS) * c(k:NOBS))
            c(k:NOBS) = c(k:NOBS) - (2.0_dp * vtc / vtv) * v(k:NOBS)
        end do

        ! Substituição retroativa no sistema triangular R b = c.
        do i = NPAR, 1, -1
            b(i) = (c(i) - sum(R(i, i + 1:NPAR) * b(i + 1:NPAR))) / R(i, i)
        end do
    end subroutine ols_householder_qr

    subroutine estatisticas(X, y, b, r2, sigma, gl)
        real(dp), intent(in) :: X(NOBS, NPAR), y(NOBS), b(NPAR)
        real(dp), intent(out) :: r2, sigma
        integer, intent(out) :: gl

        real(dp) :: ajustado(NOBS), resid(NOBS), sse, sst, media

        ajustado = matmul(X, b)
        resid = y - ajustado

        sse = sum(resid**2)
        media = sum(y) / real(NOBS, dp)
        sst = sum((y - media)**2)

        gl = NOBS - NPAR
        r2 = 1.0_dp - sse / sst
        sigma = sqrt(sse / real(gl, dp))
    end subroutine estatisticas

end program modelo
