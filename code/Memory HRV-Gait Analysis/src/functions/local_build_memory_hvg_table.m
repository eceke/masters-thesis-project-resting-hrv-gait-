function [mergedOut, qcSummary] = local_build_memory_hvg_table( ...
    memoryData, hvgRaw, presentedWords, includePerturbation, ...
    selectedHRV, selectedGait, selectedHRVCanonical, selectedGaitCanonical, selectedHRVTransforms)
%LOCAL_BUILD_MEMORY_HVG_TABLE Build analysis-ready memory-HRV-gait table.
%
% General-purpose preprocessing rules:
%   - gait predictors: z-standardized
%   - HRV predictors: optionally natural-log transformed, then z-standardized
%   - the z_* column name always represents the final model predictor
%
% Backward-compatible defaults are used if the canonical-name or transform
% inputs are omitted.

selectedHRV = string(selectedHRV);
selectedGait = string(selectedGait);
selectedHRV = selectedHRV(:);
selectedGait = selectedGait(:);

if nargin < 7 || isempty(selectedHRVCanonical)
    selectedHRVCanonical = selectedHRV;
else
    selectedHRVCanonical = string(selectedHRVCanonical(:));
end
if nargin < 8 || isempty(selectedGaitCanonical)
    selectedGaitCanonical = selectedGait;
else
    selectedGaitCanonical = string(selectedGaitCanonical(:));
end
if nargin < 9 || isempty(selectedHRVTransforms)
    selectedHRVTransforms = repmat("none", numel(selectedHRV), 1);
else
    selectedHRVTransforms = lower(string(selectedHRVTransforms(:)));
end

if numel(selectedHRVCanonical) ~= numel(selectedHRV)
    error('selectedHRVCanonical must have one entry per selected HRV predictor.');
end
if numel(selectedGaitCanonical) ~= numel(selectedGait)
    error('selectedGaitCanonical must have one entry per selected gait predictor.');
end
if numel(selectedHRVTransforms) ~= numel(selectedHRV)
    error('selectedHRVTransforms must have one entry per selected HRV predictor.');
end
if any(~ismember(selectedHRVTransforms, ["none", "ln", "asis"]))
    error('Unsupported HRV transform. Allowed values are "none", "ln", and "asis".');
end

selectedPredictors = unique([selectedHRV; selectedGait], 'stable');

qcMetric = strings(0,1);
qcValue = strings(0,1);
qcSeverity = strings(0,1);
qcDetails = strings(0,1);

    function addQC(metric, value, severity, details)
        qcMetric(end+1,1) = string(metric); %#ok<AGROW>
        qcValue(end+1,1) = string(value); %#ok<AGROW>
        qcSeverity(end+1,1) = string(severity); %#ok<AGROW>
        qcDetails(end+1,1) = string(details); %#ok<AGROW>
    end

%% Validate fixed inputs
presentedWords = double(presentedWords);
if ~isscalar(presentedWords) || ~isfinite(presentedWords) || presentedWords <= 0 || ...
        abs(presentedWords - round(presentedWords)) > sqrt(eps)
    error('presentedWords must be a positive integer.');
end
presentedWords = round(presentedWords);

%% Use selected memory file(s)
M = memoryData;
M.participant_id = local_standardize_participant_id(M.participant_id);
M.walk_segment = upper(string(M.walk_segment));
M.memory_speed_label = string(M.memory_speed_label);

% A participant x memory administration must be unique before joining.
local_assert_unique_keys(M, ["participant_id", "walk_segment"], ...
    'Memory data contain duplicate participant x walk_segment rows.');

M.Presented_Words = repmat(double(presentedWords), height(M), 1);
M.Total_Recalled = double(M.Correct) + double(M.Intrusions);
M.Recall_Performance = double(M.Correct) ./ double(M.Presented_Words);
M.Recall_Precision = double(M.Correct) ./ double(M.Total_Recalled);
M.Recall_Precision(M.Total_Recalled == 0) = NaN;

addQC('memory_rows_total', height(M), 'INFO', 'Selected memory speed file(s) combined.');
addQC('memory_participants_total', numel(unique(M.participant_id)), 'INFO', 'Unique participants in memory files.');

