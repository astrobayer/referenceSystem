#!/bin/sh
# runStandaloneTests.sh
# ---------------------
# Build and run the referenceSystem C core tests with plain gcc, with no
# MATLAB and no mex.h in the picture. Handover section C.4 requires rsCore.c
# to stay buildable this way, because it is the only check of the arithmetic
# that does not depend on a MATLAB installation.
#
#   sh test/c/runStandaloneTests.sh            serial build
#   RS_OPENMP=1 sh test/c/runStandaloneTests.sh  build with OpenMP
#
# Exit status is 0 when every test passed.
#
# -------------------------------------------------------------------------
# referenceSystem v2.1
# Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
# Created: 2026-07-24 18:25 (CEST, UTC+02:00)
# -------------------------------------------------------------------------
set -e

scriptDir=$(cd "$(dirname "$0")" && pwd)
rootDir=$(cd "$scriptDir/../.." && pwd)
mexDir="$rootDir/mex"
buildDir="$scriptDir/build"

CC=${CC:-gcc}
CFLAGS=${CFLAGS:--O2 -std=c99 -Wall -Wextra -Wno-unused-parameter}

if [ "${RS_OPENMP:-0}" = "1" ]; then
    CFLAGS="$CFLAGS -fopenmp"
fi

mkdir -p "$buildDir"

echo "Building rsCore standalone tests with $CC"
# shellcheck disable=SC2086
$CC $CFLAGS -I"$mexDir" -o "$buildDir/testRsCore" \
    "$scriptDir/testRsCore.c" "$mexDir/rsCore.c" "$mexDir"/iers/*.c \
    "$mexDir"/sofa/*.c -lm

echo "Building ported IERS Conventions routine tests with $CC"
# shellcheck disable=SC2086
$CC $CFLAGS -I"$mexDir" -o "$buildDir/testIersModels" \
    "$scriptDir/testIersModels.c" "$mexDir"/iers/*.c "$mexDir"/sofa/*.c -lm

echo "Building public C API tests with $CC"
apiCoreSource=$(ls "$mexDir"/*.c | grep -v 'mexGateway\.c$')
# shellcheck disable=SC2086
$CC $CFLAGS -I"$mexDir" -o "$buildDir/testApi" \
    "$scriptDir/testApi.c" $apiCoreSource "$mexDir"/iers/*.c \
    "$mexDir"/sofa/*.c -lm

echo "Building Chebyshev panel core tests with $CC"
# shellcheck disable=SC2086
# Globbed for the same reason as the gateway link line below: testCheb.c
# reaches rsRotationItrsToGcrsFromCip at rev. 1.93, and naming rsCheb.c alone
# would have failed the moment it did.
chebCoreSource=$(ls "$mexDir"/*.c | grep -v 'mexGateway\.c$')
# shellcheck disable=SC2086
$CC $CFLAGS -I"$mexDir" -o "$buildDir/testCheb" \
    "$scriptDir/testCheb.c" $chebCoreSource "$mexDir"/iers/*.c \
    "$mexDir"/sofa/*.c -lm

echo "Building mexGateway logic tests with $CC and the stub mex API"
# shellcheck disable=SC2086
# EVERY CORE SOURCE EXCEPT THE ONE THE TEST #includes. Naming rsCore.c here
# was the same defect buildMex carried until rev. 1.85: adding mex/rsCheb.c
# left this link line behind and the gateway tests failed with four undefined
# references. mexGateway.c is excluded because testMexGateway.c includes it
# directly, which is how it reaches the static command functions.
gatewayCoreSource=$(ls "$mexDir"/*.c | grep -v 'mexGateway\.c$')
# shellcheck disable=SC2086
$CC $CFLAGS -I"$mexDir" -I"$scriptDir" -o "$buildDir/testMexGateway" \
    "$scriptDir/testMexGateway.c" $gatewayCoreSource "$mexDir"/iers/*.c \
    "$mexDir"/sofa/*.c -lm

echo
"$buildDir/testRsCore"
echo
# The fixture argument is where the D27 SOFA-versus-FUNDARG sweep is written.
# It is a build product of this script, not a file kept under revision
# control, and TestTime reads it (handover obligation O3).
"$buildDir/testIersModels" "$rootDir/test/fixtures/fundargIers.csv"
echo
# Both interpolant formats: arc.eopi is format 1 (six channels) and
# arcFormat2.eopi is format 2 with the seventh, lod, channel older builders
# wrote. arcFormat2Rate.csv is MATLAB's rate on the latter, the truth that does
# not share the C side's construction. arcFormat2DaySecond.csv is MATLAB's
# rotation and rate at a day and a second, the truth for the day-and-second
# entry points. The last argument is a directory testApi may write a scratch
# file into and remove again.
"$buildDir/testApi" "$rootDir/test/fixtures/arc.eopi" \
    "$rootDir/test/fixtures/arcFormat2.eopi" \
    "$rootDir/test/fixtures/arcFormat2Rate.csv" \
    "$rootDir/test/fixtures/arcFormat2DaySecond.csv" \
    "$buildDir"
echo
"$buildDir/testCheb"
echo
"$buildDir/testMexGateway"

# The S3 measurement studies are kept beside the tests they justify. They are
# not part of the pass/fail suite: they measure the difference step, the CIP
# evaluation noise and the term magnitudes quoted in the ACCURACY blocks of
# cipCoordinates and rotationItrsToGcrs, and they take a few seconds each.
#
#   sh test/c/runStandaloneTests.sh study
if [ "${1:-}" = "study" ]; then
    echo
    echo "Building the S3 measurement studies"
    for name in noiseProbe stepSelect qterm; do
        # shellcheck disable=SC2086
        $CC $CFLAGS -I"$mexDir/sofa" -o "$buildDir/$name" \
            "$scriptDir/$name.c" "$mexDir"/sofa/*.c -lm
        echo
        "$buildDir/$name"
    done
fi
