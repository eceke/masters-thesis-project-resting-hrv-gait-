function [selectedMarkers, selectionInfo] = select_markers_sequence_based(...
    candidates, accPhys, gyroPhys, fs, cfg)
% The candidate selects the markers that match the template.

    arguments
        candidates (:,1) struct 
        accPhys (:,:) double
        gyroPhys (:,:) double
        fs (1,1) double
        cfg (1,1) struct
    end
    
    if cfg.advanced.verbose
        fprintf('[SELECT] Marker selection begins...\n');
        fprintf('  Number of candidates: %d\n', length(candidates));
    end
    
    % === 1. Preparing ACC Signal ===
    accSignal = sqrt(sum(accPhys.^2, 2));
    
    % === 2. CALCULATE ALL INFORMATION FROM SCRATCH FOR EACH CANDIDATE ===
    enrichedCandidates = struct();
    
    for i = 1:length(candidates)
        cand = candidates(i);
        
        % === INFORMATION CALCULATED IN SELECT ===
        % 1. Symmetric Prominence (70% symmetry, 30% depth)
        symProm = calculate_symmetric_prominence_select(cand, accSignal, fs);
        
        % 2. Depth Duration
        dipDuration = calculate_dip_duration_select(cand, accPhys, fs);
        dipDurationScore = score_dip_duration(dipDuration);
        
        % 3. Gyro Pattern Score
        if ~isempty(gyroPhys)
            gyroScore = check_gyro_pattern_select(cand, gyroPhys, fs, cfg);
        else
            gyroScore = 0.5;
        end
        
        % === SELECT CONFIDENCE CALCULATION ===
        % Weights: prominence(%60), depth(%20), gyro(%20)
        selectConfidence = 0.6 * symProm + 0.2 * dipDurationScore + 0.2 * gyroScore;
        
        % === CREATE A NEW STRUCTURE ===
        enrichedCandidates(i).timeSec = cand.timeSec;
        enrichedCandidates(i).sampleIndex = cand.sampleIndex;
        enrichedCandidates(i).selectConfidence = selectConfidence;
        enrichedCandidates(i).symmetricProminence = symProm;
        enrichedCandidates(i).dipDuration = dipDuration;
        enrichedCandidates(i).dipDurationScore = dipDurationScore;
        enrichedCandidates(i).gyroPatternScore = gyroScore;
        enrichedCandidates(i).minValue = accSignal(cand.sampleIndex);
        enrichedCandidates(i).neighborCount = 0;
        enrichedCandidates(i).neighborPenalty = 1.0;
    end
    
    % === 3. NEIGHBORHOOD ANALYSIS ===
    if length(enrichedCandidates) >= 2
        times = [enrichedCandidates.timeSec];
        for i = 1:length(enrichedCandidates)
            neighborCount = 0;
            for j = 1:length(enrichedCandidates)
                if i == j, continue; end
                if abs(times(i) - times(j)) < 3.0
                    neighborCount = neighborCount + 1;
                end
            end
            enrichedCandidates(i).neighborCount = neighborCount;
            if neighborCount > 0
                penalty = 0.9 ^ neighborCount;
                enrichedCandidates(i).neighborPenalty = penalty;
                enrichedCandidates(i).selectConfidence = enrichedCandidates(i).selectConfidence * penalty;
            end
        end
    end
    
    % === 4. CONFIDENCE FILTER ===
    minConfidence = 0.2;
    selectConfs = [enrichedCandidates.selectConfidence];
    validIdx = selectConfs >= minConfidence;
    filteredCandidates = enrichedCandidates(validIdx);
    
    if cfg.advanced.verbose
        fprintf('  After filtration: %d candidate\n', length(filteredCandidates));
    end
    
    % === 5. DYNAMIC PROGRAMMING FOR SELECTION ===
    [selectedIdx, selectionScores] = dynamic_selection(filteredCandidates, cfg, fs);
    
    % === 6. PREPARE THE SELECTED MARKERS ===
    selectedMarkers = filteredCandidates(selectedIdx);
    
    % === 7. SELECTION INFO ===
    selectionInfo = struct();
    selectionInfo.method = 'dynamic_programming_with_select_confidence';
    selectionInfo.selectedIndices = selectedIdx;
    selectionInfo.scores = selectionScores;
    selectionInfo.meanSelectConfidence = mean([selectedMarkers.selectConfidence]);
    selectionInfo.minSelectConfidence = min([selectedMarkers.selectConfidence]);
    selectionInfo.nCandidates = length(filteredCandidates);
    
    if cfg.advanced.verbose
        fprintf('[SELECT] The selection is over.:\n');
        for i = 1:length(selectedMarkers)
            fprintf('  %2d. %6.1f s (conf: %.2f, sym: %.2f, gyro: %.2f)\n', ...
                i, selectedMarkers(i).timeSec, ...
                selectedMarkers(i).selectConfidence, ...
                selectedMarkers(i).symmetricProminence, ...
                selectedMarkers(i).gyroPatternScore);
        end
    end
    
    % Export candidate diagnostics to the MATLAB base workspace
    assignin('base', 'enrichedCandidates_debug', enrichedCandidates);
    assignin('base', 'filteredCandidates_debug', filteredCandidates);
    assignin('base', 'accSignal_debug', accSignal);
    
    if cfg.advanced.verbose
        fprintf('[DEBUG] Variables were saved to the workspace:\n');
        fprintf('  enrichedCandidates_debug: %d aday\n', length(enrichedCandidates));
        fprintf('  filteredCandidates_debug: %d aday\n', length(filteredCandidates));
    end