invalidCorrect = ~isfinite(double(M.Correct)) | double(M.Correct) < 0 | double(M.Correct) > M.Presented_Words;
invalidIntrusions = ~isfinite(double(M.Intrusions)) | double(M.Intrusions) < 0;
if any(invalidCorrect)
    addQC('invalid_correct_rows', sum(invalidCorrect), 'ERROR', 'Correct must be finite and between 0 and Presented_Words.');
    error('Memory data contain %d invalid Correct value(s). Check the input memory file(s).', sum(invalidCorrect));
else
    addQC('invalid_correct_rows', 0, 'OK', 'All Correct values are valid.');
end
if any(invalidIntrusions)
    addQC('invalid_intrusions_rows', sum(invalidIntrusions), 'ERROR', 'Intrusions must be finite and non-negative.');
    error('Memory data contain %d invalid Intrusions value(s). Check the input memory file(s).', sum(invalidIntrusions));
else
    addQC('invalid_intrusions_rows', 0, 'OK', 'All Intrusions values are valid.');
end

zeroRecallRows = sum(M.Total_Recalled == 0);
if zeroRecallRows > 0
    addQC('correct_plus_intrusions_zero_rows', zeroRecallRows, 'WARNING', ...
        'Rows with Correct + Intrusions = 0. Recall Precision cannot be computed for these rows.');
else
    addQC('correct_plus_intrusions_zero_rows', 0, 'OK', 'No rows with Correct + Intrusions = 0.');
end

% Correct_Percent consistency check is optional QC.
if ismember('Correct_Percent', M.Properties.VariableNames)
    cp = double(M.Correct_Percent);
    availableCP = isfinite(cp) & M.Total_Recalled > 0;
    if any(availableCP)
        calcPrecision = double(M.Correct) ./ double(M.Total_Recalled);
        diffScale01 = abs(cp(availableCP) - calcPrecision(availableCP));
        diffScale100 = abs((cp(availableCP) ./ 100) - calcPrecision(availableCP));
        mismatch = false(height(M),1);
        mismatch(availableCP) = ~(diffScale01 <= 0.02 | diffScale100 <= 0.02);
        if any(mismatch)
            addQC('correct_percent_mismatch_rows', sum(mismatch), 'WARNING', ...
                'Available Correct_Percent values are not consistent with Correct/(Correct+Intrusions) within tolerance 0.02.');
        else
            addQC('correct_percent_mismatch_rows', 0, 'OK', ...
                'Available Correct_Percent values are consistent with Correct/(Correct+Intrusions).');
        end
    else
        addQC('correct_percent_mismatch_rows', 'not checked', 'INFO', ...
            'Correct_Percent was not available; optional consistency QC was skipped.');
    end
else
    addQC('correct_percent_mismatch_rows', 'not checked', 'INFO', ...
        'Correct_Percent column was not provided; optional consistency QC was skipped.');
end

% Optional valence consistency QC.
valenceCols = ["Positive", "Negative", "Neutral"];
hasValenceCols = ismember(valenceCols, string(M.Properties.VariableNames));
if all(hasValenceCols)
    completeValenceRows = isfinite(double(M.Positive)) & isfinite(double(M.Negative)) & isfinite(double(M.Neutral));
    missingValenceRows = sum(~completeValenceRows);

    if missingValenceRows > 0
        addQC('memory_rows_missing_valence_counts', missingValenceRows, 'WARNING', ...
            'Some memory rows do not contain Positive/Negative/Neutral counts. Accuracy analysis can proceed; these rows are skipped only for valence consistency QC.');
    else
        addQC('memory_rows_missing_valence_counts', 0, 'OK', ...
            'All memory rows contain Positive/Negative/Neutral counts.');
    end

    if any(completeValenceRows)
        valenceMismatch = sum((double(M.Positive(completeValenceRows)) + ...
                               double(M.Negative(completeValenceRows)) + ...
                               double(M.Neutral(completeValenceRows))) ~= ...
                               double(M.Correct(completeValenceRows)));
        if valenceMismatch > 0
            addQC('positive_negative_neutral_not_equal_correct_rows', valenceMismatch, 'WARNING', ...
                'Among rows with available valence counts, Positive + Negative + Neutral does not equal Correct for some rows.');
        else
            addQC('positive_negative_neutral_not_equal_correct_rows', 0, 'OK', ...
                'Among rows with available valence counts, Positive + Negative + Neutral equals Correct.');
        end
    else
        addQC('positive_negative_neutral_not_equal_correct_rows', 'not checked', 'INFO', ...
            'No complete Positive/Negative/Neutral rows were available. Accuracy analysis can proceed; valence consistency QC was skipped.');
    end
