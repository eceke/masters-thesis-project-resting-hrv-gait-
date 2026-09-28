function data = read_channel_csv(csvPath, separator, decimalSeparator)
% Read a Movisens/Unisens CSV into numeric array.
%
% - Works for 1-col and multi-col numeric CSVs
% - Uses readmatrix with Delimiter and DecimalSeparator (no setvaropts)
% - Trims trailing all-NaN rows if they occur

    arguments
        csvPath (1,:) char
        separator (1,:) char = ';'
        decimalSeparator (1,:) char = '.'
    end

    if ~isfile(csvPath)
        error('read_channel_csv:FileNotFound', 'CSV not found: %s', csvPath);
    end

    % Fast path: readmatrix directly (most robust for numeric-only CSV)
    try
        data = readmatrix(csvPath, 'Delimiter', separator, 'DecimalSeparator', decimalSeparator);
    catch
        % Fallback path: detectImportOptions -> readmatrix
        try
            opts = detectImportOptions(csvPath, 'Delimiter', separator, 'DecimalSeparator', decimalSeparator);
            data = readmatrix(csvPath, opts);
        catch ME
            error('read_channel_csv:ReadFailed', 'Failed to read %s\n%s', csvPath, ME.message);
        end
    end

    if istable(data)
        data = table2array(data);
    end
    if ~isnumeric(data)
        error('read_channel_csv:NonNumeric', 'CSV produced non-numeric output: %s', csvPath);
    end

    data = double(data);

    % Trim trailing all-NaN rows (can happen with trailing delimiters/newlines)
    if ~isempty(data)
        nanRow = all(isnan(data), 2);
        if any(nanRow)
            lastValid = find(~nanRow, 1, 'last');
            if ~isempty(lastValid) && lastValid < size(data,1)
                data = data(1:lastValid, :);
            end
        end
    end
end
