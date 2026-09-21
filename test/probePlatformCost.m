function result = probePlatformCost(options)
%PROBEPLATFORMCOST Separate file cost, call cost and compiled cost on a machine.
%
%   result = referenceSystem.test.probePlatformCost()
%   result = probePlatformCost(ScratchDir = "D:\tmp\rsProbe")
%
%   WHY THIS EXISTS. Runs 81 to 83 took 99.7, 84.3 and 81.3 s on PCWIN64
%   against 47.3 s for the same suite on GLNXA64. The BENCHMARKS section was
%   healthy in every one, so the compiled kernels are not the cost and the
%   difference sits in whatever surrounds them.
%
%   AND THE COMPARISON THAT PRODUCED THOSE RATIOS IS CONFOUNDED, WHICH IS THE
%   FIRST THING THIS PROBE IS FOR. The Linux figure and the Windows figures
%   come from DIFFERENT COMPUTERS, not from one machine booted two ways. A
%   ratio of suite durations across two machines names the difference after
%   whichever variable the reader happened to notice - here the operating
%   system - when processor, clock, disk and MATLAB update all changed at the
%   same time. That is precisely what O21 forbids: a speed claim needs a
%   measured baseline, and a number from another machine is not one.
%
%   SO THE FIELDS BELOW ARE BUILT TO BE COMPARABLE ANYWAY. fileRatio is
%   MACHINE-INTERNAL - the same files, read twice on one machine, in two
%   locations - so it answers its question without any cross-machine
%   comparison at all. callInCpuSteps and mexInCpuSteps are divided by that
%   machine's own scalar-loop time, so they say how expensive a call is IN
%   UNITS OF THAT PROCESSOR and can be compared with another machine's figure
%   even when the two processors differ. The raw seconds are reported too, and
%   are the fields NOT to compare across machines.
%
% INPUT ARGUMENTS
%   (none)
%
% OPTIONAL NAME-VALUE ARGUMENTS
%   Name          Size   Type      Default    Description
%   ----          ----   ----      -------    -----------
%   ScratchDir    1x1    string    tempdir    A SECOND location to repeat the
%                                             file measurement in. Point it at
%                                             a path OUTSIDE the scanned tree
%                                             - not under Documents, OneDrive
%                                             or a network share - and compare.
%   Repeat        1x1    double    3          Trials; the median is reported.
%
% OUTPUT ARGUMENTS
%   Name             Size   Type     Units  Description
%   ----             ----   ----     -----  -----------
%   result           1x1    struct   -      Fields below, all medians.
%   .fileReadHome    1x1    double   s      Reading every package .m file in
%                                           place, once.
%   .fileReadScratch 1x1    double   s      The same files, copied to
%                                           ScratchDir and read there.
%   .fileRatio       1x1    double   -      home / scratch. Near 1 means the
%                                           location does not matter.
%   .callOverhead    1x1    double   us     Per call, a package function with
%                                           an arguments block, N=1.
%   .mexOverhead     1x1    double   us     Per call, the same work through
%                                           the gateway at N=1.
%   .cpuScalarStep   1x1    double   us     Per iteration of a bare scalar
%                                           arithmetic loop: no file, no
%                                           dispatch, no library. The
%                                           machine's own speed unit.
%   .cpuVectorOp     1x1    double   s      One large elementwise operation:
%                                           memory bandwidth and threading.
%   .callInCpuSteps  1x1    double   -      callOverhead / cpuScalarStep.
%                                           DIMENSIONLESS and therefore the
%                                           field to compare BETWEEN machines.
%   .mexInCpuSteps   1x1    double   -      The same for the gateway call.
%   .fileOpenOnly    1x1    double   s      Opening and closing every source
%                                           file, reading no bytes.
%   .fileOpenShare   1x1    double   -      fileOpenOnly / fileReadHome. Near
%                                           1 means the bytes are free and the
%                                           cost is the OS path.
%   .vectorOpSmall   1x1    double   s      Elementwise over 1e4 elements: in
%                                           cache, almost no allocation.
%   .vectorOpLarge   1x1    double   s      The same over 4e6: tens of MB
%                                           allocated and touched.
%   .vectorPerElementRatio
%                    1x1    double   -      Per-element cost large/small. Near
%                                           1 means memory is not the
%                                           constraint; well above 1 means it
%                                           is.
%   .callBare        1x1    double   us     A call with NO arguments block.
%   .callValidated   1x1    double   us     The same call behind the argument
%                                           validation this toolbox uses.
%   .validationShare 1x1    double   -      callValidated / callBare. How much
%                                           of a package call is validation.
%   .computeThreads  1x1    double   -      maxNumCompThreads, so the threaded
%                                           rows can be read or discarded.
%   .platform        1x1    string   -      computer("arch").
%
% METHOD
%   THREE MEASUREMENTS, BECAUSE THERE ARE THREE CANDIDATES AND THEY HAVE
%   DIFFERENT REMEDIES.
%
%     fileRatio well above 1     The scanned location is the cost. An
%                                exclusion for the working tree, or moving it
%                                off the scanned path, recovers the time. This
%                                is the candidate the test profile points at:
%                                TestDispatch reads all 103 sources, hashes
%                                every C file and spawns a nested suite run,
%                                and it took 24.9 s in BOTH Windows runs -
%                                identical, warm cache or cold.
%     fileRatio near 1, and
%     callInCpuSteps larger
%     than the other machine's   MATLAB-level overhead on this platform:
%                                dispatch, arguments blocks, validators. There
%                                is no fix in this toolbox, and the carried
%                                items in the handover header - iersConstants
%                                at 36 calls per rotation, attitudeConvention
%                                evaluated as a default - are worth more here
%                                than they are on Linux.
%     mexOverhead slower         The gateway or its build. Least likely: the
%                                BENCHMARKS section is within target on both
%                                platforms.
%
%   THE THREE PAIRS ADDED AT REV. 1.197 DISCRIMINATE, AND EACH IS READ WITHIN
%   ONE MACHINE BEFORE THE TWO ARE COMPARED. The first probe established the
%   SHAPE - a faster core surrounded by slower everything - and killed the
%   tree-specific scanner hypothesis, but every one of its numbers mixed the
%   surviving mechanisms together. Each pair now varies one thing:
%
%     fileOpenShare          Near 1 on a host means the BYTES are free and the
%                            cost is in opening - a filter driver, a scanner,
%                            a permission check. Well under 1 means the cost
%                            is reading, which is bandwidth or a device.
%     vectorPerElementRatio  Near 1 means the memory subsystem keeps up and
%                            the per-operation overhead dominates. Well above
%                            1 on one host only means allocation, page
%                            faulting or bandwidth is that host's constraint,
%                            and it is also where a thread-count difference
%                            would show, so read computeThreads with it.
%     validationShare        How much of a call is the arguments block rather
%                            than the call itself. If this is much larger on
%                            one host, the penalty is in the VALIDATION
%                            machinery - many small allocations and calls -
%                            and the carried optimisation items in the
%                            handover header are the direct remedy. If it is
%                            the same on both while callInCpuSteps differs,
%                            the cost is bare dispatch and no change in this
%                            toolbox can reach it.
%
%   RUN IT ON BOTH MACHINES AND COMPARE THE SAME FIELD - fileRatio, the three
%   *Share* and *Ratio* fields and the two *InCpuSteps* fields, never the raw
%   seconds. A single figure from one
%   machine says nothing, and a raw figure from two different machines says
%   something false, which is the whole of O21.
%
% ACCURACY
%   Not applicable; this function measures elapsed time and computes no
%   geodetic quantity. Times are medians over Repeat trials, and a loaded
%   machine will show more.
%
% ERRORS
%   referenceSystem:probePlatformCost:scratchNotWritable
%
% WARNINGS
%   referenceSystem:probePlatformCost:scratchIsAlsoScanned   Raised on Windows
%       when ScratchDir was left at tempdir, which resolves under the user
%       profile there and is scanned like the working tree. fileRatio then
%       compares two scanned locations and returns about 1 whichever way the
%       question would have gone, which is worse than no measurement because
%       it looks like one.
%
% EXAMPLE
%   result = probePlatformCost(ScratchDir = "C:\temp\rsProbe")
%   fprintf('file ratio %.2f, call %.1f us\n', result.fileRatio, ...
%       result.callOverhead);
%
% KEYWORDS
%   performance, platform, file system, antivirus, call overhead, diagnosis
%
% See also PROFILEROTATIONCALL, RUNTESTSUITE.
%
% -------------------------------------------------------------------------
% referenceSystem v2.3
% Developed by Matthias Weigelt with the assistance of Claude Opus 5 (Anthropic)
% Created: 2026-07-30 18:40 (CEST, UTC+02:00)
% -------------------------------------------------------------------------

    arguments
        % "" AND NOT tempdir: the D113 idiom, so an OMISSION can be told
        % apart from a deliberate choice. The warning below fires only on
        % the omission, and a caller who names tempdir on purpose is not
        % second-guessed.
        options.ScratchDir (1,1) string = ""
        options.Repeat (1,1) double {mustBePositive} = 3
    end

    packageFolder = fileparts(which('referenceSystem.toolboxVersion'));
    sourceFile = dir(fullfile(packageFolder, '*.m'));
    sourcePath = fullfile({sourceFile.folder}, {sourceFile.name});

    % THE DEFAULT SCRATCH IS THE WRONG PLACE ON WINDOWS AND THE PROBE SAYS SO
    % RATHER THAN RETURNING A CONFIDENT 1.0. tempdir on PCWIN64 resolves under
    % the user profile - AppData\Local\Temp - which the same real-time scanner
    % walks as Documents does. A fileRatio measured between two scanned
    % locations is near 1 whether or not scanning is the cost, so the default
    % can produce exactly the reassuring answer that means nothing. On Linux
    % tempdir is /tmp and the default is fine.
    scratchGiven = options.ScratchDir ~= "";
    if ~scratchGiven
        options.ScratchDir = string(tempdir);
    end
    if ~scratchGiven && computer("arch") == "win64"
        warning('referenceSystem:probePlatformCost:scratchIsAlsoScanned', ...
            ['ScratchDir was left at tempdir, which on this platform sits ', ...
            'under the user profile (%s) - the same tree a real-time ', ...
            'scanner walks. fileRatio will then compare two scanned ', ...
            'locations and come back near 1 whether or not scanning is the ', ...
            'cost. Pass ScratchDir explicitly, pointing at a path that is ', ...
            'excluded or on another volume, or the file measurement cannot ', ...
            'answer its question.'], options.ScratchDir);
    end

    scratch = fullfile(options.ScratchDir, "rsProbe");
    if ~isfolder(scratch)
        [made, message] = mkdir(scratch);
        if ~made
            error('referenceSystem:probePlatformCost:scratchNotWritable', ...
                'Cannot create "%s": %s', scratch, message);
        end
    end
    removeScratch = onCleanup(@() localRemove(scratch));
    for k = 1:numel(sourcePath)
        copyfile(sourcePath{k}, scratch);
    end
    scratchFile = dir(fullfile(scratch, '*.m'));
    scratchPath = fullfile({scratchFile.folder}, {scratchFile.name});

    result.fileReadHome = localMedian(@() localReadAll(sourcePath), ...
        options.Repeat);
    result.fileReadScratch = localMedian(@() localReadAll(scratchPath), ...
        options.Repeat);
    result.fileRatio = result.fileReadHome/result.fileReadScratch;

    % ONE EPOCH, MANY CALLS: this measures the wrapper and not the arithmetic.
    % TWO EPOCHS, because earthRotationAngle takes UT1 and REFUSES any other
    % scale rather than substituting one - so the UT1 epoch is built directly
    % instead of converted, which also keeps the D113 warning out of a timed
    % loop.
    epoch = referenceSystem.daySecondToEpoch([60310 43200], "UTC");
    epochUt1 = referenceSystem.daySecondToEpoch([60310 43200], "UT1");
    callCount = 2000;
    result.callOverhead = 1e6*localMedian( ...
        @() localCallLoop(epoch, callCount), options.Repeat)/callCount;

    result.mexOverhead = 1e6*localMedian( ...
        @() localMexLoop(epochUt1, callCount), options.Repeat)/callCount;

    % THE MACHINE'S OWN SPEED UNIT. Bare scalar arithmetic: no file, no
    % dispatch, no library, nothing threaded. Dividing the call costs by this
    % turns "microseconds on my computer" into "how many elementary steps a
    % call is worth here", which is the only form in which two different
    % computers can be compared at all.
    stepCount = 2e6;
    result.cpuScalarStep = 1e6*localMedian( ...
        @() localScalarLoop(stepCount), options.Repeat)/stepCount;
    result.cpuVectorOp = localMedian(@localVectorOp, options.Repeat);

    result.callInCpuSteps = result.callOverhead/result.cpuScalarStep;
    result.mexInCpuSteps = result.mexOverhead/result.cpuScalarStep;

    % THREE DISCRIMINATING PAIRS (rev. 1.197). The first probe established
    % the SHAPE of the difference - a faster core surrounded by slower
    % everything - and eliminated the tree-specific scanner. It could not say
    % WHICH of the three surviving mechanisms is at work, because each of its
    % measurements mixed them. Each pair below varies one thing and holds the
    % rest, so the ratio BETWEEN the two members is the discriminator and no
    % cross-machine comparison of an absolute figure is needed.
    result.fileOpenOnly = localMedian(@() localOpenAll(sourcePath), ...
        options.Repeat);
    result.fileOpenShare = result.fileOpenOnly/result.fileReadHome;

    result.vectorOpSmall = localMedian(@() localVectorOfSize(1e4), ...
        options.Repeat);
    result.vectorOpLarge = localMedian(@() localVectorOfSize(4e6), ...
        options.Repeat);
    result.vectorPerElementRatio = ...
        (result.vectorOpLarge/4e6)/(result.vectorOpSmall/1e4);

    callCount = 20000;
    result.callBare = 1e6*localMedian(@() localBareLoop(callCount), ...
        options.Repeat)/callCount;
    result.callValidated = 1e6*localMedian(@() localValidatedLoop(callCount), ...
        options.Repeat)/callCount;
    result.validationShare = result.callValidated/result.callBare;

    result.computeThreads = maxNumCompThreads;
    result.platform = string(computer('arch'));
