function out = build_analysis_table(cfg, merged_full_table)
%BUILD_ANALYSIS_TABLE Collapse Heart/Hip rows into one analysis-ready row.
%
% Input:
%   FULL_master_table_with_kinesis.csv style table
%
% Output:
%   one row = participant_id + segment_name
%
% Contains:
%   - participant_id
%   - segment_name
%   - segment_type
%   - kinesis_condition
%   - heart_* features
%   - hip_* features
%   - kinesis_* outcomes

if nargin < 2
    error('build_analysis_table:MissingInputs', ...
        'cfg and merged_full_table are required.');
end

T = merged_full_table;

out = struct();
out.analysis_table = table();
out.qc = struct();
out.warnings = {};

%% Normalize metadata
T.participant_id = cellstr(string(T.participant_id));
T.sensor = cellstr(string(T.sensor));
T.segment_name = cellstr(string(T.segment_name));
T.segment_type = cellstr(string(T.segment_type));

if ismember('kinesis_condition', T.Properties.VariableNames)
    T.kinesis_condition = cellstr(string(T.kinesis_condition));
end

%% Required columns
required_cols = {'participant_id','sensor','segment_name','segment_type'};

for i = 1:numel(required_cols)
    if ~ismember(required_cols{i}, T.Properties.VariableNames)
        error('build_analysis_table:MissingColumn', ...
            'Required column missing: %s', required_cols{i});
    end
end

%% Split Heart and Hip rows
heart_rows = strcmp(T.sensor, 'Heart');
hip_rows   = strcmp(T.sensor, 'Hip');

Heart = T(heart_rows, :);
Hip   = T(hip_rows, :);

%% Keys
key_cols = {'participant_id','segment_name'};

%% Keep participant-level metadata
meta_cols = {'participant_id','segment_name','segment_type','kinesis_condition'};
meta_cols = meta_cols(ismember(meta_cols, T.Properties.VariableNames));

Base = unique(T(:, meta_cols), 'rows', 'stable');

%% Feature columns
exclude_cols = {'participant_id','sensor','segment_name','segment_type','file_status'};
if ismember('kinesis_condition', T.Properties.VariableNames)
    exclude_cols{end+1} = 'kinesis_condition';
end

all_cols = T.Properties.VariableNames;
candidate_cols = setdiff(all_cols, exclude_cols, 'stable');

kinesis_cols = candidate_cols(startsWith(candidate_cols, 'kinesis_'));

% Kinesis outcomes are participant+segment-level, not sensor-specific.
% Use Heart rows preferentially, but either Heart or Hip contains same values.
K = T(:, [key_cols, kinesis_cols]);
K = local_take_first_by_key(K, key_cols);

%% Heart feature columns
heart_candidate_cols = setdiff(candidate_cols, kinesis_cols, 'stable');
heart_candidate_cols = heart_candidate_cols( ...
    startsWith(heart_candidate_cols, 'ecg_') | ...
    startsWith(heart_candidate_cols, 'hr_live_') | ...
    startsWith(heart_candidate_cols, 'hrvrmssd_live_') | ...
    startsWith(heart_candidate_cols, 'nn_live_') | ...
    startsWith(heart_candidate_cols, 'bpmbxb_live_') | ...
    startsWith(heart_candidate_cols, 'temp_') | ...
    startsWith(heart_candidate_cols, 'acc_') | ...
    startsWith(heart_candidate_cols, 'angularrate_'));

