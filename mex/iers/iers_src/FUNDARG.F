      SUBROUTINE FUNDARG ( T, L, LP, F, D, OM )
*+
*  FUNDARG - lunisolar fundamental arguments, Simon et al. (1994),
*  IERS Conventions (2010) Sec 5.7.1-5.7.2.
*
*  Test case: T = 0.07995893223819302 (MJD = 54465)
*    expected: L  = 2.291187512612069099 rad
*              LP = 6.212931111003726414 rad
*              F  = 3.658025792050572989 rad
*              D  = 4.554139562402433228 rad
*              OM = -0.5167379217231804489 rad
*-----------------------------------------------------------------------
      IMPLICIT NONE

      DOUBLE PRECISION T, L, LP, F, D, OM

      DOUBLE PRECISION DAS2R
      PARAMETER ( DAS2R = 4.848136811095359935899141D-6 )
      DOUBLE PRECISION TURNAS
      PARAMETER ( TURNAS = 1296000D0 )
      DOUBLE PRECISION D2PI
      PARAMETER ( D2PI = 6.283185307179586476925287D0 )

      L = MOD (       485868.249036D0 +
     .                  T*( 1717915923.2178D0 +
     .                  T*(         31.8792D0 +
     .                  T*(          0.051635D0 +
     .                  T*(        - 0.00024470D0 )))), TURNAS ) * DAS2R

      LP = MOD (       1287104.79305D0 +
     .            T*( 129596581.0481D0 +
     .            T*(       - 0.5532D0 +
     .            T*(         0.000136D0 +
     .            T*(       - 0.00001149D0 )))), TURNAS ) * DAS2R

      F  = MOD (       335779.526232D0 +
     .                  T*( 1739527262.8478D0 +
     .                  T*(       - 12.7512D0 +
     .                  T*(       -  0.001037D0 +
     .                  T*(          0.00000417D0 )))), TURNAS ) * DAS2R

      D = MOD (        1072260.70369D0 +
     .          T*( 1602961601.2090D0 +
     .          T*(        - 6.3706D0 +
     .          T*(          0.006593D0 +
     .          T*(        - 0.00003169D0 )))), TURNAS ) * DAS2R

      OM = MOD (       450160.398036D0 +
     .             T*( - 6962890.5431D0 +
     .             T*(         7.4722D0 +
     .             T*(         0.007702D0 +
     .             T*(       - 0.00005939D0 )))), TURNAS ) * DAS2R

      RETURN
      END
