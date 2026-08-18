/* Measures the Qdot term of Rdot and the equinox-versus-CIO agreement (R13b). */
#include <stdio.h>
#include <math.h>
#include "sofa.h"
#define DAS2R 4.848136811095359935899141e-6
#define DAY 86400.0
int main(void){
    double h=200.0, worstQ=0.0, worstQdd=0.0, worstR=0.0;
    int e,i,j;
    for(e=0;e<40;e++){
        double mjd=47892.0+e*548.0, sec=43200.0;
        double d1=2400000.5+mjd;
        double qm[3][3],q0[3][3],qp[3][3];
        double x,y,s;
        iauXys06a(d1,(sec-h)/DAY,&x,&y,&s); iauC2ixys(x,y,s,qm);
        iauXys06a(d1,sec/DAY,&x,&y,&s);     iauC2ixys(x,y,s,q0);
        iauXys06a(d1,(sec+h)/DAY,&x,&y,&s); iauC2ixys(x,y,s,qp);
        for(i=0;i<3;i++)for(j=0;j<3;j++){
            double qd=fabs(qp[i][j]-qm[i][j])/(2.0*h);
            double qdd=fabs(qp[i][j]-2.0*q0[i][j]+qm[i][j])/(h*h);
            if(qd>worstQ)worstQ=qd;
            if(qdd>worstQdd)worstQdd=qdd;
        }
        /* equinox route: rc2i_equinox = Rz(GST-ERA) * Pnm06a, compared with
         * the CIO route rc2i = C2ixys(x,y,s). Both without observed offsets,
         * so the two describe the same model and must agree. */
        {
            double rnpb[3][3], rc2i[3][3], era, gst, eo, m[3][3];
            double ut1=sec/DAY;
            iauPnm06a(d1,sec/DAY,rnpb);
            iauXys06a(d1,sec/DAY,&x,&y,&s); iauC2ixys(x,y,s,rc2i);
            era=iauEra00(d1,ut1);
            gst=iauGst06a(d1,ut1,d1,sec/DAY);
            eo=era-gst;
            for(i=0;i<3;i++)for(j=0;j<3;j++) m[i][j]=rnpb[i][j];
            iauRz(-eo,m);   /* Rz(-(ERA-GST)) * NPB  ==  CIO based rc2i */
            for(i=0;i<3;i++)for(j=0;j<3;j++){
                double d=fabs(m[i][j]-rc2i[i][j]);
                if(d>worstR)worstR=d;
            }
        }
    }
    printf("over 40 epochs 1990-2050, h=%.0f s\n",h);
    printf("  max |Qdot| element   %.4e 1/s   ratio to omega %.3e"
           "   velocity at 7e6 m %.2f um/s\n",
           worstQ, worstQ/7.292115e-5, worstQ*7.0e6*1e6);
    printf("  max |Qddot| element  %.4e 1/s^2 acceleration %.3e m/s^2\n",
           worstQdd, worstQdd*7.0e6);
    printf("  equinox vs CIO worst element %.4e = %.3f uas\n",
           worstR, worstR/DAS2R*1e6);
    return 0;
}