fprintf('\nHeart candidate cols containing ECG:\n');
disp(heart_candidate_cols(startsWith(heart_candidate_cols, 'ecg_'))');

Heart_features = Heart(:, [key_cols, heart_candidate_cols]);
Heart_features = local_prefix_feature_columns(Heart_features, key_cols, 'heart_');

%% Hip feature columns
hip_candidate_cols = setdiff(candidate_cols, kinesis_cols, 'stable');
hip_candidate_cols = hip_candidate_cols( ...
    startsWith(hip_candidate_cols, 'acc_') | ...
    startsWith(hip_candidate_cols, 'angularrate_') | ...
    startsWith(hip_candidate_cols, 'movementacceleration_') | ...
    startsWith(hip_candidate_cols, 'stepcount_'));

Hip_features = Hip(:, [key_cols, hip_candidate_cols]);
Hip_features = local_prefix_feature_columns(Hip_features, key_cols, 'hip_');

%% Merge Base + Heart + Hip + Kinesis
A = Base;

A = outerjoin(A, Heart_features, ...
    'Keys', key_cols, ...
    'MergeKeys', true, ...
    'Type', 'left');

A = outerjoin(A, Hip_features, ...
    'Keys', key_cols, ...
    'MergeKeys', true, ...
    'Type', 'left');

A = outerjoin(A, K, ...
    'Keys', key_cols, ...
    'MergeKeys', true, ...
    'Type', 'left');

%% Remove completely empty feature columns
id_cols_final = {'participant_id','segment_name','segment_type','kinesis_condition'};
id_cols_final = id_cols_final(ismember(id_cols_final, A.Properties.VariableNames));

feature_cols_final = setdiff(A.Properties.VariableNames, id_cols_final, 'stable');

empty_cols = false(size(feature_cols_final));

for i = 1:numel(feature_cols_final)
    col = feature_cols_final{i};
    empty_cols(i) = local_column_all_missing(A.(col));
end

cols_to_drop = feature_cols_final(empty_cols);

if ~isempty(cols_to_drop)
    A(:, cols_to_drop) = [];
    out.warnings{end+1} = sprintf( ...
        'Dropped %d completely empty feature columns.', ...
        numel(cols_to_drop));
end

%% QC
out.qc.n_input_rows = height(T);
out.qc.n_heart_rows = height(Heart);
out.qc.n_hip_rows = height(Hip);
out.qc.n_analysis_rows = height(A);
out.qc.n_participants = numel(unique(A.participant_id));
out.qc.n_segments = numel(unique(A.segment_name));
out.qc.n_features = width(A) - numel(id_cols_final);
out.qc.n_dropped_empty_columns = numel(cols_to_drop);

if ismember('kinesis_condition', A.Properties.VariableNames)
    out.qc.n_rows_without_condition = sum(cellfun(@isempty, A.kinesis_condition));
else
    out.qc.n_rows_without_condition = height(A);
    out.warnings{end+1} = 'kinesis_condition column missing from analysis table.';
end

out.qc.warning_messages = strjoin(out.warnings, ' | ');

out.analysis_table = A;

end

%% ========================================================================
function T_out = local_prefix_feature_columns(T_in, key_cols, prefix)

T_out = T_in;

vars = T_out.Properties.VariableNames;

for i = 1:numel(vars)
    old_name = vars{i};

    if ismember(old_name, key_cols)
        continue;
    end

    new_name = matlab.lang.makeValidName([prefix old_name]);
    T_out.Properties.VariableNames{strcmp(T_out.Properties.VariableNames, old_name)} = new_name;
end

end

%% ========================================================================
function T_out = local_take_first_by_key(T_in, key_cols)
%LOCAL_TAKE_FIRST_BY_KEY Keep first row per participant+segment key.

if isempty(T_in)
    T_out = T_in;
    return;
end

[~, idx] = unique(T_in(:, key_cols), 'rows', 'stable');
T_out = T_in(idx, :);

end

%% ========================================================================
function tf = local_column_all_missing(x)

if isnumeric(x)
    tf = all(isnan(x));

elseif islogical(x)
    % false is meaningful, so logical columns are never considered missing
    tf = false;

elseif iscell(x)
    tf = all(cellfun(@(v) isempty(v) || ...
        (ischar(v) && isempty(strtrim(v))) || ...
        (isstring(v) && (ismissing(v) || strlength(v) == 0)), x));

elseif isstring(x)
    tf = all(ismissing(x) | strlength(x) == 0);

elseif iscategorical(x)
    tf = all(isundefined(x));

else
    tf = false;
end

end