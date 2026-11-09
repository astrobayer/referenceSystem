function vectors = broadcastVectors(vectors, epochCount, name, functionName)
%BROADCASTVECTORS Expand one 3x1 column to one per epoch, or check the count.
%
%   vectors = broadcastVectors(vectors, epochCount, name, functionName)
%
%   PACKAGE-PRIVATE. A 3xN block and an epoch struct of N entries have to agree
%   and a single column has to be usable for every epoch; that is three lines
%   and it was about to be written twice, in gcrsToBcrs and bcrsToGcrs, which
%   is how the pair drifts.
%
% INPUT ARGUMENTS
%   Name           Size   Type      Units  Description
%   ----           ----   ----      -----  -----------
%   vectors        3xM    double    -      Columns to broadcast or check.
%   epochCount     1x1    double    -      Required number of columns.
%   name           1x1    string    -      Argument name, for the message.
%   functionName   1x1    string    -      Public caller, for the identifier.
%
% OUTPUT ARGUMENTS
%   Name       Size   Type     Units  Description
%   ----       ----   ----     -----  -----------
%   vectors    3xN    double   -      One column per epoch.
%
% METHOD
%   A single column is repeated; any other count that is not epochCount is an
%   error rather than an implicit expansion, because MATLAB's own broadcasting
%   would silently accept a 3x1 against a 3xN and say nothing about a 3x2
%   against a 3x7 until much later.
%
% ACCURACY
%   Not applicable; no arithmetic is performed.
%
% ERRORS
%   referenceSystem:<caller>:sizeMismatch
%
% REFERENCES
%   Handover section C.2 (identifiers name the public caller), C.5 rule 2.
%
% EXAMPLE
%   % Not called directly; see gcrsToBcrs.
%
% KEYWORDS
%   broadcast, size check, vectorization, private
%
% See also GCRSTOBCRS, BCRSTOGCRS.
%
% -------------------------------------------------------------------------
% referenceSystem v3.0
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-28 15:40 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    if size(vectors, 2) == epochCount
        return
    end
    if size(vectors, 2) == 1
        vectors = repmat(vectors, 1, epochCount);
        return
    end
    error(sprintf('referenceSystem:%s:sizeMismatch', functionName), ...
        ['%s must have one column or one column per epoch; it has %d ', ...
        'columns for %d epochs.'], name, size(vectors, 2), epochCount);
end