else
    addQC('positive_negative_neutral_not_equal_correct_rows', 'not checked', 'INFO', ...
        'Positive/Negative/Neutral columns were not provided. Accuracy analysis can proceed; valence consistency QC was skipped.');
end

%% Perturbation handling from memory
if includePerturbation
    hasPertCol = ismember('perturbation_group', M.Properties.VariableNames) && ...
        any(~ismissing(string(M.perturbation_group)) & strlength(strtrim(string(M.perturbation_group))) > 0);
    hasCondition = ismember('Condition', M.Properties.VariableNames) && ...
        any(~ismissing(string(M.Condition)) & strlength(strtrim(string(M.Condition))) > 0);

    if hasPertCol
        M.perturbation_group = string(M.perturbation_group);
        addQC('perturbation_source', 'memory perturbation_group', 'OK', 'Using memory perturbation_group column.');
    elseif hasCondition
        M.perturbation_group = string(M.Condition);
        addQC('perturbation_source', 'memory Condition', 'INFO', ...
            'Using memory Condition as perturbation_group because no populated perturbation_group column was provided.');
    else
        error(['Perturbation/group was requested, but neither a populated perturbation_group nor Condition column ' ...
               'was found in the memory data.']);
    end
else
    addQC('perturbation_source', 'not used', 'INFO', 'Perturbation/group variable was not requested.');
end

% Keep only memory-side columns needed for the HRV-gait join/modeling. This
% prevents same-named source columns (e.g., Condition or perturbation_group)
% from being automatically renamed by innerjoin.
memoryJoinCols = ["participant_id", "memory_speed_label", "walk_segment", ...
                  "Correct", "Intrusions", "Presented_Words", "Total_Recalled", ...
                  "Recall_Performance", "Recall_Precision"];
if includePerturbation
    memoryJoinCols = [memoryJoinCols, "perturbation_group"];
end
memoryJoinCols = memoryJoinCols(ismember(memoryJoinCols, string(M.Properties.VariableNames)));
M = M(:, cellstr(memoryJoinCols));

%% Standardize HRV-gait table
H = hvgRaw;

participantCol = local_find_column(H, ["participant_id", "Participant", "participant", "VP", "subject_id"]);
if strlength(participantCol) == 0
    error('HRV-gait file is missing participant_id column.');
end
if participantCol ~= "participant_id"
    H.Properties.VariableNames{strcmp(H.Properties.VariableNames, participantCol)} = 'participant_id';
end
H.participant_id = local_standardize_participant_id(H.participant_id);

restCol = local_find_column(H, ["rest_condition", "resting_condition", "rest"]);
if strlength(restCol) == 0
    error('HRV-gait file is missing rest_condition column.');
end
if restCol ~= "rest_condition"
    H.Properties.VariableNames{strcmp(H.Properties.VariableNames, restCol)} = 'rest_condition';
end
H.rest_condition = string(H.rest_condition);

walkCol = local_find_column(H, ["walk_segment", "walking_segment", "segment", "walking_condition"]);
if strlength(walkCol) == 0
    error('HRV-gait file is missing walk_segment / walking_segment column.');
end
if walkCol ~= "walk_segment"
    H.Properties.VariableNames{strcmp(H.Properties.VariableNames, walkCol)} = 'walk_segment';
end
H.walk_segment = upper(string(H.walk_segment));

speedCol = local_find_column(H, ["speed", "walking_speed_kmh", "walking_speed", "speed_kmh"]);
if strlength(speedCol) == 0
    warning('No speed / walking_speed_kmh column found. Speed will be derived from walk_segment where possible.');
    H.speed = local_speed_from_segment(H.walk_segment);
else
    if speedCol ~= "speed"
        H.Properties.VariableNames{strcmp(H.Properties.VariableNames, speedCol)} = 'speed';
    end
    H.speed = local_force_numeric_or_segment(H.speed, H.walk_segment);
end

addQC('hvg_raw_rows_total', height(H), 'INFO', 'Rows in raw HRV-gait table.');
addQC('hvg_raw_participants_total', numel(unique(string(H.participant_id))), 'INFO', 'Unique participants in raw HRV-gait table.');
addQC('hvg_raw_segments', strjoin(unique(string(H.walk_segment), 'stable'), ', '), 'INFO', 'Walking segments present in raw HRV-gait file.');
addQC('hvg_raw_rest_conditions', strjoin(unique(string(H.rest_condition), 'stable'), ', '), 'INFO', 'Rest conditions present in raw HRV-gait file.');