end

% =========================== local functions ===========================

function elapsed = localReadAll(pathList)
%LOCALREADALL Open and read every file once, discarding the content.

    start = tic;
    for k = 1:numel(pathList)
        text = fileread(pathList{k}); %#ok<NASGU>
    end
    elapsed = toc(start);
end

function elapsed = localCallLoop(epoch, callCount)
%LOCALCALLLOOP A package call with an arguments block, at N = 1.

    start = tic;
    for k = 1:callCount
        value = referenceSystem.convertTimeScale(epoch, "TT"); %#ok<NASGU>
    end
    elapsed = toc(start);
end

function elapsed = localMexLoop(epoch, callCount)
%LOCALMEXLOOP The same shape of call, reaching the gateway.

    start = tic;
    for k = 1:callCount
        value = referenceSystem.earthRotationAngle(epoch); %#ok<NASGU>
    end
    elapsed = toc(start);
end

function elapsed = localScalarLoop(stepCount)
%LOCALSCALARLOOP Bare scalar arithmetic, the machine's own speed unit.

    start = tic;
    total = 0;
    for k = 1:stepCount
        total = total + k*0.5;
    end
    if total < 0
        % Never taken; it exists so the loop cannot be optimised away.
        fprintf('%g', total);
    end
    elapsed = toc(start);
