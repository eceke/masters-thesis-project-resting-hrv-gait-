function [daEpochFiles, daCutInfo] = cut_and_save_dataanalyzer_epochs(epochTable, cfg, sourceFolderName, outputFolderName)
%CUT_AND_SAVE_DATAANALYZER_EPOCHS
% Cuts Data Analyzer Heart (.bin + some .csv) using epochTable (startSec/endSec)
% and writes per-segment folders that DataAnalyzer can open (with unisens.xml).
%
% INPUT:
%   epochTable : table with columns segmentName, startSec, endSec, durationSec (output of build_epoch_table)
%   cfg        : config struct (must contain cfg.projectRoot, cfg.dir.raw, cfg.dir.epochs, cfg.participantId)
%
% OUTPUT:
%   daEpochFiles : struct listing produced segment folders/files
%   daCutInfo    : struct with per-file cut indices etc.

    arguments
        epochTable table
        cfg (1,1) struct
        sourceFolderName (1,:) char = 'Data Analyzer Heart'
        outputFolderName (1,:) char = 'DataAnalyzerHeart'
    end

    % --- Locate source Data Analyzer Heart folder ---
    vpRawDir = fullfile(cfg.projectRoot, cfg.dir.raw, cfg.participantId);
        daDir    = fullfile(vpRawDir, sourceFolderName);
    assert(isfolder(daDir), 'Data Analyzer Heart folder not found: %s', daDir);

    daXmlPath = fullfile(daDir, 'unisens.xml');
    assert(isfile(daXmlPath), 'Data Analyzer unisens.xml not found: %s', daXmlPath);

    % --- Output root ---
    outRoot = fullfile(cfg.projectRoot, cfg.dir.epochs, cfg.participantId, outputFolderName);
    if ~isfolder(outRoot), mkdir(outRoot); end

    % --- Parse Data Analyzer unisens.xml (bin + csv entries) ---
    daMeta = parse_unisens_xml_minimal(daXmlPath);

    % Only cut files that physically exist in Data Analyzer folder
    ids = string(daMeta.ids(:));
    existsMask = false(size(ids));
    for i = 1:numel(ids)
        existsMask(i) = isfile(fullfile(daDir, ids(i)));
    end
    ids = ids(existsMask);

    fprintf('[DA CUT] Found %d files in Data Analyzer Heart to cut.\n', numel(ids));
    fprintf('[DA CUT] Output root: %s\n', outRoot);

    daEpochFiles = struct();
    daCutInfo = struct();
    daCutInfo.files = struct();
    daCutInfo.segments = struct();

    % --- Load template XML once for segment xml generation ---
    templateDoc = xmlread(daXmlPath);
    root0 = templateDoc.getDocumentElement;
    nsUri = char(root0.getNamespaceURI);
    templateStartTs = char(root0.getAttribute('timestampStart'));
    templateStartUtc = '';
    ca = root0.getElementsByTagNameNS(nsUri, 'customAttribute');
    for k = 0:ca.getLength-1
        node = ca.item(k);
        if node.hasAttribute('key') && strcmp(char(node.getAttribute('key')), 'timestampStartUTC')
            templateStartUtc = char(node.getAttribute('value'));
            break;
        end
    end

    % --- Process each segment ---
    for iSeg = 1:height(epochTable)
        segName   = epochTable.segmentName{iSeg};
        startSec  = epochTable.startSec(iSeg);
        endSec    = epochTable.endSec(iSeg);
        durSec    = endSec - startSec;

        safeSegName = strrep(segName, ' ', '_');

        segDir = fullfile(outRoot, safeSegName);
        if ~isfolder(segDir), mkdir(segDir); end

        fprintf('[DA CUT] Segment %d/%d: %s [%.3f - %.3f] s\n', ...
            iSeg, height(epochTable), safeSegName, startSec, endSec);

        savedIdsThisSeg = {};

        % Cut each file listed in Data Analyzer unisens.xml
        for iFile = 1:numel(ids)
            id = char(ids(iFile));
            srcPath = fullfile(daDir, id);
            assert(isfile(srcPath), 'Missing source file (unexpected): %s', srcPath);

            info = daMeta.byId.(safe_fieldname(id));

            fs = info.sampleRate;
            if ~isfinite(fs) || fs <= 0
                % fs can be extremely low (0.0166...) but still >0.
                warning('[DA CUT] Invalid sampleRate for %s, skipping.', id);
                continue;
            end

            % Compute cut sample range (1-based inclusive), per channel fs
            startSample = floor(startSec * fs) + 1;
            endSample   = ceil(endSec * fs);

            % For very low fs, endSample may equal startSample-1 if segment very short; clamp
            if endSample < startSample
                endSample = startSample;
            end

            [cutOk, nTotal] = cut_one_file(srcPath, fullfile(segDir, id), info, startSample, endSample);

            % Log
            key = matlab.lang.makeValidName([safeSegName '__' strrep(id,'.','_')]);
            daCutInfo.segments.(key).segmentName = segName;
            daCutInfo.segments.(key).fileId = id;
            daCutInfo.segments.(key).fs = fs;
            daCutInfo.segments.(key).startSample = startSample;
            daCutInfo.segments.(key).endSample = endSample;
            daCutInfo.segments.(key).nTotalSamples = nTotal;
            daCutInfo.segments.(key).cutOk = cutOk;

            if cutOk
                savedIdsThisSeg{end+1} = id; %#ok<AGROW>
            end
        end

        % Write segment unisens.xml (KEEP original ids like ecg.bin, acc.bin, bpmbxb_live.csv, ...)
        write_unisens_xml_dataAnalyzer( ...
            segDir, startSec, durSec, savedIdsThisSeg, ...
            templateDoc, nsUri, templateStartTs, templateStartUtc);

        daEpochFiles.(safeSegName).dir = segDir;
        daEpochFiles.(safeSegName).files = savedIdsThisSeg;
    end

    fprintf('[DA CUT] Done. Segments written under: %s\n', outRoot);
