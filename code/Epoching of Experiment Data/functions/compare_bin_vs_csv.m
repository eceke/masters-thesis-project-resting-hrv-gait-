function reportTbl = compare_bin_vs_csv(modality, participantId)
%COMPARE_BIN_VS_CSV
% - Decode ALL .bin files into human-readable numeric matrices (raw integers)
% - Compare .bin (Data Analyzer Heart/Hip) vs .csv (Heart/Hip) by BASE NAME:
%       acc.bin  <-> acc.csv
%       ecg.bin  <-> ecg.csv
%       ...
% - Use BOTH unisens.xml files
% - Export decoded BIN as CSV WITHOUT header (raw starts at first row)
% - Report: size match, exact match, first difference, max abs diff
%
% INPUT
%   modality : 'Heart' or 'Hip'

    arguments
        modality (1,:) char {mustBeMember(modality, {'Heart','Hip'})} = 'Heart'
        participantId (1,:) char = ''
    end

    % === AUTO-DETECT vpRoot FROM PROJECT STRUCTURE (Pertuba/Raw/VPxx) ===
    thisFileFullPath = mfilename('fullpath');
    thisFolder = fileparts(thisFileFullPath);
    if isempty(thisFolder)
        thisFolder = pwd;
    end

    currentFolder = thisFolder;
    pertubaRoot = '';

    while ~strcmp(currentFolder, fileparts(currentFolder))
        if isfolder(fullfile(currentFolder, 'Raw'))
            pertubaRoot = currentFolder;
            break;
        end
        currentFolder = fileparts(currentFolder);
    end

    if isempty(pertubaRoot)
        error('Pertuba root could not be detected (no parent folder contains a "Raw" directory).');
    end

    rawRoot = fullfile(pertubaRoot, 'Raw');

    % === TARGET VP FROM USER INPUT ===
    participantId = strtrim(participantId);
    
    if isempty(participantId)
        participantId = input('Enter participant ID for BIN/CSV compare (e.g., VP01): ', 's');
        participantId = strtrim(participantId);
    end
    
    vpCandidate = fullfile(rawRoot, participantId);
    
    if ~isfolder(vpCandidate)
        error('Expected participant folder not found: %s', vpCandidate);
    end
    
    vpRoot = vpCandidate;
    
    fprintf('[%s] BIN/CSV compare will use participant folder: %s\n', modality, vpRoot);

    % === Select folders by modality ===
    if strcmpi(modality, 'Heart')
        binFolder = fullfile(vpRoot, 'Data Analyzer Heart');
        csvFolder = fullfile(vpRoot, 'Heart');
    else
        binFolder = fullfile(vpRoot, 'Data Analyzer Hip');
        csvFolder = fullfile(vpRoot, 'Hip');
    end

    binXmlPath = fullfile(binFolder, 'unisens.xml');
    csvXmlPath = fullfile(csvFolder, 'unisens.xml');

    % Export decoded BIN as CSV for inspection (NO HEADER):
    doExportBinAsCsv = true;
    exportFolder = fullfile(vpRoot, ['BinDecodedAsCsv_' modality]);

    %% ============ Sanity checks ============
    assert(isfolder(binFolder), 'BIN folder not found: %s', binFolder);
    assert(isfolder(csvFolder), 'CSV folder not found: %s', csvFolder);
    assert(isfile(binXmlPath),  'BIN unisens.xml not found: %s', binXmlPath);
    assert(isfile(csvXmlPath),  'CSV unisens.xml not found: %s', csvXmlPath);

    if doExportBinAsCsv && ~isfolder(exportFolder)
        mkdir(exportFolder);
    end

    %% ============ Parse unisens.xml (both) ============
    binMeta = parse_unisens_xml(binXmlPath);
    csvMeta = parse_unisens_xml(csvXmlPath);

    %% ============ Build BASE-NAME keys ============
    binIds = string(binMeta.ids(:));
    csvIds = string(csvMeta.ids(:));

    % Take only relevant extensions
    binIds = binIds(endsWith(lower(binIds), ".bin"));
    csvIds = csvIds(endsWith(lower(csvIds), ".csv"));

    binBases = erase(binIds, ".bin");
    csvBases = erase(csvIds, ".csv");

    allBases = unique([binBases; csvBases], 'stable');

    %% ============ Compare ============
    rows = cell(0, 22);
    r = 0;

    for k = 1:numel(allBases)
        base = allBases(k);

        binId = base + ".bin";
        csvId = base + ".csv";

        binPath = fullfile(binFolder, binId);
        csvPath = fullfile(csvFolder, csvId);

        binExists = isfile(binPath);
        csvExists = isfile(csvPath);

        % Retrieve xml entry info (must exist in respective xml if file exists)
        binInfo = [];
        csvInfo = [];

        if binExists
            fn = safe_fieldname(char(binId));
            assert(isfield(binMeta.byId, fn), 'BIN exists but not found in BIN unisens.xml: %s', binId);
            binInfo = binMeta.byId.(fn);
        end

        if csvExists
            fn = safe_fieldname(char(csvId));
            assert(isfield(csvMeta.byId, fn), 'CSV exists but not found in CSV unisens.xml: %s', csvId);
            csvInfo = csvMeta.byId.(fn);
        end

        % --- Read BIN ---
        binData = [];
        binRows = NaN; binCols = NaN;
        if binExists
            binData = read_unisens_bin(char(binPath), binInfo);
            binRows = size(binData,1);
            binCols = size(binData,2);

            if doExportBinAsCsv
                outCsv = fullfile(exportFolder, char(base + "_RAW_FROM_BIN.csv"));
                writematrix(binData, outCsv, 'Delimiter', ';'); % NO HEADER
            end
        end

        % --- Read CSV ---
        csvData = [];
        csvRows = NaN; csvCols = NaN;
        if csvExists
            csvData = read_unisens_csv(char(csvPath), csvInfo);
            csvRows = size(csvData,1);
            csvCols = size(csvData,2);
        end

        % --- Compare if both exist ---
        sameSize = false;
        exactEqual = false;
        maxAbsDiff = NaN;
        firstDiffRow = NaN;
        firstDiffCol = NaN;
        binValAtFirstDiff = NaN;
        csvValAtFirstDiff = NaN;

        if binExists && csvExists
            sameSize = isequal(size(binData), size(csvData));

            if sameSize
                exactEqual = isequal(binData, csvData);

                if ~exactEqual
                    D = abs(binData - csvData);
                    maxAbsDiff = max(D(:));

                    idx = find(D > 0, 1, 'first');
                    [firstDiffRow, firstDiffCol] = ind2sub(size(D), idx);
                    binValAtFirstDiff = binData(firstDiffRow, firstDiffCol);
                    csvValAtFirstDiff = csvData(firstDiffRow, firstDiffCol);
                else
                    maxAbsDiff = 0;
                end
            end
        end

        % --- Pack report row (id is now the BASE name) ---
        r = r + 1;
        rows(r,:) = { ...
            char(base), ...
            binExists, csvExists, ...
            binRows, binCols, ...
            csvRows, csvCols, ...
            sameSize, exactEqual, maxAbsDiff, ...
            firstDiffRow, firstDiffCol, ...
            binValAtFirstDiff, csvValAtFirstDiff, ...
            getfield_or(binInfo, 'dataType', ''), ...
            numel(getfield_or(binInfo, 'channels', {})), ...
            getfield_or(binInfo, 'lsbValue', NaN), ...
            getfield_or(binInfo, 'baseline', NaN), ...
            getfield_or(csvInfo, 'dataType', ''), ...
            numel(getfield_or(csvInfo, 'channels', {})), ...
            getfield_or(csvInfo, 'lsbValue', NaN), ...
            getfield_or(csvInfo, 'baseline', NaN) ...
        };
    end

    reportTbl = cell2table(rows, 'VariableNames', { ...
        'id', ...
        'binExists','csvExists', ...
        'binRows','binCols', ...
        'csvRows','csvCols', ...
        'sameSize','exactEqual','maxAbsDiff', ...
        'firstDiffRow','firstDiffCol', ...
        'binValFirstDiff','csvValFirstDiff', ...
        'bin_dataType','bin_nChannels','bin_lsbValue','bin_baseline', ...
        'csv_dataType','csv_nChannels','csv_lsbValue','csv_baseline' ...
    });

    outReport = fullfile(vpRoot, ['bin_vs_csv_full_report_' modality '.csv']);
    writetable(reportTbl, outReport);
    disp(reportTbl);
    
    % === Gate info (optional convenience) ===
    passMask = reportTbl.binExists & reportTbl.csvExists & reportTbl.sameSize & reportTbl.exactEqual;
    failMask = reportTbl.binExists & reportTbl.csvExists & ~(reportTbl.sameSize & reportTbl.exactEqual);
    
    assignin('base', ['binCsvPassMask_' modality], passMask);
    assignin('base', ['binCsvFailMask_' modality], failMask);

    fprintf('\n[%s] Report saved: %s\n', modality, outReport);
    if doExportBinAsCsv
        fprintf('[%s] Decoded BIN exports (no header): %s\n', modality, exportFolder);
    end
