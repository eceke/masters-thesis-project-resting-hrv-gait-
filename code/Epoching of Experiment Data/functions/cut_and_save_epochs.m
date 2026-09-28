function [epochFiles, cutInfo] = cut_and_save_epochs(epochTable, dataStruct, cfg, meta, sourceFolderName, epochRootName)
%CUT_AND_SAVE_EPOCHS  Cut segments and save as .mat and CSV files
%
% NEW:
% - Saves RAW (unscaled/original) CSVs into:
%     Epochs\VPxx\csv\<SEGMENT>\  (default)
% - Saves PHYSICAL CSVs into:
%     Epochs\VPxx\csv\<SEGMENT>\Physical\
% - Saves both raw+phys into the MAT file as well.

   arguments
        epochTable table
        dataStruct struct
        cfg (1,1) struct
        meta struct
        sourceFolderName (1,:) char = 'Heart'
        epochRootName (1,:) char = 'Heart'
    end

    % --- Output root: Epochs/VP01/
    outputDir = fullfile(cfg.projectRoot, cfg.dir.epochs, cfg.participantId, epochRootName);
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
        fprintf('[CUT & SAVE] Created directory: %s\n', outputDir);
    end

    % --- CSV main dir: Epochs/VP01/csv
    if cfg.output.saveCsv
        csvMainDir = fullfile(outputDir, cfg.output.csvSubfolder);
        if ~exist(csvMainDir, 'dir')
            mkdir(csvMainDir);
        end
    end

    epochFiles = struct();
    cutInfo = struct();

    

% ===== NEW: Load template Unisens XML once (for per-segment unisens.xml generation) =====
templateDoc = [];
templateNsUri = '';
templateStartTs = '';
templateStartUtc = '';
if cfg.output.saveCsv
    try
        rawDir0 = fullfile(cfg.projectRoot, cfg.dir.raw, cfg.participantId);
        sourceDir0 = fullfile(rawDir0, sourceFolderName);
        if exist(sourceDir0, 'dir')
            rawDir0 = sourceDir0;
        end
        templateXmlPath = fullfile(rawDir0, 'unisens.xml');
        if isfile(templateXmlPath)
            templateDoc = xmlread(templateXmlPath);
            root0 = templateDoc.getDocumentElement;
            templateNsUri = char(root0.getNamespaceURI);
            templateStartTs = char(root0.getAttribute('timestampStart'));
            % Try to read timestampStartUTC from customAttributes (if present)
            ca = root0.getElementsByTagNameNS(templateNsUri, 'customAttribute');
            for k = 0:ca.getLength-1
                node = ca.item(k);
                if node.hasAttribute('key') && strcmp(char(node.getAttribute('key')), 'timestampStartUTC')
                    templateStartUtc = char(node.getAttribute('value'));
                    break;
                end
            end
        else
            warning('Template unisens.xml not found: %s (segment XMLs will not be created)', templateXmlPath);
        end
    catch ME
        warning(ME.identifier, "Failed to load template unisens.xml (segment XMLs will not be created): %s", ME.message);

        templateDoc = [];
    end
