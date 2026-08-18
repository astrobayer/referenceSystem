/*
 * iersCnmtx.c -- C port of IERS Conventions (2010) CNMTX.F.
 * Ported line-for-line from mex/iers/iers_src/CNMTX.F.
 *
 * The original declares NJ(J)/MJ(J) spanning N=2..3, but every one of
 * the 71 tabulated lines has N=2 (M=1 or 2), and the routine only
 * loops N=2..NMAX with NMAX=2 -- so N never varies here. This port
 * drops the redundant N dimension accordingly (documented inline
 * below), which changes nothing numerically.
 *
 * Test case (from the original CNMTX.F header): dmjd = 54964.0
 *   expected h(1..12) =
 *    15.35873641938967360,  9.784941251812741214, -5.520740128266865554,
 *    3.575314211234633888, -13.93717453496387648, -9.167400321705855504,
 *    5.532815475865292321,  9.558741883500834646, -10.22541212627272600,
 *    0.8367570529461261231, 1.946355176475630611, -13.55702062247304696
 * Validated in test/test_tidal.c.
 */
#include "iersModels.h"
#include <math.h>

#define NLINES 71
#define CNMTX_TWOPI 6.283185307179586476925287

/* NJ, MJ, HS, PHASE, FREQ -- transcribed verbatim from CNMTX.F.
 * NJ is always 2 in this table so it is omitted; MJ (1 or 2) is kept. */
static const int MJ_TAB[NLINES] = {
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
    2,2,2,2,2,2,2,2,2,2,2
};

static const double HS_TAB[NLINES] = {
   -1.94,-1.25,-6.64,-1.51,-8.02,-9.47,-50.20,-1.80,-9.54,1.52,
  -49.45,-262.21,1.70,3.43,1.94,
   1.37,7.41,20.62,4.14,3.94,-7.14,1.37,-122.03,1.02,2.89,
   -7.30,368.78,50.01,-1.08,2.93,
   5.25,3.95,20.62,4.09,3.42,1.69,11.29,7.23,1.51,2.16,1.38,
   1.80,4.67,16.01,19.32,
   1.30,-1.02,-4.51,120.99,1.13,22.98,1.06,-1.90,-2.18,-23.58,
   631.92,1.92,-4.66,-17.86,4.47,
   1.97,17.20,294.00,-2.46,-1.02,79.96,23.83,2.59,4.47,1.95,1.17
};

static const double PHASE_TAB[NLINES] = {
   9.0899831,8.8234208,12.1189598,1.4425700,4.7381090,4.4715466,
   7.7670857,-2.9093042,0.3862349,-3.1758666,0.1196725,3.4152116,
   12.8946194,5.5137686,6.4441883,
   -4.2322016,-0.9366625,8.5427453,11.8382843,1.1618945,5.9693878,
   -1.2032249,2.0923141,-1.7847596,8.0679449,0.8953321,4.1908712,
   7.4864102,10.7819493,0.3137975,
   6.2894282,7.2198478,-0.1610030,3.1345361,2.8679737,-4.5128771,
   4.9665307,8.2620698,11.5576089,0.6146566,3.9101957,
   20.6617051,13.2808543,16.3098310,8.9289802,
   5.0519065,15.8350306,8.6624178,11.9579569,8.0808832,4.5771061,
   0.7000324,14.9869335,11.4831564,4.3105437,7.6060827,3.7290090,
   10.6350594,3.2542086,12.7336164,
   16.0291555,10.1602590,6.2831853,2.4061116,5.0862033,8.3817423,
   11.6772814,14.9728205,4.0298682,7.3254073,9.1574019
};