end

%% ===================== XML PARSER =====================
function meta = parse_unisens_xml(xmlPath)
    txt = fileread(xmlPath);

    entryPattern = '<(signalEntry|valuesEntry)\s+[^>]*id="([^"]+)"[^>]*>(.*?)</\1>';
    tokens = regexp(txt, entryPattern, 'tokens');

    ids = cell(numel(tokens),1);
    byId = struct();

    for i = 1:numel(tokens)
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

        info.dataType = attr_or_empty(attrsStr, 'dataType');
        info.lsbValue = attr_or_nan(attrsStr, 'lsbValue');
        info.baseline = attr_or_nan(attrsStr, 'baseline');

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

function out = getfield_or(s, field, defaultVal)
    if isempty(s)
        out = defaultVal;
        return;
    end
    if isfield(s, field)
        out = s.(field);
    else
        out = defaultVal;
    end
end

%% ===================== BIN READER =====================
function X = read_unisens_bin(binPath, info)
    dt = lower(string(info.dataType));
    nCh = numel(info.channels);
    assert(nCh >= 1, 'No channels in XML for %s', binPath);

    if isempty(info.bin_endianess)
        machinefmt = 'ieee-le';
    else
        if strcmpi(info.bin_endianess, 'LITTLE')
            machinefmt = 'ieee-le';
        elseif strcmpi(info.bin_endianess, 'BIG')
            machinefmt = 'ieee-be';
        else
            error('Unknown endianess "%s" in XML for %s', info.bin_endianess, binPath);
        end
    end

    fid = fopen(binPath, 'r', machinefmt);
    assert(fid ~= -1, 'Failed to open BIN: %s', binPath);
    c = onCleanup(@() fclose(fid));

    switch dt
        case "int16"
            precision = 'int16=>double';
        case "int32"
            precision = 'int32=>double';
        case "uint16"
            precision = 'uint16=>double';
        case "uint32"
            precision = 'uint32=>double';
        otherwise
            error('Unsupported dataType "%s" for %s', dt, binPath);
    end

    raw = fread(fid, [nCh, Inf], precision);
    X = raw.'; % NxC
end

%% ===================== CSV READER =====================
function X = read_unisens_csv(csvPath, info)
    sep = info.csv_separator;
    dec = info.csv_decimal;

    assert(~isempty(sep), 'CSV separator missing in XML for %s', csvPath);
    assert(~isempty(dec), 'CSV decimalSeparator missing in XML for %s', csvPath);

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