end

%% ===== SELECT CUSTOM CALCULATION FUNCTIONS =====

function symProm = calculate_symmetric_prominence_select(candidate, accSignal, fs)
    % SYMMETRICAL PROMINENCE: 70% symmetry + 30% depth
    
    idx = candidate.sampleIndex;
    
    if idx < 1 || idx > length(accSignal)
        symProm = 0;
        return;
    end
    
    % Window: 2 seconds
    window = round(2.0 * fs);
    
    % Left
    leftStart = max(1, idx - window);
    leftSignal = accSignal(leftStart:idx-1);
    if isempty(leftSignal)
        leftMax = accSignal(idx);
    else
        leftMax = max(leftSignal);
    end
    
    % Right
    rightEnd = min(length(accSignal), idx + window);
    rightSignal = accSignal(idx+1:rightEnd);
    if isempty(rightSignal)
        rightMax = accSignal(idx);
    else
        rightMax = max(rightSignal);
    end
    
    % === 1. SYMMETRY RATIO (%70) ===
    if leftMax > 0 && rightMax > 0
        symmetryRatio = min(leftMax, rightMax) / max(leftMax, rightMax);
    else
        symmetryRatio = 0;
    end
    
    % === 2. DEPTH SCORE (%30) ===
    dipVal = accSignal(idx);
    avgShoulder = (leftMax + rightMax) / 2;
    
    if avgShoulder > dipVal && avgShoulder > 0
        depthScore = (avgShoulder - dipVal) / avgShoulder;
    else
        depthScore = 0;
    end
    
    % === 3. FINAL SCORE ===
    symProm = (symmetryRatio * 0.7) + (depthScore * 0.3);
end

