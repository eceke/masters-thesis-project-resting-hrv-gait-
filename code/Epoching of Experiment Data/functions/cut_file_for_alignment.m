function [ok, cutInfo] = cut_file_for_alignment(srcPath, dstPath, entryInfo, sourceStartTime, commonStart, commonEnd, forcedStartIndex, forcedEndIndex)
%CUT_FILE_FOR_ALIGNMENT Cut a single CSV or BIN file to the aligned time window.
%
% INPUT
%   srcPath         : full path to source file
%   dstPath         : full path to output file
%   entryInfo       : XML entry info
%   sourceStartTime : datetime of source folder start
%   commonStart     : datetime common aligned start
%   commonEnd       : datetime common aligned end
%   forcedStartIndex: optional exact start index to reuse (for BIN side)
%   forcedEndIndex  : optional exact end index to reuse (for BIN side)
%
% OUTPUT
%   ok              : true/false
%   cutInfo         : struct with details

    arguments
        srcPath (1,:) char
        dstPath (1,:) char
        entryInfo (1,1) struct
        sourceStartTime datetime
        commonStart datetime
        commonEnd datetime
        forcedStartIndex double = NaN
        forcedEndIndex double = NaN
    end

    ok = false;
    cutInfo = struct();

    if ~isfile(srcPath)
        warning('cut_file_for_alignment:MissingSource', 'Source file not found: %s', srcPath);
        return;
    end

    [~,~,ext] = fileparts(srcPath);
    ext = lower(ext);

    fs = entryInfo.sampleRate;
    if ~isfinite(fs) || isnan(fs) || fs <= 0
        warning('cut_file_for_alignment:InvalidFS', 'Invalid sampleRate for %s', srcPath);
        return;
    end

    % Either compute indices from time window, or reuse exact reference indices
    if ~isnan(forcedStartIndex) && ~isnan(forcedEndIndex)
        requestedStartIndex = forcedStartIndex;
        requestedEndIndex   = forcedEndIndex;
    else
        startOffsetSec = seconds(commonStart - sourceStartTime);
        endOffsetSec   = seconds(commonEnd - sourceStartTime);

        if endOffsetSec <= startOffsetSec
            warning('cut_file_for_alignment:InvalidOffsets', ...
                'Invalid time window for %s', srcPath);
            return;
        end

        requestedStartIndex = floor(startOffsetSec * fs) + 1;
        requestedEndIndex   = ceil(endOffsetSec * fs);
    end

    if strcmp(ext, '.csv')
        X = read_csv_for_alignment_local(srcPath, entryInfo);

        if isempty(X)
            cutX = X;
            write_matrix_local(cutX, dstPath);
            ok = true;
            cutInfo = make_cutinfo_local(entryInfo, srcPath, dstPath, fs, ...
                requestedStartIndex, requestedEndIndex, ...
                NaN, NaN, ...
                0, 0, 'csv_empty');
            return;
        end

        entryType = '';
        if isfield(entryInfo, 'entryType')
            entryType = entryInfo.entryType;
        end

        if strcmpi(entryType, 'valuesEntry')
            % valuesEntry: first column stores reference ECG sample/event indices
            firstCol = X(:,1);
            validMask = ~isnan(firstCol) & isfinite(firstCol);
            rowMask = validMask & firstCol >= requestedStartIndex & firstCol <= requestedEndIndex;
            cutX = X(rowMask, :);

            % IMPORTANT:
            % After alignment, valuesEntry first column must become LOCAL
            % to the aligned ECG signal, otherwise epoch cutting will compare
            % old/global indices against new/local ECG indices.
            if ~isempty(cutX)
                cutX(:,1) = cutX(:,1) - requestedStartIndex + 1;
            end

            % For valuesEntry, the kept rows are selected by first-column index,
            % but the resulting first column is now LOCAL (starts from 1).
            actualStartIndex = 1;
            actualEndIndex   = size(cutX, 1);
            mode = 'csv_valuesEntry_firstColumn_localized';

        else
            % signalEntry: row/sample-based cutting
            totalRows = size(X,1);
            actualStartIndex = max(1, min(totalRows, requestedStartIndex));
            actualEndIndex   = max(1, min(totalRows, requestedEndIndex));

            if actualStartIndex > actualEndIndex
                cutX = X([]);
            else
                cutX = X(actualStartIndex:actualEndIndex, :);
            end
            mode = 'csv_signalEntry_rows';
        end

        write_matrix_local(cutX, dstPath);
        ok = true;

        cutInfo = make_cutinfo_local(entryInfo, srcPath, dstPath, fs, ...
            requestedStartIndex, requestedEndIndex, ...
            actualStartIndex, actualEndIndex, ...
            size(cutX,1), size(X,1), mode);

    elseif strcmp(ext, '.bin')
        dt = lower(string(entryInfo.dataType));
        nCh = numel(entryInfo.channels);

        if nCh < 1
            warning('cut_file_for_alignment:NoChannels', 'No channels for BIN: %s', srcPath);
            return;
        end

        machinefmt = 'ieee-le';
        if isfield(entryInfo, 'bin_endianess') && ~isempty(entryInfo.bin_endianess)
            if strcmpi(entryInfo.bin_endianess, 'BIG')
                machinefmt = 'ieee-be';
            end
        end

        fid = fopen(srcPath, 'r', machinefmt);
        if fid == -1
            warning('cut_file_for_alignment:OpenFailed', 'Failed to open BIN: %s', srcPath);
            return;
        end
        c = onCleanup(@() fclose(fid)); %#ok<NASGU>

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
                warning('cut_file_for_alignment:UnsupportedType', ...
                    'Unsupported dataType "%s" for %s', dt, srcPath);
                return;
        end

        raw = fread(fid, [nCh, Inf], precisionRead); % nCh x N
        totalSamples = size(raw, 2);

        actualStartIndex = max(1, min(totalSamples, requestedStartIndex));
        actualEndIndex   = max(1, min(totalSamples, requestedEndIndex));

        if actualStartIndex > actualEndIndex
            cutRaw = raw(:, []);
        else
            cutRaw = raw(:, actualStartIndex:actualEndIndex);
        end

        fidw = fopen(dstPath, 'w', machinefmt);
        if fidw == -1
            warning('cut_file_for_alignment:CreateFailed', 'Failed to create BIN: %s', dstPath);
            return;
        end
        cw = onCleanup(@() fclose(fidw)); %#ok<NASGU>

        fwrite(fidw, cutRaw, precisionWrite);
        ok = true;

        cutInfo = make_cutinfo_local(entryInfo, srcPath, dstPath, fs, ...
            requestedStartIndex, requestedEndIndex, ...
            actualStartIndex, actualEndIndex, ...
            size(cutRaw,2), totalSamples, 'bin_samples');

    else
        warning('cut_file_for_alignment:UnsupportedExtension', ...
            'Unsupported file extension: %s', srcPath);
        return;
    end
