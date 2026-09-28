function T = local_read_memory_file(filePath, memorySpeedLabel, memoryWalkSegment, requireValenceColumns)
%LOCAL_READ_MEMORY_FILE Read and standardize a FastWords memory recall file.
%
% Required source columns for accuracy analysis:
%   Participant, Correct, Intrusions
%
% Optional accuracy columns:
%   Condition, perturbation_group, Correct_Percent
%
% Additional required source columns for valence analysis:
%   Negative, Positive, Neutral
%
% If requireValenceColumns is false, Negative / Positive / Neutral are
% optional. Missing optional columns are added to the returned table so that
% multiple speed files can still be vertically concatenated safely.

if nargin < 4
    requireValenceColumns = true;
end
requireValenceColumns = logical(requireValenceColumns);

raw = local_read_table_preserve_names(filePath);

baseRequired = ["Participant", "Correct", "Intrusions"];
optionalBase = ["Condition", "perturbation_group", "Correct_Percent"];
valenceRequired = ["Negative", "Positive", "Neutral"];

sourceNames = string(raw.Properties.VariableNames);
canonicalNames = sourceNames;

% Required base columns.
for i = 1:numel(baseRequired)
    idx = find(strcmpi(sourceNames, baseRequired(i)), 1, 'first');
    if isempty(idx)
        error('Memory file is missing required column "%s": %s', baseRequired(i), filePath);
    end
    canonicalNames(idx) = baseRequired(i);
end

% Optional base columns, canonicalized when present.
for i = 1:numel(optionalBase)
    idx = find(strcmpi(sourceNames, optionalBase(i)), 1, 'first');
    if ~isempty(idx)
        canonicalNames(idx) = optionalBase(i);
    end
end

% Valence columns are required only for valence analysis.
for i = 1:numel(valenceRequired)
    idx = find(strcmpi(sourceNames, valenceRequired(i)), 1, 'first');
    if isempty(idx)
        if requireValenceColumns
            error('Memory file is missing required valence column "%s": %s', valenceRequired(i), filePath);
        end
    else
        canonicalNames(idx) = valenceRequired(i);
    end
end

raw.Properties.VariableNames = cellstr(canonicalNames);

% Stable schema across files.
keepCols = ["Participant", "Condition", "perturbation_group", ...
            "Negative", "Positive", "Neutral", ...
            "Correct", "Intrusions", "Correct_Percent"];
availableKeepCols = keepCols(ismember(keepCols, string(raw.Properties.VariableNames)));
T = raw(:, cellstr(availableKeepCols));

% Add missing optional string columns.
if ~ismember('Condition', T.Properties.VariableNames)
    T.Condition = strings(height(T), 1);
    T.Condition(:) = missing;
end
if ~ismember('perturbation_group', T.Properties.VariableNames)
    T.perturbation_group = strings(height(T), 1);
    T.perturbation_group(:) = missing;
end

% Add missing optional numeric columns.
optionalNumeric = [valenceRequired, "Correct_Percent"];
for i = 1:numel(optionalNumeric)
    v = optionalNumeric(i);
    if ~ismember(v, string(T.Properties.VariableNames))
        T.(v) = NaN(height(T), 1);
        if requireValenceColumns && any(v == valenceRequired)
            error('Memory file is missing required valence column "%s": %s', v, filePath);
        end
    end
end

% Stable column order.
T = T(:, cellstr(keepCols));

% Numeric memory columns.
numericCols = [valenceRequired, "Correct", "Intrusions", "Correct_Percent"];
for i = 1:numel(numericCols)
    T.(numericCols(i)) = local_force_numeric(T.(numericCols(i)), numericCols(i));
end

T.participant_id = local_standardize_participant_id(T.Participant);
T.Condition = string(T.Condition);
T.perturbation_group = string(T.perturbation_group);
T.memory_speed_label = repmat(string(memorySpeedLabel), height(T), 1);
T.walk_segment = repmat(upper(string(memoryWalkSegment)), height(T), 1);

% Put important columns first.
ordered = ["participant_id", "memory_speed_label", "walk_segment", keepCols];
T = T(:, cellstr(ordered));

% Hard-stop on duplicate participant rows within one administration. A
% duplicate here would multiply observations during the later HRV-gait join.
[~, ~, g] = unique(T(:, {'participant_id', 'memory_speed_label'}), 'rows');
counts = accumarray(g, 1);
if any(counts > 1)
    dupGroups = find(counts > 1);
    dupIDs = strings(numel(dupGroups), 1);
    for k = 1:numel(dupGroups)
        rowIdx = find(g == dupGroups(k), 1, 'first');
        dupIDs(k) = string(T.participant_id(rowIdx));
    end
    error('Memory file contains duplicate participant rows for %s. Duplicate participant_id(s): %s. File: %s', ...
        memorySpeedLabel, strjoin(dupIDs, ', '), filePath);
end
end

function x = local_force_numeric(x, colName)
    if isnumeric(x)
        x = double(x);
        return;
    end
    if islogical(x)
        x = double(x);
        return;
    end

    converted = str2double(string(x));
    nonemptyBad = isnan(converted) & ~ismissing(string(x)) & strlength(strtrim(string(x))) > 0;
    if any(nonemptyBad)
        error('Column "%s" must be numeric or convertible to numeric.', colName);
    end
    x = converted;
end
