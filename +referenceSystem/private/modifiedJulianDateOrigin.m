function origin = modifiedJulianDateOrigin()
%MODIFIEDJULIANDATEORIGIN The calendar instant of MJD 0, 1858-11-17 00:00.
%
%   origin = modifiedJulianDateOrigin() returns MJD 0 as a zone-free datetime.
%
%   PACKAGE-PRIVATE, AND THE ONE PLACE THE MJD EPOCH IS FORMED, for
%   datetimeToEpoch, epochTo and leapSecondTable. It is DERIVED from
%   iersConstants.julianDateOffset
%   (JD - MJD = 2400000.5, SOFA DJM0), so the offset and the date cannot come
%   to disagree, rather than stored as a second literal. iersConstants itself
%   cannot hold a datetime: it is codegen-clean, and its contract test holds
%   every field to a finite double scalar.
%
% INPUT ARGUMENTS
%   (none)
%
% OUTPUT ARGUMENTS
%   Name     Size   Type       Units  Description
%   ----     ----   ----       -----  -----------
%   origin   1x1    datetime   -      1858-11-17 00:00:00, no time zone.
%
% METHOD
%   MATLAB's Julian date conversion of 2400000.5. Measured to be isequal to
%   datetime(1858, 11, 17, 0, 0, 0), with no time zone on either, and to give
%   bit-identical differences against a datetime carrying nanoseconds.
%
% ACCURACY
%   Exact. JD 2400000.5 is representable and the conversion is an offset.
%
% ERRORS
%   (none)
%
% See also IERSCONSTANTS, DATETIMETOEPOCH, EPOCHTO, LEAPSECONDTABLE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-09-15 14:10 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    origin = datetime(referenceSystem.iersConstants().julianDateOffset, ...
        'ConvertFrom', 'juliandate');
end