end

function X = read_csv_for_alignment_local(csvPath, entryInfo)
    sep = ';';
    dec = '.';

    if isfield(entryInfo, 'csv')
        if isfield(entryInfo.csv, 'separator') && ~isempty(entryInfo.csv.separator)
            sep = entryInfo.csv.separator;
        end
        if isfield(entryInfo.csv, 'decimalSeparator') && ~isempty(entryInfo.csv.decimalSeparator)
            dec = entryInfo.csv.decimalSeparator;
        end
    else
        if isfield(entryInfo, 'csv_separator') && ~isempty(entryInfo.csv_separator)
            sep = entryInfo.csv_separator;
        end
        if isfield(entryInfo, 'csv_decimal') && ~isempty(entryInfo.csv_decimal)
            dec = entryInfo.csv_decimal;
        end
    end

    X = read_channel_csv(csvPath, sep, dec);
end

function write_matrix_local(X, dstPath)
    outDir = fileparts(dstPath);
    if ~isfolder(outDir)
        mkdir(outDir);
    end
    writematrix(X, dstPath, 'Delimiter', ';');
end

function s = make_cutinfo_local(entryInfo, srcPath, dstPath, fs, ...
    requestedStartIndex, requestedEndIndex, ...
    actualStartIndex, actualEndIndex, ...
    nKept, nOriginal, mode)

    s = struct();

    s.fileId = '';
    if isfield(entryInfo, 'id')
        s.fileId = entryInfo.id;
    else
        [~,name,ext] = fileparts(srcPath);
        s.fileId = [name ext];
    end

    [~,~,ext] = fileparts(srcPath);
    s.extension = ext;

    s.entryType = '';
    if isfield(entryInfo, 'entryType')
        s.entryType = entryInfo.entryType;
    end

    s.srcPath = srcPath;
    s.dstPath = dstPath;
    s.sampleRate = fs;

    % Requested/theoretical indices
    s.requestedStartIndex = requestedStartIndex;
    s.requestedEndIndex   = requestedEndIndex;

    % Actual indices really used after clamp
    s.startIndex = actualStartIndex;
    s.endIndex   = actualEndIndex;

    s.nKept = nKept;
    s.nOriginal = nOriginal;
    s.mode = mode;

    % Head/tail removal info must use ACTUAL applied indices
    if ~isnan(actualStartIndex)
        s.nRemovedHead = max(0, actualStartIndex - 1);
    else
        s.nRemovedHead = NaN;
    end

    if ~isnan(actualEndIndex)
        s.nRemovedTail = max(0, nOriginal - actualEndIndex);
    else
        s.nRemovedTail = NaN;
    end

    if ~isnan(actualStartIndex) && actualStartIndex > 1
        s.removedHeadRange = sprintf('1:%d', actualStartIndex - 1);
    else
        s.removedHeadRange = '';
    end

    if ~isnan(actualEndIndex) && actualEndIndex < nOriginal
        s.removedTailRange = sprintf('%d:%d', actualEndIndex + 1, nOriginal);
    else
        s.removedTailRange = '';
    end

    if nKept > 0 && ~isnan(actualStartIndex) && ~isnan(actualEndIndex)
        s.keptRange = sprintf('%d:%d', actualStartIndex, actualEndIndex);
    else
        s.keptRange = '';
    end
end