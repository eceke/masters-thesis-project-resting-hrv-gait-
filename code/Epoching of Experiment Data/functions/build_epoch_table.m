function epochTable = build_epoch_table(confirmedMarkers, cfg)
% Create segment boundaries from confirmed markers

    arguments
        confirmedMarkers (:,1) struct
        cfg (1,1) struct
    end
    
    % Get marker times
    markerTimes = [confirmedMarkers.timeSec];
    
    % Use segment-marker mapping
    segmentNames = cfg.segmentNames;
    nSegments = length(segmentNames);
    
    % Create empty table with ALL columns including duration
    epochTable = table();
    epochTable.segmentName = cell(nSegments, 1);
    epochTable.startSec = zeros(nSegments, 1);
    epochTable.endSec = zeros(nSegments, 1);
    epochTable.durationSec = zeros(nSegments, 1);
    epochTable.startMarkerLabel = cell(nSegments, 1);
    epochTable.endMarkerLabel = cell(nSegments, 1);
    epochTable.confidenceStart = zeros(nSegments, 1);
    epochTable.confidenceEnd = zeros(nSegments, 1);
    epochTable.notes = cell(nSegments, 1);
    
    % Marker labels
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
    
    % Determine boundaries for each segment
    for iSeg = 1:nSegments
        segName = segmentNames{iSeg};
        
        % Which markers belong to this segment?
        markerIndices = cfg.segmentMarkerMap(segName);
        
        if length(markerIndices) == 1
            % Resting segments (RS_EO1, RS_EC, RS_EO2)
            % Start = 0 or previous segment's end
            % End = this marker's time
            
            if iSeg == 1
                % First segment: RS_EO1
                startTime = 0;
                startLabel = 'recording_start';
                endTime = markerTimes(markerIndices(1));
                endLabel = markerLabels{markerIndices(1)};
                confStart = 1.0;  % Recording start
                confEnd = confirmedMarkers(markerIndices(1)).selectConfidence;
                
                % Manual override check
                if isfield(confirmedMarkers, 'manualOverride') && ...
                   confirmedMarkers(markerIndices(1)).manualOverride
                    notes = 'end_marker_manual';
                else
                    notes = '';
                end
                
            else
                % Other resting segments
                prevMarkerIdx = cfg.segmentMarkerMap(segmentNames{iSeg-1});
                if length(prevMarkerIdx) == 1
                    startTime = markerTimes(prevMarkerIdx);
                    startLabel = markerLabels{prevMarkerIdx};
                    confStart = confirmedMarkers(prevMarkerIdx).selectConfidence;
                else
                    startTime = markerTimes(prevMarkerIdx(2));  % end marker
                    startLabel = markerLabels{prevMarkerIdx(2)};
                    confStart = confirmedMarkers(prevMarkerIdx(2)).selectConfidence;
                end
                
                endTime = markerTimes(markerIndices(1));
                endLabel = markerLabels{markerIndices(1)};
                confEnd = confirmedMarkers(markerIndices(1)).selectConfidence;
                
                % Notes
                notes = '';
                if isfield(confirmedMarkers, 'manualOverride')
                    if (isfield(confirmedMarkers(prevMarkerIdx(end)), 'manualOverride') && ...
                        confirmedMarkers(prevMarkerIdx(end)).manualOverride) || ...
                       confirmedMarkers(markerIndices(1)).manualOverride
                        notes = 'marker_manual';
                    end
                end
            end
            
        else
            % Walking segments (BW_1KMH, FWW_1KMH, BW_4KMH, FWW_4KMH)
            % 2 markers: start and end
            startTime = markerTimes(markerIndices(1));
            endTime = markerTimes(markerIndices(2));
            startLabel = markerLabels{markerIndices(1)};
            endLabel = markerLabels{markerIndices(2)};
            confStart = confirmedMarkers(markerIndices(1)).selectConfidence;
            confEnd = confirmedMarkers(markerIndices(2)).selectConfidence;
            
            % Notes
            notes = '';
            if isfield(confirmedMarkers, 'manualOverride')
                if confirmedMarkers(markerIndices(1)).manualOverride || ...
                   confirmedMarkers(markerIndices(2)).manualOverride
                    notes = 'marker_manual';
                end
            end
        end
        
        % Calculate duration
        duration = endTime - startTime;
        
        % Add to table - FILL IN ALL VARIABLES
        epochTable.segmentName{iSeg} = segName;
        epochTable.startSec(iSeg) = startTime;
        epochTable.endSec(iSeg) = endTime;
        epochTable.durationSec(iSeg) = duration;
        epochTable.startMarkerLabel{iSeg} = startLabel;
        epochTable.endMarkerLabel{iSeg} = endLabel;
        epochTable.confidenceStart(iSeg) = confStart;
        epochTable.confidenceEnd(iSeg) = confEnd;
        epochTable.notes{iSeg} = notes;
    end
    
    % Add TABLE segment if exists
    if cfg.hasTableSegment
        % TABLE: between FWW_1KMH_end and BW_4KMH_start
        
        % Find FWW_1KMH's end marker
        fww1kmhIdx = find(strcmp(segmentNames, 'FWW_1KMH'));
        if ~isempty(fww1kmhIdx)
            fwwMarkers = cfg.segmentMarkerMap('FWW_1KMH');
            startTime = markerTimes(fwwMarkers(2));  % end marker
            startLabel = markerLabels{fwwMarkers(2)};
            confStart = confirmedMarkers(fwwMarkers(2)).selectConfidence;
        else
            startTime = NaN;
            startLabel = 'unknown';
            confStart = 0;
        end
        
        % Find BW_4KMH's start marker
        bw4kmhIdx = find(strcmp(segmentNames, 'BW_4KMH'));
        if ~isempty(bw4kmhIdx)
            bwMarkers = cfg.segmentMarkerMap('BW_4KMH');
            endTime = markerTimes(bwMarkers(1));  % start marker
            endLabel = markerLabels{bwMarkers(1)};
            confEnd = confirmedMarkers(bwMarkers(1)).selectConfidence;
        else
            endTime = NaN;
            endLabel = 'unknown';
            confEnd = 0;
        end
        
        % Calculate duration
        duration = endTime - startTime;
        
        % CREATE A ONE-ROW TABLE FOR A NEW ROW
        newRow = table();
        newRow.segmentName = {'TABLE'};
        newRow.startSec = startTime;
        newRow.endSec = endTime;
        newRow.durationSec = duration;
        newRow.startMarkerLabel = {startLabel};
        newRow.endMarkerLabel = {endLabel};
        newRow.confidenceStart = confStart;
        newRow.confidenceEnd = confEnd;
        newRow.notes = {'derived_segment'};
        
        % Add to table
        epochTable = [epochTable; newRow];
    end
    
    % Sort the table by startSec
    epochTable = sortrows(epochTable, 'startSec');
    
    fprintf('[BUILD EPOCH TABLE] %d segments created.\n', height(epochTable));
end