function [dipDuration, dipLeft, dipRight] = calculate_dip_duration_select(candidate, accPhys, fs)
    % DEPTH DURATION ALGORITHM
    
    % 1. ACCX data
    accX = accPhys(:, 1);
    idx = candidate.sampleIndex;
    
    % 2. Parameters
    returnLevel = 0.85;        % g, constant
    stabilitySamples = 15;     % 15 sequential example
    maxSearchSamples = round(2.5 * fs);  % 2.5 seconds
    
    % 3. Scan the right side (find dipRight)
    dipRight = find_boundary(accX, idx, +1, returnLevel, stabilitySamples, maxSearchSamples);
    
    % 4. Scan the left side (dipLeft find)
    dipLeft = find_boundary(accX, idx, -1, returnLevel, stabilitySamples, maxSearchSamples);
    
    % 5. Calculate the depth (seconds)
    dipDuration = (dipRight - dipLeft) / fs;
    
    % 6. Maximum limit (5 seconds)
    if dipDuration > 5.0
        dipDuration = 5.0;
    end
end

function boundary = find_boundary(accX, startIdx, direction, returnLevel, stabilitySamples, maxSearch)
    % SCAN BY DIRECTION: +1 = right, -1 = left
    
    n = length(accX);
    boundary = startIdx;  % Default: starting point if not found.
    
    % Screening limits
    if direction == 1  % Right
        endIdx = min(n, startIdx + maxSearch);
        searchRange = startIdx+1 : endIdx;
    else  % Left
        endIdx = max(1, startIdx - maxSearch);
        searchRange = startIdx-1 : -1 : endIdx;
    end
    
    % Check every point
    for i = 1:length(searchRange)
        currentIdx = searchRange(i);
        
        % At this point, is ACCX ≥ returnLevel?
        if accX(currentIdx) >= returnLevel
            
            % Stability check: the next 15 samples
            if check_stability(accX, currentIdx, direction, returnLevel, stabilitySamples)
                boundary = currentIdx;
                return;  % Found
            end
        end
    end
    
    % Not found: Set to max limit
    if direction == 1
        boundary = min(n, startIdx + maxSearch);
    else
        boundary = max(1, startIdx - maxSearch);
    end
end

function stable = check_stability(accX, startIdx, direction, returnLevel, stabilitySamples)
    % Are all 15 consecutive examples ≥ returnLevel?
    
    n = length(accX);
    stable = true;
    
    for k = 0:stabilitySamples-1
        if direction == 1  % Right
            checkIdx = startIdx + k;
        else  % Left
            checkIdx = startIdx - k;
        end
        
        % Border control
        if checkIdx < 1 || checkIdx > n
            stable = false;
            return;
        end
        
        % Value control
        if accX(checkIdx) < returnLevel
            stable = false;
            return;
        end
    end
end

function score = score_dip_duration(duration)
    % SCORING:
% < 0.5s: 0.2 (Very bad)
% 0.5-1.0s: 0.5 (Bad)
% 1.0-3.0s: 1.0 (Ideal)
% 3.0-4.0s: 0.8 (Average)
% 4.0-5.0s: 0.4 (Bad)
% ≥ 5.0s: 0.2 (Very bad)
    
    if duration < 0.5
        score = 0.2;
    elseif duration < 1.0
        score = 0.5;
    elseif duration < 3.0
        score = 1.0;
    elseif duration < 4.0
        score = 0.8;
    elseif duration < 5.0
        score = 0.4;
    else
        score = 0.2;
    end
end