end

function elapsed = localVectorOp()
%LOCALVECTOROP One large elementwise operation: bandwidth and threading.

    elapsed = localVectorOfSize(4e6);
end

function elapsed = localVectorOfSize(elementCount)
%LOCALVECTOROFSIZE One elementwise operation over a chosen length.
%   Small stays in cache and allocates little; large allocates tens of
%   megabytes and touches memory the processor has not seen. Per ELEMENT the
%   two should cost about the same on a machine whose memory subsystem is not
%   the constraint.

    sample = ones(elementCount, 1);
    start = tic;
    scaled = sample*1.5 + 0.25; %#ok<NASGU>
    elapsed = toc(start);
end

function elapsed = localOpenAll(pathList)
%LOCALOPENALL Open and close every file, reading nothing.
%   The difference from localReadAll is the bytes: if opening alone costs
%   nearly as much as opening and reading, the cost is in the OS path - a
%   filter driver, a permission check, a directory walk - and not in I/O.

    start = tic;
    for k = 1:numel(pathList)
        fileId = fopen(pathList{k}, 'r');
        if fileId > 0
            fclose(fileId);
        end
    end
    elapsed = toc(start);
end

function elapsed = localBareLoop(callCount)
%LOCALBARELOOP A function call with no arguments block at all.

    start = tic;
    for k = 1:callCount
        value = localBare(k); %#ok<NASGU>
    end
    elapsed = toc(start);
