function [position, velocity] = applyGcrsToBcrs(ingredient, position, velocity)
%APPLYGCRSTOBCRS The inverse of applyBcrsToGcrs, by iteration.
%
%   [position, velocity] = applyGcrsToBcrs(ingredient, position, velocity)
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
%   Appendix A1. See bcrsTransform, which assembles the ingredients and states
%   the equation, the term sizes and the finite-difference validation in full.
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

    target = position;
    targetVelocity = velocity;
    for iteration = 1:2
        [trial, trialVelocity] = applyBcrsToGcrs(ingredient, position, velocity);
        position = position + (target - trial);
        if ~isempty(velocity)
            velocity = velocity + (targetVelocity - trialVelocity);
        end
    end
end