function gyroScore = check_gyro_pattern_select(candidate, gyroPhys, fs, cfg)
    % GYRO PATTERN: First half Z-peak/Y-trough, Second half Y-peak/Z-trough
    
    windowSec = 1.2;
    windowSamples = round(windowSec * fs);
    idx = candidate.sampleIndex;
    
    % Window
    startIdx = max(1, idx - windowSamples);
    endIdx = min(size(gyroPhys,1), idx + windowSamples);
    
    if (endIdx - startIdx) < (0.5 * windowSamples)
        gyroScore = 0;
        return;
    end
    
    gyroWindow = gyroPhys(startIdx:endIdx, :);
    n = size(gyroWindow, 1);
    mid = floor(n / 2);
    
    if mid < 10
        gyroScore = 0;
        return;
    end
    
    % First half: Z peak (Λ), Y trough (V)
    z_first = gyroWindow(1:mid, 3);
    y_first = gyroWindow(1:mid, 2);
    
    [z_first_max, z_max_idx] = max(z_first);
    z_first_min_before = min(z_first(1:z_max_idx));
    z_first_min_after = min(z_first(z_max_idx:end));
    
    [y_first_min, y_min_idx] = min(y_first);
    y_first_max_before = max(y_first(1:y_min_idx));
    y_first_max_after = max(y_first(y_min_idx:end));
    
    first_half_ok = (z_first_max > z_first_min_before + 1.0) && ...
                    (z_first_max > z_first_min_after + 1.0) && ...
                    (y_first_min < y_first_max_before - 1.0) && ...
                    (y_first_min < y_first_max_after - 1.0);
    
    % Second half: Y peak (Λ), Z trough (V)
    z_second = gyroWindow(mid+1:end, 3);
    y_second = gyroWindow(mid+1:end, 2);
    
    [y_second_max, y2_max_idx] = max(y_second);
    y_second_min_before = min(y_second(1:y2_max_idx));
    y_second_min_after = min(y_second(y2_max_idx:end));
    
    [z_second_min, z2_min_idx] = min(z_second);
    z_second_max_before = max(z_second(1:z2_min_idx));
    z_second_max_after = max(z_second(z2_min_idx:end));
    
    second_half_ok = (y_second_max > y_second_min_before + 1.0) && ...
                     (y_second_max > y_second_min_after + 1.0) && ...
                     (z_second_min < z_second_max_before - 1.0) && ...
                     (z_second_min < z_second_max_after - 1.0);
    
    % Score
    if first_half_ok && second_half_ok
        gyroScore = 1.0;
    elseif first_half_ok || second_half_ok
        gyroScore = 0.6;
    else
        gyroScore = 0.2;
    end
end

%% ===== DYNAMIC SELECTION ALGORITHM =====

function [selectedIdx, scores] = dynamic_selection(candidates, cfg, fs)
    nCandidates = length(candidates);
    nMarkers = cfg.expectedMarkerCount;
    
    if nCandidates < nMarkers
        [~, sortIdx] = sort([candidates.selectConfidence], 'descend');
        selectedIdx = sortIdx(1:min(nCandidates, nMarkers));
        scores = zeros(1, nMarkers);
        return;
    end
    
    % Dynamic programming tables
    dpScore = -inf(nCandidates, nMarkers);
    dpPrev = zeros(nCandidates, nMarkers, 'int32');
    times = [candidates.timeSec];
    selectConfs = [candidates.selectConfidence];
    
    % === SPECIFIC LIMITATION FOR MARKER 1: 270–350s RANGE ===
    for i = 1:nCandidates
        % Time control for Marker 1
        timePenaltyMarker1 = calculate_marker1_penalty(times(i));
        dpScore(i, 1) = selectConfs(i) - timePenaltyMarker1;
    end
    
    % === Dynamic Programming for Marker 2-11 ===
    for m = 2:nMarkers
        for i = m:nCandidates
            bestScore = -inf;
            bestPrev = 0;
            
            for j = (m-1):(i-1)
                if times(i) <= times(j)
                    continue;
                end
                
                % Time Interval Penalty
                gap = times(i) - times(j);
                timePenalty = calculate_gap_penalty(gap, m-1, m);
                
                % Total score
                totalScore = dpScore(j, m-1) + selectConfs(i) - timePenalty;
                
                if totalScore > bestScore
                    bestScore = totalScore;
                    bestPrev = j;
                end
            end
            
            dpScore(i, m) = bestScore;
            dpPrev(i, m) = bestPrev;
        end
    end
    
    % === FIND THE BEST WAY (WITHOUT INTERVENTION AT THE FINAL MARKER) ===
    [bestScore, bestIdx] = max(dpScore(:, nMarkers));
    
    % Follow the path again.
    selectedIdx = zeros(nMarkers, 1);
    selectedIdx(nMarkers) = bestIdx;
    
    for m = nMarkers:-1:2
        selectedIdx(m-1) = dpPrev(selectedIdx(m), m);
    end
    
    scores = dpScore(selectedIdx, :);