end

function value = localBare(x)
%LOCALBARE The cheapest call this file can make.
    value = x + 1;
end

function elapsed = localValidatedLoop(callCount)
%LOCALVALIDATEDLOOP The same call behind an arguments block.

    start = tic;
    for k = 1:callCount
        value = localValidated(k); %#ok<NASGU>
    end
    elapsed = toc(start);
end

function value = localValidated(x, options)
%LOCALVALIDATED The same work behind the validation this toolbox uses.
%   Deliberately shaped like the package's own signatures: a size-and-class
%   constrained positional, a validator function, and a name-value with a
%   mustBeMember domain - the three things every hot-path function in
%   referenceSystem carries.

    arguments
        x (1,1) double {mustBeReal, mustBeFinite}
        options.Scale (1,1) string {mustBeMember(options.Scale, ...
            ["TT", "TAI", "UTC"])} = "TT"
    end

    value = x + 1 + strlength(options.Scale)*0;
end

function value = localMedian(work, repeat)
%LOCALMEDIAN Median of Repeat trials, discarding nothing.

    sample = zeros(repeat, 1);
    for k = 1:repeat
        sample(k) = work();
    end
    value = median(sample);
end

function localRemove(scratch)
%LOCALREMOVE Take the copies away again.

    if isfolder(scratch)
        rmdir(scratch, 's');
    end
end