% Optional HRV-gait group column for consistency check.
hGroupCol = local_find_column(H, ["perturbation_group", "kinesis_condition", "Condition", "condition", "group"]);
if strlength(hGroupCol) > 0
    H.perturbation_group_hvg = string(H.(hGroupCol));
    % Avoid duplicate non-key variable names during the later innerjoin.
    if strcmpi(hGroupCol, "perturbation_group")
        H.perturbation_group = [];
    end
    addQC('hvg_group_column_detected', hGroupCol, 'INFO', 'HRV-gait group column detected for consistency checks.');
else
    addQC('hvg_group_column_detected', 'none', 'INFO', 'No HRV-gait group column detected.');
end

%% Keep only user-selected FWW segments for memory analysis
fwSegments = unique(string(M.walk_segment), 'stable');
if any(~startsWith(fwSegments, "FWW_"))
    error('Memory files must map only to FWW walking segments. Found: %s', strjoin(fwSegments, ', '));
end

bwRows = sum(startsWith(H.walk_segment, "BW"));
Hfw = H(ismember(H.walk_segment, fwSegments), :);

addQC('bw_rows_excluded_from_memory_models', bwRows, 'OK', ...
    'BW rows were present in source data but excluded before memory merge.');
addQC('fw_rows_retained_for_memory_models', height(Hfw), 'OK', ...
    "Only user-selected FWW segment(s) are retained for memory analysis: " + strjoin(fwSegments, ', '));

if height(Hfw) == 0
    error('None of the selected FWW segment(s) were found in HRV-gait file: %s', strjoin(fwSegments, ', '));
end

% Each participant x FW segment x rest condition must be unique. Otherwise
% the memory join would duplicate model rows silently.
local_assert_unique_keys(Hfw, ["participant_id", "walk_segment", "rest_condition"], ...
    'HRV-gait data contain duplicate participant x walk_segment x rest_condition rows.');

%% Participant matching QC
memoryParticipants = unique(string(M.participant_id));
hvgParticipants = unique(string(Hfw.participant_id));
memNotHvg = setdiff(memoryParticipants, hvgParticipants, 'stable');
hvgNotMem = setdiff(hvgParticipants, memoryParticipants, 'stable');

if isempty(memNotHvg)
    addQC('participants_memory_not_in_hvg', 'none', 'OK', 'All memory participants exist in FW HRV-gait data.');
else
    addQC('participants_memory_not_in_hvg', strjoin(memNotHvg, ', '), 'WARNING', 'These memory participants were not found in FW HRV-gait data.');
end
if isempty(hvgNotMem)
    addQC('participants_hvg_not_in_memory', 'none', 'OK', 'All FW HRV-gait participants exist in memory data.');
else
    addQC('participants_hvg_not_in_memory', strjoin(hvgNotMem, ', '), 'WARNING', 'These FW HRV-gait participants were not found in memory data.');
end

%% Merge memory with FW gait/HRV rows
merged = innerjoin(M, Hfw, 'Keys', {'participant_id', 'walk_segment'});
if height(merged) == 0
    error('Merged table has zero rows. Check participant_id and FWW segment labels.');
end

addQC('merged_rows_total', height(merged), 'INFO', 'Rows after memory x FWW HRV-gait merge.');
addQC('merged_participants_total', numel(unique(string(merged.participant_id))), 'INFO', 'Unique participants after merge.');
addQC('merged_segments', strjoin(unique(string(merged.walk_segment), 'stable'), ', '), 'OK', ...
    'Segments in merged model data. Should only include the user-selected FWW segment(s).');

if any(~ismember(string(merged.walk_segment), fwSegments))
    addQC('non_fw_rows_in_merged_data', sum(~ismember(string(merged.walk_segment), fwSegments)), 'ERROR', ...
        'Non-FW rows entered merged data. This should not happen.');
else
    addQC('non_fw_rows_in_merged_data', 0, 'OK', 'No BW or non-FW rows entered merged data.');
end

% Speed-segment consistency.
expectedSpeed = local_speed_from_segment(merged.walk_segment);
badSpeedRows = isfinite(expectedSpeed) & isfinite(merged.speed) & ...
    abs(double(merged.speed) - expectedSpeed) > 1e-6;