end

%% ===== TIME PENALTY FOR MARKER 1. =====

function penalty = calculate_marker1_penalty(timeSec)
    % MARKER 1: should be in the 270–350 range.
    
    if timeSec >= 270 && timeSec <= 350
        penalty = 0;  % Ideal range: NO PENALTY
    else
        % Outside of range: penalty based on distance.
        if timeSec < 270
            distance = 270 - timeSec;
        else % timeSec > 350
            distance = timeSec - 350;
        end
        
        if distance <= 20
            penalty = 0.2;  % Light penalty (outside 1-20sec)
        elseif distance <= 60
            penalty = 0.5;  % Medium penalty (outside 21-60sec)
        else
            penalty = 1.0;  % Heavy penalty (outside >60sec)
        end
    end
end

%% ===== TIME INTERVAL PENALTY FOR MARKER PASSES =====

function penalty = calculate_gap_penalty(gap, fromIdx, toIdx)
    % ALLOWED RANGES
    
    % STABLE transitions (widened ranges)
    if (fromIdx == 1 && toIdx == 2)  % 1→2
        allowedMin = 300; allowedMax = 320;
        isStable = true;
    elseif (fromIdx == 2 && toIdx == 3)  % 2→3
        allowedMin = 300; allowedMax = 320;
        isStable = true;
    elseif (fromIdx == 4 && toIdx == 5)  % 4→5
        allowedMin = 80; allowedMax = 130;
        isStable = true;
    elseif (fromIdx == 6 && toIdx == 7)  % 6→7
        allowedMin = 160; allowedMax = 210;
        isStable = true;
    elseif (fromIdx == 8 && toIdx == 9)  % 8→9
        allowedMin = 95; allowedMax = 125;
        isStable = true;
    elseif (fromIdx == 10 && toIdx == 11)  % 10→11
        allowedMin = 170; allowedMax = 300;
        isStable = true;
    
    % UNSTABLE transitions (exact min/max, not widened)
    elseif (fromIdx == 3 && toIdx == 4)  % 3→4
        allowedMin = 227; allowedMax = 420;
        isStable = false;
    elseif (fromIdx == 5 && toIdx == 6)  % 5→6
        allowedMin = 17; allowedMax = 87;
        isStable = false;
    elseif (fromIdx == 7 && toIdx == 8)  % 7→8
        allowedMin = 160; allowedMax = 217;
        isStable = false;
    elseif (fromIdx == 9 && toIdx == 10)  % 9→10
        allowedMin = 16; allowedMax = 58;
        isStable = false;
    else
        % Default (not required) for other transitions
        allowedMin = 100; allowedMax = 200;
        isStable = false;
    end
    
    % === IS IT IN RANGE? ===
    if gap >= allowedMin && gap <= allowedMax
        penalty = 0;  % Ideal: NO PENALTY
    
    % === OUTSIDE RANGE ===
    else
        if gap < allowedMin
            distance = allowedMin - gap;
        else % gap > allowedMax
            distance = gap - allowedMax;
        end
        
        % PENALTY CALCULATION
        if distance <= 20
            % Outside of 1-20s: minor penalty
            if isStable
                penalty = 0.1;  % Smaller penalty for stable
            else
                penalty = 0.15; % A little bigger for Unstable
            end
        elseif distance <= 60
            % Outside 21-60sec: medium penalty
            if isStable
                penalty = 0.3;
            else
                penalty = 0.4;
            end
        elseif distance <= 120
            % Outside 61-120sec: heavy penalty
            if isStable
                penalty = 0.6;
            else
                penalty = 0.7;
            end
        else
            % Outside >120sec: very heavy penalty
            penalty = 1.0;
        end
    end
end