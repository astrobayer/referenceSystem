function [position, velocity] = applyBcrsToGcrs(ingredient, position, velocity)
%APPLYBCRSTOGCRS Resolution B1.3 spatial part and its time derivative.
%
%   [position, velocity] = applyBcrsToGcrs(ingredient, position, velocity)
%
%   PACKAGE-PRIVATE, AND ITS OWN FILE FOR A REASON. Both appliers were first
%   written as LOCAL functions at the end of bcrsTransform.m, where they were
%   invisible to gcrsToBcrs and bcrsToGcrs and every call raised
%   MATLAB:UndefinedFunction - eight tests at once. A private FILE is shared
%   across the whole package; a local function is scoped to the file that holds
%   it. Section C.5 rule 2 says a helper used by more than one public function
%   is a private file, and this is why.
%
% INPUT ARGUMENTS
%   Name         Size   Type      Units  Description
%   ----         ----   ----      -----  -----------
%   ingredient   1x1    struct    -      From bcrsTransform: earthVelocity,
%                                        earthAcceleration, externalPotential,
%                                        cSquared, scaleTerm.
%   position     3xN    double    m      Geocentric separation vector.
%   velocity     3xN    double    m/s    Its derivative, or [] for none.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type     Units  Description
%   ----       ----   ----     -----  -----------
%   position   3xN    double   m      The vector in the other frame.
%   velocity   3xN    double   m/s    Its derivative, or [] if none was given.
%
% METHOD
%   IAU 2000 Resolution B1.3, spatial part, as printed in Soffel et al. 2003
%   Appendix A1, and for the velocity its time part. See bcrsTransform, which
%   assembles the ingredients and states the equations and the term sizes.
%
% ACCURACY
%   The resolution's own. Every neglected term is quantified in bcrsTransform;
%   the largest is 6.1e-13 m/s, against the 1e-7 m/s a KBR reduction works at.
%
% ERRORS
%   None; the callers validate.
%
% REFERENCES
%   Soffel, M. et al., 2003, AJ 126, 2687, Appendix A1 (IAU Resolution B1.3).
%   IERS Conventions (2010), Eq. (11.18) and (11.19), the acceleration-free form.
%
% EXAMPLE
%   % Not called directly; see gcrsToBcrs.
%
% KEYWORDS
%   BCRS, GCRS, Resolution B1.3, Lorentz, velocity, private
%
% See also BCRSTRANSFORM, GCRSTOBCRS, BCRSTOGCRS.
%
% -------------------------------------------------------------------------
% referenceSystem v2.1
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-08-02 09:20 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    v = ingredient.earthVelocity;
    a = ingredient.earthAcceleration;
    % PLUS, NOT MINUS, AND THE SIGN WAS WRONG AS FIRST WRITTEN. This is the
    % FORWARD direction, BCRS to GCRS, so it must invert IERS Eq. (11.19),
    % r_TDB = r_TT (1 - U/c^2 - L_C) - ... : a TDB-compatible barycentric
    % vector is SHORTER than the TT-compatible geocentric one, so coming
    % back lengthens it. Checked against Eq. (11.19) numerically rather
    % than by eye: the wrong sign leaves a round-trip residual of 0.189 m,
    % which is exactly 2*L_C*|r|, and the right one leaves 5.5e-9 m.
    w = ingredient.externalPotential + ingredient.scaleTerm*ingredient.cSquared;
    cSquared = ingredient.cSquared;

    vDotR = sum(v.*position, 1);
    aDotR = sum(a.*position, 1);

    if ~isempty(velocity)
        % dX/dt, then divided by dT/dt = 1 - rateOfTime/c^2. The potential
        % enters without the L_C scale term: TT and TDB rescale lengths and
        % times alike, so a velocity carries no L_C.
        potential = ingredient.externalPotential;
        vDotRdot = sum(v.*velocity, 1);
        aDotRdot = sum(a.*velocity, 1);
        rDotRdot = sum(position.*velocity, 1);
        rateOfTime = 0.5*sum(v.^2, 1) + potential + aDotR + vDotRdot;
        velocity = velocity + (0.5*a.*vDotR + 0.5*v.*(aDotR + vDotRdot) + ...
            potential.*velocity + velocity.*aDotR + position.*aDotRdot - ...
            a.*rDotRdot + velocity.*rateOfTime)/cSquared;
    end

    position = position + (0.5*v.*vDotR + w.*position + position.*aDotR - ...
        0.5*a.*sum(position.^2, 1))/cSquared;
end
