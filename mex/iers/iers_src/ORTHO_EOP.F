      SUBROUTINE ORTHO_EOP ( TIME, EOP )
*+
*  - - - - - - - - - -
*   O R T H O _ E O P 
*  - - - - - - - - - -
*
*  This routine is part of the International Earth Rotation and
*  Reference Systems Service (IERS) Conventions software collection.
*
*  The purpose of the subroutine is to compute the diurnal and semi-
*  diurnal variations in Earth Orientation Parameters (x,y, UT1) from
*  ocean tides.
* 
*  Status: Class 1 model
*
*  Given:
*     TIME           d     Modified Julian Date 
*
*  Returned:
*     EOP            d     delta_x, in microarcseconds
*                          delta_y, in microarcseconds
*                          delta_UT1, in microseconds 
*
*  Called:
*     CNMTX                Compute time dependent part of second degree
*                          diurnal and semidiurnal tidal potential from
*                          the dominant spectral lines in the Cartwright-
*                          Tayler-Edden harmonic decomposition
*
*  Test case:
*     given input: MJD = 47100D0
*
*     expected output: delta_x = -162.8386373279636530D0 microarcseconds
*                      delta_y = 117.7907525842668974D0 microarcseconds
*                      delta_UT1 = -23.39092370609808214D0 microseconds
*
*  References:
*     Ray, R. D., Steinberg, D. J., Chao, B. F., and Cartwright, D. E.,
*     "Diurnal and Semidiurnal Variations in the Earth's Rotation
*     Rate Induced by Ocean Tides", 1994, Science, 264, pp. 830-832
*
*     Petit, G. and Luzum, B. (eds.), IERS Conventions (2010),
*     IERS Technical Note No. 36, BKG (2010)
*-----------------------------------------------------------------------

      IMPLICIT NONE
      INTEGER K, J
      DOUBLE PRECISION EOP(3), ORTHOW(12,3), TIME, H(12)
      DATA ORTHOW /
     .-6.77832D0,-14.86323D0,0.47884D0,-1.45303D0,0.16406D0,  0.42030D0,
     . 0.09398D0,25.73054D0,-4.77974D0, 0.28080D0,1.94539D0, -0.73089D0,
     .14.86283D0,-6.77846D0, 1.45234D0, 0.47888D0,-0.42056D0, 0.16469D0,
     .15.30276D0,-4.30615D0, 0.07564D0, 2.28321D0,-0.45717D0,-1.62010D0,
     .-1.76335D0,1.03364D0, -0.27553D0, 0.34569D0,-0.12343D0,-0.10146D0,
     .-0.47119D0,1.28997D0, -0.19336D0, 0.02724D0, 0.08955D0, 0.04726D0/

* Compute the partials of the tidal variations to the orthoweights
      CALL CNMTX (TIME, H)

* Compute eop changes
      DO 20 K=1,3
         EOP(K) = 0D0
         DO 40 J=1,12
            EOP(K) = EOP(K) + H(J)*ORTHOW(J,K)
40       CONTINUE         

20    CONTINUE
      RETURN
      END
