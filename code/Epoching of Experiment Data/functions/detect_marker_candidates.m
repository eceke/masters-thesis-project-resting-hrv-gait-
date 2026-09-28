function candidates = detect_marker_candidates(accData, fs, cfg)
% finds ONLY candidate locations from the data.

    arguments
        accData (:,:) double
        fs (1,1) double
        cfg (1,1) struct
    end
    
    if isfield(cfg, 'advanced_verbose') && cfg.advanced_verbose
        fprintf('[DETECT] Candidate positions are being determined...\n');
        fprintf('  ACC data size: %d x %d\n', size(accData,1), size(accData,2));
        fprintf('  Sampling frequency: %.1f Hz\n', fs);
    end
    
    % === 1. MAGNITUDE CALCULATION ===
    % Check the parameters in the Config file.
    if isfield(cfg, 'detect_useMagnitude') && cfg.detect_useMagnitude
        detectionSignal = sqrt(sum(accData.^2, 2));
    else
        detectionSignal = accData(:,1); % X axis
    end
    
    % === 2. SIGNAL PROCESSING ===
    smoothWindow = 0.3; % Default value
    if isfield(cfg, 'detect_smoothWindow')
        smoothWindow = cfg.detect_smoothWindow;
    end
    
    smoothSamples = round(smoothWindow * fs);
    if smoothSamples > 1 && smoothSamples < length(detectionSignal)
        detectionSignal = simple_smooth(detectionSignal, smoothSamples);
    end
    
    % Time vector
    t = (0:size(accData,1)-1)' / fs;
    
    % === 3. FIND LOCAL MINIUMS ===
    invertedSignal = -detectionSignal;
    
    % Prominence calculation
    signalRange = range(detectionSignal);
    minProminenceFactor = 0.10; % Default value
    if isfield(cfg, 'detect_minProminenceFactor')
        minProminenceFactor = cfg.detect_minProminenceFactor;
    end
    
    minProminence = signalRange * minProminenceFactor;
    
    % Width parameters
    minWidthSeconds = 0.3;
    maxWidthSeconds = 6.0;
    if isfield(cfg, 'detect_minWidthSeconds')
        minWidthSeconds = cfg.detect_minWidthSeconds;
    end
    if isfield(cfg, 'detect_maxWidthSeconds')
        maxWidthSeconds = cfg.detect_maxWidthSeconds;
    end
    
    minWidthSamples = max(1, round(minWidthSeconds * fs));
    maxWidthSamples = round(maxWidthSeconds * fs);
    
    try
        [pks, locs, widths, proms] = findpeaks(...
            invertedSignal, ...
            'MinPeakProminence', minProminence, ...
            'MinPeakWidth', minWidthSamples, ...
            'MaxPeakWidth', maxWidthSamples, ...
            'WidthReference', 'halfprom');
        
    catch ME
        warning(ME.identifier, '%s', ME.message);
        candidates = [];
        return;
    end
    
    % If no candidate was found
    if isempty(locs)
        if isfield(cfg, 'advanced_verbose') && cfg.advanced_verbose
            fprintf('[DETECT] No candidates were found\n');
        end
        candidates = [];
        return;
    end
    
    % === 4. MERGE VERY CLOSE CANDIDATES ===
    mergeThreshold = 4.0; % Default value
    if isfield(cfg, 'detect_mergeThreshold')
        mergeThreshold = cfg.detect_mergeThreshold;
    end
    
    mergeSamples = round(mergeThreshold * fs);
    [locs, widths, proms] = merge_close_candidates(locs, widths, proms, mergeSamples);
    
    % === 5. REFINE: FIND THE EXACT BOTTOM POINT ON THE AXIS ===
    refineAxis = 'X'; % Default value
    if isfield(cfg, 'detect_refineAxis')
        refineAxis = upper(cfg.detect_refineAxis);
    end
    
    if size(accData, 2) >= 3
        switch refineAxis
            case 'X'
                refineSignal = accData(:,1);
            case 'Y'
                refineSignal = accData(:,2);
            case 'Z'
                refineSignal = accData(:,3);
            otherwise
                refineSignal = accData(:,1);
        end
    else
        refineSignal = accData(:,1);
    end
    
    refineWindow = round(0.5 * fs);
    refinedLocs = zeros(size(locs));
    
    for i = 1:length(locs)
        idxStart = max(1, locs(i) - refineWindow);
        idxEnd = min(length(refineSignal), locs(i) + refineWindow);
        window = refineSignal(idxStart:idxEnd);
        [~, minIdx] = min(window);
        refinedLocs(i) = idxStart + minIdx - 1;
    end
    locs = refinedLocs;
    
    % === 6. CREATE A SIMPLE CANDIDATE STRUCTURE. ===
    candidates = struct();
    
    for i = 1:length(locs)
        idx = locs(i);
        
        % Time and index information only
        candidates(i).timeSec = t(idx);
        candidates(i).sampleIndex = idx;
    end
    
    % Clean the empty ones
    if ~isempty(candidates)
        emptyIdx = arrayfun(@(x) isempty(x.sampleIndex), candidates);
        candidates(emptyIdx) = [];
    end
    
    if isfield(cfg, 'advanced_verbose') && cfg.advanced_verbose
        fprintf('[DETECT] %d candidates was found.\n', length(candidates));
        if length(candidates) > 0
            fprintf('  Top 5 candidates time: ');
            for i = 1:min(5, length(candidates))
                fprintf('%.1f s ', candidates(i).timeSec);
            end
            fprintf('\n');
        end
    end
    