static const double FREQ_TAB[NLINES] = {
   5.18688050,5.38346657,5.38439079,5.41398343,5.41490765,5.61149372,
   5.61241794,5.64201057,5.64293479,5.83859664,5.83952086,5.84044508,
   5.84433381,5.87485066,6.03795537,
   6.06754801,6.06847223,6.07236095,6.07328517,6.10287781,6.24878055,
   6.26505830,6.26598252,6.28318449,6.28318613,6.29946388,6.30038810,
   6.30131232,6.30223654,6.31759007,
   6.33479368,6.49789839,6.52841524,6.52933946,6.72592553,6.75644239,
   6.76033111,6.76125533,6.76217955,6.98835826,6.98928248,
   11.45675174,11.48726860,11.68477889,11.71529575,
   11.73249771,11.89560406,11.91188181,11.91280603,11.93000800,11.94332289,
   11.96052486,12.11031632,12.12363121,12.13990896,12.14083318,12.15803515,
   12.33834347,12.36886033,12.37274905,
   12.37367327,12.54916865,12.56637061,12.58357258,12.59985198,12.60077620,
   12.60170041,12.60262463,12.82880334,12.82972756,13.06071921
};

/* orthotide weight factors, SP(6,2) in the original */
static const double SP_TAB[2][6] = {
    {0.0298, 0.1408, 0.0805, 0.6002, 0.3025, 0.1517},
    {0.0200, 0.0905, 0.0638, 0.3476, 0.1645, 0.0923}
};

static double fmod_f(double a, double p) { return fmod(a, p); }

void iersCnmtx(double dmjd, double h[12])
{
    const double dt = 2.0;
    const double d1960 = 37076.5;

    /* anm[m][k], bnm[m][k]: m in {0,1} <-> M in {1,2}; k in {0,1,2} <-> K in {-1,0,1} */
    double anm[2][3] = {{0}}, bnm[2][3] = {{0}};

    for (int ki = 0; ki < 3; ki++) {
        int K = ki - 1; /* -1, 0, 1 */
        double dt60 = (dmjd - (double)K * dt) - d1960;
        anm[0][ki] = 0.0; anm[1][ki] = 0.0;
        bnm[0][ki] = 0.0; bnm[1][ki] = 0.0;
        for (int j = 0; j < NLINES; j++) {
            int N = 2;
            int M = MJ_TAB[j];
            int mi = M - 1;
            double pinm = (double)((N + M) % 2) * CNMTX_TWOPI / 4.0;
            double alpha = fmod_f(PHASE_TAB[j] - pinm, CNMTX_TWOPI)
                         + fmod_f(FREQ_TAB[j] * dt60, CNMTX_TWOPI);
            anm[mi][ki] += HS_TAB[j] * cos(alpha);
            bnm[mi][ki] -= HS_TAB[j] * sin(alpha);
        }
    }

    /* orthogonalize the response terms, for M = 1,2 (mi = 0,1) */
    for (int mi = 0; mi < 2; mi++) {
        double ap = anm[mi][2] + anm[mi][0]; /* K=+1 + K=-1 */
        double am = anm[mi][2] - anm[mi][0];
        double bp = bnm[mi][2] + bnm[mi][0];
        double bm = bnm[mi][2] - bnm[mi][0];

        double p0 = SP_TAB[mi][0] * anm[mi][1];
        double p1 = SP_TAB[mi][1] * anm[mi][1] - SP_TAB[mi][2] * ap;
        double p2 = SP_TAB[mi][3] * anm[mi][1] - SP_TAB[mi][4] * ap + SP_TAB[mi][5] * bm;

        double q0 = SP_TAB[mi][0] * bnm[mi][1];
        double q1 = SP_TAB[mi][1] * bnm[mi][1] - SP_TAB[mi][2] * bp;
        double q2 = SP_TAB[mi][3] * bnm[mi][1] - SP_TAB[mi][4] * bp - SP_TAB[mi][5] * am;

        anm[mi][0] = p0; anm[mi][1] = p1; anm[mi][2] = p2;
        bnm[mi][0] = q0; bnm[mi][1] = q1; bnm[mi][2] = q2;
    }

    /* fill H(1..12): for M=1,2 (mi=0,1); for K=-1,0,1 (ki=0,1,2): H[j]=A, H[j+1]=B */
    int j = 0;
    for (int mi = 0; mi < 2; mi++) {
        for (int ki = 0; ki < 3; ki++) {
            h[j]     = anm[mi][ki];
            h[j + 1] = bnm[mi][ki];
            j += 2;
        }
    }
}
