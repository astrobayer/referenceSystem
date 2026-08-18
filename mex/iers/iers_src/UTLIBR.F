      SUBROUTINE UTLIBR (RMJD, DUT1, DLOD)
*+
*  UTLIBR - subdiurnal libration effect on UT1 and LOD.
*  Test cases:
*     rmjd_a = 44239.1 -> dUT1_a =  2.441143834386761746D0 mus
*                         dLOD_a = -14.78971247349449492D0 mus/day
*     rmjd_b = 55227.4 -> dUT1_b = -2.655705844335680244D0 mus
*                         dLOD_b =  27.39445826599846967D0 mus/day
*  Source: IERS Conventions (2010), Table 5.1b
*-----------------------------------------------------------------------
      IMPLICIT NONE
      DOUBLE PRECISION RMJD, DUT1, DLOD

      INTEGER I, J
      INTEGER IARG(6,11)
      DOUBLE PRECISION T, GMST, L, LP, F, D, OM
      DOUBLE PRECISION ARG(6)
      DOUBLE PRECISION PER(11), DUT1S(11), DUT1C(11), DLODS(11),
     .                 DLODC(11) 
      DOUBLE PRECISION ANGLE

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
     .((IARG(I,J),I=1,6), PER(J), DUT1S(J),DUT1C(J), DLODS(J), DLODC(J),
     .                                                           J=1,11)
     ./2, -2,  0, -2,  0, -2, 0.5377239,  0.05, -0.03,  -0.3,  -0.6,
     . 2,  0,  0, -2, -2, -2, 0.5363232,  0.06, -0.03,  -0.4,  -0.7,
     . 2, -1,  0, -2,  0, -2, 0.5274312,  0.35, -0.20,  -2.4,  -4.1,
     . 2,  1,  0, -2, -2, -2, 0.5260835,  0.07, -0.04,  -0.5,  -0.8,
     . 2,  0,  0, -2,  0, -1, 0.5175645, -0.07,  0.04,   0.5,   0.8,
     . 2,  0,  0, -2,  0, -2, 0.5175251,  1.75, -1.01, -12.2, -21.3,
     . 2,  1,  0, -2,  0, -2, 0.5079842, -0.05,  0.03,   0.3,   0.6,
     . 2,  0, -1, -2,  2, -2, 0.5006854,  0.04, -0.03,  -0.3,  -0.6,
     . 2,  0,  0, -2,  2, -2, 0.5000000,  0.76, -0.44,  -5.5,  -9.6,
     . 2,  0,  0,  0,  0,  0, 0.4986348,  0.21, -0.12,  -1.5,  -2.6,
     . 2,  0,  0,  0,  0, -1, 0.4985982,  0.06, -0.04,  -0.4,  -0.8/

      DUT1 = 0D0
      DLOD = 0D0

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

      DO 20 J=1,11
        ANGLE = 0D0
        DO 10 I=1,6
          ANGLE = ANGLE + IARG(I,J) * ARG(I)
   10   CONTINUE
        ANGLE = DMOD( ANGLE, TWOPI )

        DUT1 = DUT1 + DUT1S(J)*DSIN(ANGLE) + DUT1C(J)*DCOS(ANGLE)
        DLOD = DLOD + DLODS(J)*DSIN(ANGLE) + DLODC(J)*DCOS(ANGLE)
   20 CONTINUE
      RETURN
      END