if any(badSpeedRows)
    error('Numeric speed does not match the speed encoded in walk_segment for %d merged row(s).', sum(badSpeedRows));
else
    addQC('memory_speed_walk_segment_mismatch_rows', 0, 'OK', ...
        'Memory walk_segment labels match the numeric speed information.');
end

% Perturbation consistency.
if includePerturbation
    if ~ismember('perturbation_group', merged.Properties.VariableNames)
        if ismember('perturbation_group_hvg', merged.Properties.VariableNames)
            merged.perturbation_group = string(merged.perturbation_group_hvg);
            addQC('perturbation_final_source', 'HRV-gait group column', 'WARNING', ...
                'Using HRV-gait group column because memory perturbation_group was not available.');
        else
            error('Perturbation/group was requested, but no usable perturbation variable was available after merging.');
        end
    end
    merged.perturbation_group = string(merged.perturbation_group);

    if all(ismissing(merged.perturbation_group) | strlength(strtrim(merged.perturbation_group)) == 0)
        error('Perturbation/group was requested, but the merged perturbation_group column is empty.');
    end

    if ismember('perturbation_group_hvg', merged.Properties.VariableNames)
        memGroup = string(merged.perturbation_group);
        hvgGroup = string(merged.perturbation_group_hvg);
        comparable = ~ismissing(memGroup) & ~ismissing(hvgGroup) & ...
            strlength(strtrim(memGroup)) > 0 & strlength(strtrim(hvgGroup)) > 0;
        mismatchGroup = comparable & (memGroup ~= hvgGroup);
        if any(mismatchGroup)
            addQC('memory_hvg_group_mismatch_rows', sum(mismatchGroup), 'WARNING', ...
                'Memory perturbation_group and HRV-gait group column differ in some merged rows.');
        else
            addQC('memory_hvg_group_mismatch_rows', 0, 'OK', ...
                'Available memory and HRV-gait perturbation labels are consistent.');
        end
    end
end

%% Predictor checks, transformations, and z-scoring
zNames = strings(0, 1);

% HRV predictors first so their explicit preprocessing policy is applied.
for i = 1:numel(selectedHRV)
    pred = selectedHRV(i);
    canonical = selectedHRVCanonical(i);
    transform = selectedHRVTransforms(i);

    values = local_get_numeric_predictor(merged, pred);
    merged.(pred) = values;

    missingRate = mean(~isfinite(values));
    addQC("missing_rate_" + pred, sprintf('%.4f', missingRate), 'INFO', ...
        'Missing/non-finite rate for selected HRV predictor in merged table.');

    transformed = values;
    zName = string(matlab.lang.makeValidName("z_" + pred));
    zNames(end+1,1) = zName; %#ok<AGROW>

    if transform == "ln"
        invalidForLog = isfinite(values) & values <= 0;
        if any(invalidForLog)
            error('HRV predictor "%s" requires automatic natural-log transformation but contains %d non-positive finite value(s).', ...
                pred, sum(invalidForLog));
        end
        transformed(isfinite(values)) = log(values(isfinite(values)));
        addQC("transform_" + pred, 'ln_then_z', 'OK', ...
            "Automatic natural-log transformation followed by z-standardization. Canonical predictor: " + canonical);
        merged.(zName) = local_zscore_or_nan(transformed, pred, @addQC);

    elseif transform == "asis"
        % The selected source column was already z-standardized. Copy it to
        % the model's stable z_<source> name without transforming it again.
        merged.(zName) = transformed;
        addQC("transform_" + pred, 'input_z_as_is', 'OK', ...
            "Source predictor was already z-standardized and was used as-is. Canonical predictor: " + canonical);
        addQC("zscore_status_" + pred, 'input_z_as_is', 'OK', ...
            'No second z-standardization was applied.');

    else
        addQC("transform_" + pred, 'z_only', 'OK', ...
            "No log transformation; z-standardization only. Canonical predictor: " + canonical);
        merged.(zName) = local_zscore_or_nan(transformed, pred, @addQC);
    end
end

% Gait predictors are z-standardized without automatic log transformation.
for i = 1:numel(selectedGait)
    pred = selectedGait(i);
    canonical = selectedGaitCanonical(i);

    values = local_get_numeric_predictor(merged, pred);
    merged.(pred) = values;

    missingRate = mean(~isfinite(values));
    addQC("missing_rate_" + pred, sprintf('%.4f', missingRate), 'INFO', ...
        'Missing/non-finite rate for selected gait predictor in merged table.');
    addQC("transform_" + pred, 'z_only', 'OK', ...
        "Gait predictor z-standardized without automatic log transformation. Canonical predictor: " + canonical);

    zName = string(matlab.lang.makeValidName("z_" + pred));
    zNames(end+1,1) = zName; %#ok<AGROW>
    merged.(zName) = local_zscore_or_nan(values, pred, @addQC);
