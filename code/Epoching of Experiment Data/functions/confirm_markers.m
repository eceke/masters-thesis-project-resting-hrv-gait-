function [confirmedMarkers, logInfo] = confirm_markers(selectedMarkers, candidates, fs, cfg)
% Interactive marker verification and correction

    arguments
        selectedMarkers (:,1) struct
        candidates (:,1) struct
        fs (1,1) double
        cfg (1,1) struct
    end
    
    % Log information structure
    logInfo = struct();
    logInfo.userVerified = false;
    logInfo.correctionHistory = struct();
    logInfo.numIterations = 0;
    logInfo.maxIterations = cfg.interactive.maxIterations;
    
    % Marker labels (for 11 markers)
    markerLabels = {
        'RS_EO1_end';
        'RS_EC_end';
        'RS_EO2_end';
        'BW_1KMH_start';
        'BW_1KMH_end';
        'FWW_1KMH_start';
        'FWW_1KMH_end';
        'BW_4KMH_start';
        'BW_4KMH_end';
        'FWW_4KMH_start';
        'FWW_4KMH_end';
    };
    
    % Get candidate times
    if ~isempty(candidates)
        candidateTimes = [candidates.timeSec];
    else
        candidateTimes = [];
    end
    
    % Interactive correction loop
    iteration = 0;
    while iteration < cfg.interactive.maxIterations
        iteration = iteration + 1;
        logInfo.numIterations = iteration;
        
        fprintf('\n=== MARKER VERIFICATION (Round %d/%d) ===\n', ...
            iteration, cfg.interactive.maxIterations);
        
        % 6.1 - Show markers
        show_markers(selectedMarkers, markerLabels);
        
        % 6.2 - Confirmation question
        response = input('Are markers correct? (Y/N): ', 's');
        
        if strcmpi(response, 'Y') || strcmpi(response, 'E')  % E for Turkish keyboard
            % User approved
            logInfo.userVerified = true;
            logInfo.correctionHistory(iteration).action = 'accepted';
            fprintf('✓ Markers confirmed.\n');
            break;
        end
        
        % 6.3 - If wrong: correction mode
        fprintf('\n--- MARKER CORRECTION ---\n');
        
        % Which markers are wrong?
        wrongStr = input('Which markers are wrong? (e.g., 2,5,11): ', 's');
        
        % Convert string to number list
        wrongIndices = str2num(wrongStr); %#ok<ST2NM>
        if isempty(wrongIndices)
            fprintf('Invalid input. Please enter numbers (e.g., 2,5,11)\n');
            continue;
        end
        
        % Sort from small to large
        wrongIndices = sort(wrongIndices(:)');
        
        % Save correction history
        logInfo.correctionHistory(iteration).wrongIndices = wrongIndices;
        logInfo.correctionHistory(iteration).corrections = struct();
        
        % Correct each wrong marker
        for iCorr = 1:length(wrongIndices)
            idx = wrongIndices(iCorr);
            
            if idx < 1 || idx > 11
                fprintf('  Invalid marker index: %d (should be 1-11)\n', idx);
                continue;
            end
            
            fprintf('\n  %d. marker (%s) correcting...\n', ...
                idx, markerLabels{idx});
            fprintf('  Current time: %.2f s\n', selectedMarkers(idx).timeSec);
            
            % Get approximate time from user
            userTime = input('  Enter approximate tSec: ');
            
            if isempty(userTime) || ~isnumeric(userTime) || userTime < 0
                fprintf('  Invalid time. Skipped.\n');
                continue;
            end
            
            % Is there a candidate within ±1 second?
            if ~isempty(candidateTimes)
                searchWin = cfg.interactive.searchWindow;
                candidateDiff = abs(candidateTimes - userTime);
                closeCandidates = find(candidateDiff <= searchWin);
                
                if ~isempty(closeCandidates)
                    % Select the closest candidate
                    [~, bestIdx] = min(candidateDiff(closeCandidates));
                    selectedCandidate = closeCandidates(bestIdx);
                    
                    % NEW CODE: convert candidates struct to selectedMarkers format
                    candidateToUse = struct();
                    candidateToUse.timeSec = candidates(selectedCandidate).timeSec;
                    candidateToUse.sampleIndex = candidates(selectedCandidate).sampleIndex;
                    
                    % Keep other fields of selectedMarkers (confidences, etc.)
                    % Only update timeSec and sampleIndex
                    selectedMarkers(idx).timeSec = candidateToUse.timeSec;
                    selectedMarkers(idx).sampleIndex = candidateToUse.sampleIndex;
                    
                    % Slightly lower confidence (manual intervention occurred)
                    selectedMarkers(idx).selectConfidence = selectedMarkers(idx).selectConfidence * 0.8;
                    
                    % Manual override flag (but from candidate)
                    if ~isfield(selectedMarkers, 'manualOverride')
                        [selectedMarkers.manualOverride] = deal(false);
                    end
                    selectedMarkers(idx).manualOverride = false; % Candidate exists, not fully manual
                    
                    fprintf('  ✓ Candidate found: %.2f s (conf: %.2f)\n', ...
                        selectedMarkers(idx).timeSec, selectedMarkers(idx).selectConfidence);
                    
                    % Log
                    logInfo.correctionHistory(iteration).corrections(iCorr).idx = idx;
                    logInfo.correctionHistory(iteration).corrections(iCorr).oldTime = userTime;
                    logInfo.correctionHistory(iteration).corrections(iCorr).newTime = selectedMarkers(idx).timeSec;
                    logInfo.correctionHistory(iteration).corrections(iCorr).method = 'candidate_match';
                    
                else
                    % No candidate - DIRECT OVERRIDE
                    selectedMarkers(idx).timeSec = userTime;
                    selectedMarkers(idx).sampleIndex = round(userTime * fs);
                    selectedMarkers(idx).selectConfidence = 0.1;  % Low confidence
                    
                    % Add manual override flag
                    if ~isfield(selectedMarkers, 'manualOverride')
                        [selectedMarkers.manualOverride] = deal(false);
                    end
                    selectedMarkers(idx).manualOverride = true;
                    
                    fprintf('  ⚠ Manual override: %.2f s (conf: 0.1)\n', userTime);
                    
                    % Log
                    logInfo.correctionHistory(iteration).corrections(iCorr).idx = idx;
                    logInfo.correctionHistory(iteration).corrections(iCorr).oldTime = [];
                    logInfo.correctionHistory(iteration).corrections(iCorr).newTime = userTime;
                    logInfo.correctionHistory(iteration).corrections(iCorr).method = 'manual_override';
                end
            else
                % No candidates at all - DIRECT OVERRIDE
                selectedMarkers(idx).timeSec = userTime;
                selectedMarkers(idx).sampleIndex = round(userTime * fs);
                selectedMarkers(idx).selectConfidence = 0.1;
                
                if ~isfield(selectedMarkers, 'manualOverride')
                    [selectedMarkers.manualOverride] = deal(false);
                end
                selectedMarkers(idx).manualOverride = true;
                
                fprintf('  ⚠ Manual override: %.2f s (conf: 0.1)\n', userTime);
                
                % Log
                logInfo.correctionHistory(iteration).corrections(iCorr).idx = idx;
                logInfo.correctionHistory(iteration).corrections(iCorr).oldTime = [];
                logInfo.correctionHistory(iteration).corrections(iCorr).newTime = userTime;
                logInfo.correctionHistory(iteration).corrections(iCorr).method = 'manual_override';
            end
        end
        
        % 6.4 - Check marker ordering
        markerTimes = [selectedMarkers.timeSec];
        if any(diff(markerTimes) <= 0)
            fprintf('\n⚠ Warning: Marker times are not in increasing order!\n');
            fprintf('  Please check the times.\n');
        end
        
        fprintf('\n--- Correction completed ---\n');
        
        % Max iteration check
        if iteration >= cfg.interactive.maxIterations
            fprintf('\n⚠ Maximum correction rounds reached (%d).\n', cfg.interactive.maxIterations);
            response = input('Continue? (Y/N): ', 's');
            if strcmpi(response, 'Y') || strcmpi(response, 'E')
                cfg.interactive.maxIterations = cfg.interactive.maxIterations + 1;
            else
                fprintf('Using the last markers.\n');
                break;
            end
        end
    end
    
    % Assign final markers
    confirmedMarkers = selectedMarkers;
    
    % Complete log
    logInfo.finalMarkers = confirmedMarkers;
    logInfo.markerLabels = markerLabels;
    
    fprintf('\n=== INTERACTIVE VERIFICATION COMPLETED ===\n');
    fprintf('  Total rounds: %d\n', iteration);
    fprintf('  User approval: %s\n', string(logInfo.userVerified));
    
end

%% Helper function
function show_markers(markers, labels)
    fprintf('\n--- SELECTED MARKERS ---\n');
    for i = 1:length(markers)
        conf = markers(i).selectConfidence;
        manualFlag = '';
        if isfield(markers, 'manualOverride') && markers(i).manualOverride
            manualFlag = ' [MANUAL]';
        end
        fprintf('%2d) %-20s : %8.2f s (conf: %.2f)%s\n', ...
            i, labels{i}, markers(i).timeSec, conf, manualFlag);
    end
    fprintf('\n');
end