end

%% ========= Cut one file (bin or csv) =========
function [ok, nTotalSamples] = cut_one_file(srcPath, dstPath, info, startSample, endSample)
    ok = false;
    nTotalSamples = NaN;

    [~,~,ext] = fileparts(srcPath);
    ext = lower(ext);

    if strcmp(ext, '.bin')
        [ok, nTotalSamples] = cut_bin_file(srcPath, dstPath, info, startSample, endSample);
    elseif strcmp(ext, '.csv')
        [ok, nTotalSamples] = cut_csv_file(srcPath, dstPath, info, startSample, endSample);
    else
        warning('Unknown extension for %s, skipping.', srcPath);
    end
end

function [ok, nTotalSamples] = cut_bin_file(srcPath, dstPath, info, startSample, endSample)
    ok = false;
    nTotalSamples = NaN;

    dt = lower(string(info.dataType));
    nCh = numel(info.channels);
    assert(nCh >= 1, 'No channels for BIN: %s', srcPath);

    machinefmt = 'ieee-le';
    if ~isempty(info.bin_endianess)
        if strcmpi(info.bin_endianess, 'BIG'), machinefmt = 'ieee-be'; end
    end

    fid = fopen(srcPath, 'r', machinefmt);
    assert(fid ~= -1, 'Failed to open BIN: %s', srcPath);
    c = onCleanup(@() fclose(fid));

    switch dt
        case "int16"
            precisionRead = 'int16=>double';
            precisionWrite = 'int16';
        case "int32"
            precisionRead = 'int32=>double';
            precisionWrite = 'int32';
        case "uint16"
            precisionRead = 'uint16=>double';
            precisionWrite = 'uint16';
        case "uint32"
            precisionRead = 'uint32=>double';
            precisionWrite = 'uint32';
        otherwise
            error('Unsupported dataType "%s" for %s', dt, srcPath);
    end

    raw = fread(fid, [nCh, Inf], precisionRead); % nCh x N
    nTotalSamples = size(raw, 2);

    if nTotalSamples == 0
        warning('Empty BIN: %s', srcPath);
        return;
    end

    startSample = max(1, min(nTotalSamples, startSample));
    endSample   = max(1, min(nTotalSamples, endSample));
    if startSample > endSample
        warning('Invalid cut range for %s (start>%d end>%d).', srcPath, startSample, endSample);
        return;
    end

    cutRaw = raw(:, startSample:endSample); % nCh x Ncut

    fidw = fopen(dstPath, 'w', machinefmt);
    assert(fidw ~= -1, 'Failed to create BIN: %s', dstPath);
    cw = onCleanup(@() fclose(fidw));

    fwrite(fidw, cutRaw, precisionWrite);
    ok = true;
end