end

%% Final output subset
baseCols = ["participant_id", "speed", "memory_speed_label", "walk_segment", "rest_condition"];
if includePerturbation && ismember('perturbation_group', merged.Properties.VariableNames)
    baseCols = [baseCols, "perturbation_group"];
end
memoryCols = ["Correct", "Intrusions", "Presented_Words", "Total_Recalled", "Recall_Performance", "Recall_Precision"];
finalCols = unique([baseCols, memoryCols, selectedPredictors(:).', zNames(:).'], 'stable');
finalCols = finalCols(ismember(finalCols, string(merged.Properties.VariableNames)));
mergedOut = merged(:, cellstr(finalCols));

qcSummary = table(qcMetric, qcValue, qcSeverity, qcDetails, ...
    'VariableNames', {'metric', 'value', 'severity', 'details'});
end

function values = local_get_numeric_predictor(T, pred)
    if ~ismember(pred, string(T.Properties.VariableNames))
        error('Selected predictor "%s" was not found in merged table.', pred);
    end

    values = T.(pred);
    if ~isnumeric(values)
        raw = string(values);
        converted = str2double(raw);
        bad = isnan(converted) & ~ismissing(raw) & strlength(strtrim(raw)) > 0;
        if any(bad)
            error('Selected predictor "%s" is not numeric and cannot be converted to numeric.', pred);
        end
        values = converted;
    else
        values = double(values);
    end

    values = double(values);
    values(~isfinite(values)) = NaN;
end

function z = local_zscore_or_nan(values, pred, addQC)
    finiteValues = values(isfinite(values));
    if isempty(finiteValues)
        z = NaN(size(values));
        addQC("zscore_status_" + pred, 'failed', 'ERROR', ...
            'Predictor has no finite values. Models using this predictor will be skipped.');
        return;
    end

    sdVal = std(finiteValues);
    meanVal = mean(finiteValues);
    if ~isfinite(sdVal) || sdVal == 0
        z = NaN(size(values));
        addQC("zscore_status_" + pred, 'failed', 'ERROR', ...
            'Predictor standard deviation is zero or non-finite. Models using this predictor will be skipped.');
    else
        z = NaN(size(values));
        finiteMask = isfinite(values);
        z(finiteMask) = (values(finiteMask) - meanVal) ./ sdVal;
        addQC("zscore_status_" + pred, 'ok', 'OK', 'Final model predictor z-score column was created.');
    end
end

function local_assert_unique_keys(T, keyNames, messageText)
    keyNames = string(keyNames);
    missingKeys = setdiff(keyNames, string(T.Properties.VariableNames), 'stable');
    if ~isempty(missingKeys)
        error('Cannot check duplicate keys because required key column(s) are missing: %s', strjoin(missingKeys, ', '));
    end

    [~, ~, g] = unique(T(:, cellstr(keyNames)), 'rows');
    counts = accumarray(g, 1);
    if any(counts > 1)
        error('%s Number of duplicated key groups: %d.', messageText, sum(counts > 1));
    end
end

function col = local_find_column(T, candidates)
    names = string(T.Properties.VariableNames);
    col = "";
    for i = 1:numel(candidates)
        idx = find(strcmpi(names, candidates(i)), 1, 'first');
        if ~isempty(idx)
            col = names(idx);
            return;
        end
    end
end

function x = local_force_numeric_or_segment(x, segment)
    if isnumeric(x)
        x = double(x);
        return;
    end
    converted = str2double(string(x));
    raw = string(x);
    if all(~isnan(converted) | ismissing(raw) | strlength(strtrim(raw)) == 0)
        x = converted;
    else
        x = local_speed_from_segment(segment);
    end
end

function speed = local_speed_from_segment(segment)
    segment = string(segment);
    speed = NaN(size(segment));
    for i = 1:numel(segment)
        token = regexp(char(segment(i)), '(\d+(\.\d+)?)\s*KMH', 'tokens', 'once');
        if ~isempty(token)
            speed(i) = str2double(token{1});
        end
    end
end
