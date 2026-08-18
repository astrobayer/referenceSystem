      SUBROUTINE PMSDNUT2 (RMJD, PM)
*+
*  PMSDNUT2 - diurnal lunisolar effect on polar motion (subdiurnal nutation).
*  IMPORTANT: this version (iband=1) neglects the linear trend and the
*  long-periodic terms per IERS Conventions (2010) Section 5.5.1.1,
*  using only the 10 quasi-diurnal terms (J=16..25).
*
*  Test case: rmjd = 54335D0 (August 23, 2007)
*    expected: pm(1) (dx) =  24.83144238273364834D0 microarcseconds
*              pm(2) (dy) = -14.09240692041837661D0 microarcseconds
*
*  Source: IERS Conventions (2010), Table 5.1a
*-----------------------------------------------------------------------
      IMPLICIT NONE
      DOUBLE PRECISION RMJD, PM(2)

      INTEGER IBAND, I, J, JSTART
      PARAMETER ( IBAND = 1 )
      INTEGER IARG(6,25)
      DOUBLE PRECISION T, GMST, L, LP, F, D, OM
      DOUBLE PRECISION ARG(6)
      DOUBLE PRECISION PER(25), XS(25), XC(25), YS(25), YC(25)
      DOUBLE PRECISION ANGLE, XRATE, YRATE

      DOUBLE PRECISION DAS2R
      PARAMETER ( DAS2R = 4.848136811095359935899141D-6 )
      DOUBLE PRECISION TURNAS
      PARAMETER ( TURNAS = 1296000D0 )
      DOUBLE PRECISION RMJD0, PI, TWOPI
      PARAMETER ( RMJD0   = 51544.5D0                )
      PARAMETER ( PI      = 3.141592653589793238462643D0 )
      PARAMETER ( TWOPI   = 6.283185307179586476925287D0 )
      DOUBLE PRECISION RAD2SEC
      PARAMETER ( RAD2SEC = 86400D0/TWOPI            )

      DATA 
     . (  (IARG(I,J),I=1,6),    PER(J),   XS(J),  XC(J),  YS(J),  YC(J),
     .                                                           J=1,15)
     ./ 0,  0, 0,  0,  0, -1, 6798.3837,    0.0,   0.6,   -0.1,   -0.1,
     .  0, -1, 0,  1,  0,  2, 6159.1355,    1.5,   0.0,   -0.2,    0.1,
     .  0, -1, 0,  1,  0,  1, 3231.4956,  -28.5,  -0.2,    3.4,   -3.9,
     .  0, -1, 0,  1,  0,  0, 2190.3501,   -4.7,  -0.1,    0.6,   -0.9,
     .  0,  1, 1, -1,  0,  0, 438.35990,   -0.7,   0.2,   -0.2,   -0.7,
     .  0,  1, 1, -1,  0, -1, 411.80661,    1.0,   0.3,   -0.3,    1.0,
     .  0,  0, 0,  1, -1,  1, 365.24219,    1.2,   0.2,   -0.2,    1.4,
     .  0,  1, 0,  1, -2,  1, 193.55971,    1.3,   0.4,   -0.2,    2.9,
     .  0,  0, 0,  1,  0,  2, 27.431826,   -0.1,  -0.2,    0.0,   -1.7,
     .  0,  0, 0,  1,  0,  1, 27.321582,    0.9,   4.0,   -0.1,   32.4,
     .  0,  0, 0,  1,  0,  0, 27.212221,    0.1,   0.6,    0.0,    5.1,
     .  0, -1, 0,  1,  2,  1, 14.698136,    0.0,   0.1,    0.0,    0.6,
     .  0,  1, 0,  1,  0,  1, 13.718786,   -0.1,   0.3,    0.0,    2.7,
     .  0,  0, 0,  3,  0,  3, 9.1071941,   -0.1,   0.1,    0.0,    0.9,
     .  0,  0, 0,  3,  0,  2, 9.0950103,   -0.1,   0.1,    0.0,    0.6/

      DATA 
     .(  (IARG(I,J),i=1,6),     PER(J),   XS(J),  XC(J),  YS(J),  YC(J),
     .                                                          J=16,25)
     ./ 1, -1, 0, -2,  0, -1, 1.1196992,   -0.4,   0.3,   -0.3,   -0.4,
     .  1, -1, 0, -2,  0, -2, 1.1195149,   -2.3,   1.3,   -1.3,   -2.3,
     .  1,  1, 0, -2, -2, -2, 1.1134606,   -0.4,   0.3,   -0.3,   -0.4,
     .  1,  0, 0, -2,  0, -1, 1.0759762,   -2.1,   1.2,   -1.2,   -2.1,
     .  1,  0, 0, -2,  0, -2, 1.0758059,  -11.4,   6.5,   -6.5,  -11.4,
     .  1, -1, 0,  0,  0,  0, 1.0347187,    0.8,  -0.5,    0.5,    0.8,
     .  1,  0, 0, -2,  2, -2, 1.0027454,   -4.8,   2.7,   -2.7,   -4.8,
     .  1,  0, 0,  0,  0,  0, 0.9972696,   14.3,  -8.2,    8.2,   14.3,
     .  1,  0, 0,  0,  0, -1, 0.9971233,    1.9,  -1.1,    1.1,    1.9,
     .  1,  1, 0,  0,  0,  0, 0.9624365,    0.8,  -0.4,    0.4,    0.8/

      DATA XRATE, YRATE / -3.8, -4.3/

      PM(1) = 0D0
      PM(2) = 0D0

      T = (RMJD-RMJD0)/36525D0

      GMST = MOD (   67310.54841D0 +
     .               T*( (8640184.812866D0 + 3155760000D0) +
     .               T*( 0.093104D0 +
     .               T*( -0.0000062 ))), 86400D0 )

      CALL FUNDARG ( T, L, LP, F, D, OM )

      ARG(1) = GMST / RAD2SEC + PI
      ARG(1) = DMOD( ARG(1), TWOPI )
      ARG(2) = L
      ARG(3) = LP
      ARG(4) = F
      ARG(5) = D
      ARG(6) = OM 

      IF (IBAND.EQ.1) THEN
        JSTART = 16
      ELSE
        JSTART = 1
      ENDIF
      DO 20 J=JSTART,25
        ANGLE = 0D0
        DO 10 I=1,6
          ANGLE = ANGLE + IARG(I,J) * ARG(I)
   10   CONTINUE
        ANGLE = DMOD( ANGLE, TWOPI )

        PM(1) = PM(1) + XS(J)*DSIN(ANGLE) + XC(J)*DCOS(ANGLE)
        PM(2) = PM(2) + YS(J)*DSIN(ANGLE) + YC(J)*DCOS(ANGLE)
   20 CONTINUE
      IF (IBAND.EQ.1) RETURN

      PM(1) = PM(1) + XRATE * (RMJD-RMJD0) / 365.25D0
      PM(2) = PM(2) + YRATE * (RMJD-RMJD0) / 365.25D0

      RETURN
      END