end

%% EXTRA FUNCTIONS 
function y = simple_smooth(x, windowSize)
    if windowSize < 3 || windowSize >= length(x)
        y = x;
        return;
    end
    
    kernel = ones(1, windowSize) / windowSize;
    y = conv(x, kernel, 'same');
    
    halfWin = floor(windowSize/2);
    n = length(x);
    
    for i = 1:halfWin
        if i+halfWin <= n
            y(i) = mean(x(1:i+halfWin));
        end
        if n-i-halfWin+1 >= 1
            y(n-i+1) = mean(x(n-i-halfWin+1:n));
        end
    end
end

function [mergedLocs, mergedWidths, mergedProms] = merge_close_candidates(locs, widths, proms, mergeThreshold)
    if isempty(locs)
        mergedLocs = []; mergedWidths = []; mergedProms = [];
        return;
    end
    
    mergedLocs = [];
    mergedWidths = [];
    mergedProms = [];
    
    i = 1;
    while i <= length(locs)
        currentLoc = locs(i);
        clusterLocs = currentLoc;
        clusterWidths = widths(i);
        clusterProms = proms(i);
        
        j = i + 1;
        while j <= length(locs) && (locs(j) - currentLoc) <= mergeThreshold
            clusterLocs = [clusterLocs, locs(j)];
            clusterWidths = [clusterWidths, widths(j)];
            clusterProms = [clusterProms, proms(j)];
            j = j + 1;
        end
        
        [bestProm, bestIdx] = max(clusterProms);
        mergedLocs = [mergedLocs, clusterLocs(bestIdx)];
        mergedWidths = [mergedWidths, clusterWidths(bestIdx)];
        mergedProms = [mergedProms, bestProm];
        
        i = j;
    end
end

function dipDuration = calculate_simple_dip_duration(signal, minIdx, fs)
    if minIdx < 1 || minIdx > length(signal)
        dipDuration = 0;
        return;
    end
    
    minVal = signal(minIdx);
    threshold = minVal + 0.5 * abs(minVal);
    
    maxSearch = round(3 * fs);
    
    % Left side
    leftIdx = minIdx;
    for offset = 1:min(maxSearch, minIdx-1)
        if signal(minIdx - offset) < threshold
            leftIdx = minIdx - offset;
        else
            break;
        end
    end
    
    % Right Side
    rightIdx = minIdx;
    for offset = 1:min(maxSearch, length(signal)-minIdx)
        if signal(minIdx + offset) < threshold
            rightIdx = minIdx + offset;
        else
            break;
        end
    end
    
    dipDuration = (rightIdx - leftIdx) / fs;
end