function [ok, nTotalRows] = cut_csv_file(srcPath, dstPath, info, startRow, endRow)
    ok = false;
    nTotalRows = NaN;

    % Read as numeric matrix, NO header assumed
    X = read_unisens_csv_minimal(srcPath, info);
    nTotalRows = size(X, 1);

    if nTotalRows == 0
        warning('Empty CSV: %s', srcPath);
        return;
    end

    startRow = max(1, min(nTotalRows, startRow));
    endRow   = max(1, min(nTotalRows, endRow));
    if startRow > endRow
        warning('Invalid cut range for %s (start>%d end>%d).', srcPath, startRow, endRow);
        return;
    end

    cutX = X(startRow:endRow, :);
    writematrix(cutX, dstPath, 'Delimiter', ';'); % raw starts at first row
    ok = true;
end

%% ========= Minimal unisens.xml parser (bin+csv) =========
function meta = parse_unisens_xml_minimal(xmlPath)
    txt = fileread(xmlPath);

    entryPattern = '<(signalEntry|valuesEntry)\s+[^>]*id="([^"]+)"[^>]*>(.*?)</\1>';
    tokens = regexp(txt, entryPattern, 'tokens');

    ids = cell(numel(tokens),1);
    byId = struct();

    for i = 1:numel(tokens)
        entryType = tokens{i}{1};
        id = tokens{i}{2};
        body = tokens{i}{3};
        ids{i} = id;

        openTagPattern = ['<', '(signalEntry|valuesEntry)', '\s+([^>]*)id="', regexptranslate('escape', id), '"([^>]*)>'];
        ot = regexp(txt, openTagPattern, 'tokens', 'once');
        attrsStr = '';
        if ~isempty(ot)
            attrsStr = [ot{2}, ' ', ot{3}];
        end

        info = struct();
        info.id = id;
        info.entryType = entryType;

        info.dataType   = attr_or_empty(attrsStr, 'dataType');
        info.sampleRate = attr_or_nan(attrsStr, 'sampleRate');
        info.lsbValue   = attr_or_nan(attrsStr, 'lsbValue');
        info.baseline   = attr_or_nan(attrsStr, 'baseline');

        ch = regexp(body, '<channel\s+name="([^"]+)"\s*/?>', 'tokens');
        info.channels = cellfun(@(c)c{1}, ch, 'UniformOutput', false);

        sep = regexp(body, '<csvFileFormat[^>]*separator="([^"]+)"', 'tokens', 'once');
        dec = regexp(body, '<csvFileFormat[^>]*decimalSeparator="([^"]+)"', 'tokens', 'once');
        info.csv_separator = '';
        info.csv_decimal = '';
        if ~isempty(sep), info.csv_separator = sep{1}; end
        if ~isempty(dec), info.csv_decimal = dec{1}; end

        endi = regexp(body, '<binFileFormat[^>]*endianess="([^"]+)"', 'tokens', 'once');
        info.bin_endianess = '';
        if ~isempty(endi), info.bin_endianess = endi{1}; end

        byId.(safe_fieldname(id)) = info;
    end

    meta.ids = ids;
    meta.byId = byId;
end

function v = attr_or_empty(attrsStr, key)
    t = regexp(attrsStr, [key,'="([^"]+)"'], 'tokens', 'once');
    if isempty(t), v = ''; else, v = t{1}; end
end

function v = attr_or_nan(attrsStr, key)
    t = regexp(attrsStr, [key,'="([^"]+)"'], 'tokens', 'once');
    if isempty(t)
        v = NaN;
    else
        v = str2double(t{1});
        if isnan(v), v = NaN; end
    end
end

function fn = safe_fieldname(id)
    fn = matlab.lang.makeValidName(strrep(id, '.', '_'));
end

%% ========= Minimal CSV reader (no header) =========
function X = read_unisens_csv_minimal(csvPath, info)
    sep = info.csv_separator;
    dec = info.csv_decimal;
    if isempty(sep), sep = ';'; end
    if isempty(dec), dec = '.'; end

    opts = detectImportOptions(csvPath, 'Delimiter', sep);
    opts.VariableNamesLine = 0;
    opts.DataLines = [1 Inf];

    if ~strcmp(dec, '.')
        txt = fileread(csvPath);
        txt = strrep(txt, dec, '.');
        tmp = [tempname, '.csv'];
        fid = fopen(tmp, 'w'); fwrite(fid, txt); fclose(fid);
        X = readmatrix(tmp, opts);
        delete(tmp);
    else
        X = readmatrix(csvPath, opts);
    end

    if isvector(X)
        X = X(:);
    end
end