end
fprintf('[CUT & SAVE] Processing %d segments...\n', height(epochTable));

    for iSeg = 1:height(epochTable)
        segName   = epochTable.segmentName{iSeg};
        startTime = epochTable.startSec(iSeg);
        endTime   = epochTable.endSec(iSeg);
        duration  = endTime - startTime;

        ecgStartSample = [];
        ecgEndSample = [];

        fprintf('  Segment %d: %s [%.3f - %.3f] s (%.3f s)\n', ...
            iSeg, segName, startTime, endTime, duration);

        % --- Segment folder name
        safeSegName = strrep(segName, ' ', '_');

        % --- Segment dirs
        if cfg.output.saveCsv
            segmentCsvDir = fullfile(csvMainDir, safeSegName);                 % RAW goes here
            segmentPhysDir = fullfile(segmentCsvDir, 'Physical');              % PHYS goes here

            if ~exist(segmentCsvDir, 'dir'), mkdir(segmentCsvDir); end
            if ~exist(segmentPhysDir, 'dir'), mkdir(segmentPhysDir); end

            if cfg.advanced.verbose
                fprintf('    CSV RAW dir: %s\n', segmentCsvDir);
                fprintf('    CSV PHYS dir: %s\n', segmentPhysDir);
            end
        end

        % --- SegmentData struct for MAT
        segmentData = struct();
        segmentData.segmentName     = segName;
        segmentData.startTime       = startTime;
        segmentData.endTime         = endTime;
        segmentData.duration        = duration;
        segmentData.participantId   = cfg.participantId;
        segmentData.dateProcessed   = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        segmentData.epochTableRow   = epochTable(iSeg, :);

        savedChannels = {};

        for iChan = 1:length(cfg.output.channelsToSave)
            chanName = cfg.output.channelsToSave{iChan};

            if ~isfield(dataStruct, chanName)
                if cfg.advanced.verbose
                    warning('Channel "%s" not found in dataStruct for %s', chanName, cfg.participantId);
                end
                continue;
            end

            ch = dataStruct.(chanName);

            % --- fs required
            if ~isfield(ch, 'fs') || ~isfinite(ch.fs) || ch.fs <= 0
                warning('Invalid/missing fs for channel "%s" (%s).', chanName, cfg.participantId);
                continue;
            end
            fs = ch.fs;

            % --- Determine raw + phys sources
            % Preferred fields:
            %   ch.raw, ch.phys
            % Backward compatible:
            %   ch.data (assumed physical)
            hasRaw  = isfield(ch, 'raw')  && ~isempty(ch.raw);
            hasPhys = isfield(ch, 'phys') && ~isempty(ch.phys);

            if ~hasPhys && isfield(ch, 'data') && ~isempty(ch.data)
                % Backward compatibility: treat .data as phys
                ch.phys = ch.data;
                hasPhys = true;
            end

            if ~hasRaw
                % If raw isn't provided, we CAN still run, but raw==phys
                % (you will not get true unscaled values unless you populate ch.raw upstream)
                if hasPhys
                    ch.raw = ch.phys;
                    hasRaw = true;
                    if cfg.advanced.verbose
                        warning('Channel "%s": raw not provided -> using raw=phys fallback.', chanName);
                    end
                else
                    warning('Channel "%s" has no data (raw/phys/data missing).', chanName);
                    continue;
                end
            end

            rawData  = ch.raw;
            physData = [];
            if hasPhys
                physData = ch.phys;
            end

            if isempty(rawData) || size(rawData,1)==0
                warning('Channel "%s" raw is empty (%s).', chanName, cfg.participantId);
                continue;
            end

            % --- Universal sample index calc (low fs safe)
            startSample = floor(startTime * fs) + 1;   % inclusive, 1-based
            endSample   = ceil(endTime * fs);          % inclusive

            totalSamples = size(rawData, 1);
            startSample  = max(1, min(totalSamples, startSample));
            endSample    = max(1, min(totalSamples, endSample));

            if strcmp(chanName, 'ecg')
                ecgStartSample = startSample;
                ecgEndSample = endSample;
            end

            if startSample > endSample
                warning('Invalid sample range for %s in %s (start %d > end %d).', ...
                    chanName, segName, startSample, endSample);
                continue;
            end

            if strcmp(chanName, 'nn_live') || strcmp(chanName, 'bpmbxb_live')
                if isempty(ecgStartSample) || isempty(ecgEndSample)
                    warning('ECG reference indices not available for %s in %s.', chanName, segName);
                    continue;
                end
            
                firstCol = rawData(:,1);
                mask = firstCol >= ecgStartSample & firstCol <= ecgEndSample;

                % Diagnostic output for ECG-referenced channel rows
                fprintf('    [%s][%s] ECG ref range: %d - %d\n', sourceFolderName, chanName, ecgStartSample, ecgEndSample);
                
                if ~isempty(firstCol)
                    fprintf('    [%s][%s] firstCol min/max: %g - %g\n', ...
                        sourceFolderName, chanName, min(firstCol), max(firstCol));
                end
                
                fprintf('    [%s][%s] matched rows: %d\n', ...
                    sourceFolderName, chanName, nnz(mask));

                cutRaw = rawData(mask, :);

                % Original row indices inside the valuesEntry file
                originalRows = find(mask);
                if isempty(originalRows)
                    startRowOriginal = NaN;
                    endRowOriginal = NaN;
                else
                    startRowOriginal = originalRows(1);
                    endRowOriginal   = originalRows(end);
                end
            
                cutPhys = [];
                if ~isempty(physData)
                    if size(physData,1) ~= size(rawData,1)
                        warning('Channel "%s": raw/phys length mismatch (raw=%d, phys=%d). Saving RAW only.', ...
                            chanName, size(rawData,1), size(physData,1));
                    else
                        cutPhys = physData(mask, :);
                    end
                end
            
                % Keep ECG reference indices as start/end sample
                startSample = ecgStartSample;
                endSample   = ecgEndSample;
            
            else
                cutRaw = rawData(startSample:endSample, :);
            
                cutPhys = [];
                if ~isempty(physData)
                    if size(physData,1) ~= size(rawData,1)
                        warning('Channel "%s": raw/phys length mismatch (raw=%d, phys=%d). Saving RAW only.', ...
                            chanName, size(rawData,1), size(physData,1));
                    else
                        cutPhys = physData(startSample:endSample, :);
                    end
                end
            end

            % --- Save into MAT
            segmentData.(chanName).fs          = fs;
            segmentData.(chanName).startSample = startSample;
            segmentData.(chanName).endSample   = endSample;
            segmentData.(chanName).numSamples  = size(cutRaw, 1);

            if strcmp(chanName, 'nn_live') || strcmp(chanName, 'bpmbxb_live')
                segmentData.(chanName).startRowOriginal = startRowOriginal;
                segmentData.(chanName).endRowOriginal   = endRowOriginal;
            end

            segmentData.(chanName).raw  = cutRaw;
            if ~isempty(cutPhys)
                segmentData.(chanName).phys = cutPhys;
            else
                segmentData.(chanName).phys = []; % explicit
            end

            % --- CSV export
            if cfg.output.saveCsv
                % RAW in segment folder
                rawCsvName = dataStruct.(chanName).originalFile;   % e.g., 'acc.csv'
                rawCsvPath = fullfile(segmentCsvDir, rawCsvName);


                try
                    writematrix(cutRaw, rawCsvPath, 'Delimiter',';');
                    if cfg.advanced.verbose
                        fprintf('    RAW CSV: %s (%d samples, fs=%g)\n', rawCsvName, size(cutRaw,1), fs);
                    end
                catch ME
                    warning('Failed to save RAW CSV for %s: %s', chanName, ME.message);
                end

                % PHYS in Physical subfolder (if available)
                if ~isempty(cutPhys)
                    physCsvName = sprintf('%s_%s_%s.csv', cfg.participantId, segName, chanName);
                    physCsvPath = fullfile(segmentPhysDir, physCsvName);

                    try
                        writematrix(cutPhys, physCsvPath, 'Delimiter',';');
                        if cfg.advanced.verbose
                            fprintf('    PHYS CSV: Physical\\%s (%d samples, fs=%g)\n', physCsvName, size(cutPhys,1), fs);
                        end
                    catch ME
                        warning('Failed to save PHYS CSV for %s: %s', chanName, ME.message);
                    end
                end
            end

            savedChannels{end+1} = chanName; %#ok<AGROW>
        end

        segmentData.savedChannels = savedChannels;

        % --- Save MAT
        if cfg.output.saveMat
            matFileName = sprintf('%s_%s.mat', cfg.participantId, segName);
            matPath = fullfile(outputDir, matFileName);

            try
                save(matPath, 'segmentData', '-mat', cfg.output.matVersion);

                epochFiles(iSeg).segmentName    = segName;
                epochFiles(iSeg).matFile        = matPath;
                epochFiles(iSeg).savedChannels  = savedChannels;
                epochFiles(iSeg).saved          = true;

                if cfg.advanced.verbose
                    fprintf('    MAT: %s (%d channels)\n', matFileName, length(savedChannels));
                end

            catch ME
                warning('Failed to save .mat for %s: %s', segName, ME.message);
                epochFiles(iSeg).saved = false;
            end
        end

        % --- cutInfo
        cutInfo(iSeg).segmentName    = segName;
        cutInfo(iSeg).startTime      = startTime;
        cutInfo(iSeg).endTime        = endTime;
        cutInfo(iSeg).duration       = duration;
        cutInfo(iSeg).savedChannels  = savedChannels;
        cutInfo(iSeg).numChannels    = length(savedChannels);

        if cfg.output.saveMat, cutInfo(iSeg).matFile = matPath; end
        if cfg.output.saveCsv
            cutInfo(iSeg).csvDirRaw  = segmentCsvDir;
            cutInfo(iSeg).csvDirPhys = segmentPhysDir;
        

            % ===== NEW: Write per-segment unisens.xml inside the segment folder =====
            % Enables opening the cut segment folder in DataAnalyzer as a standalone measurement.
            if cfg.output.saveCsv && ~isempty(templateDoc)
                try
                    write_unisens_xml_segment( ...
                        segmentCsvDir, segName, startTime, duration, savedChannels, dataStruct, cfg, ...
                        templateDoc, templateNsUri, templateStartTs, templateStartUtc);
                catch ME
                    warning('Failed to write unisens.xml for segment %s: %s', segName, ME.message);
                end
            end
        end
    end

    fprintf('[CUT & SAVE] Completed. Segments saved to: %s\n', outputDir);

    if cfg.output.saveCsv
        fprintf('  RAW CSVs in: %s\n', csvMainDir);
        fprintf('  PHYS CSVs in each segment''s Physical subfolder.\n');
    end

    % Unique channels summary
    allChannels = {};
    for i = 1:length(cutInfo)
        allChannels = [allChannels, cutInfo(i).savedChannels]; %#ok<AGROW>
    end
    uniqueChannels = unique(allChannels);
    fprintf('  Unique channels saved: %s\n', strjoin(uniqueChannels, ', '));
end
