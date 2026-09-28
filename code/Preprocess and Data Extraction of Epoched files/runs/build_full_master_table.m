function build_full_master_table()
%BUILD_FULL_MASTER_TABLE Convert Stage 1 long summaries into clean wide table.
%
% Rule:
%   Only analytically relevant signal-source combinations are added.
%
% Included sources:
%   Heart:
%       ecg
%       hr_live
%       hrvrmssd_live
%       temp
%       acc
%       angularrate
%       nn_live
%       bpmbxb_live
%
%   Hip:
%       acc
%       angularrate
%       movementacceleration
%       stepcount
%
% ECG:
%   ECG is read from the ECG all-test summary file if available.
%   Only Heart ECG is included in the FULL table.

fprintf('\n=====================================\n');
fprintf('BUILD FULL MASTER TABLE START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));

cfg = get_preprocessing_config();

input_file = fullfile(cfg.paths.features_root, 'stage1_signal_summaries_long.csv');

if ~isfile(input_file)
    error('build_full_master_table:MissingInput', ...
        'Could not find input file: %s', input_file);
end

T = readtable(input_file);

fprintf('\nLoaded Stage 1 long summary table:\n%s\n', input_file);
fprintf('Original Stage 1 rows: %d\n', height(T));
fprintf('Original Stage 1 columns: %d\n', width(T));

%% ------------------------------------------------------------------------
% Add ECG summary rows if available
% -------------------------------------------------------------------------

ecg_input_file = fullfile( ...
    cfg.paths.qc_root, ...
    'ECG Tests', ...
    'test_clean_ecg_all_summary.csv');

if isfile(ecg_input_file)

    ECG = readtable(ecg_input_file);

    fprintf('\nLoaded ECG summary table:\n%s\n', ecg_input_file);
    fprintf('Original ECG rows: %d\n', height(ECG));
    fprintf('Original ECG columns: %d\n', width(ECG));

    % Keep only Heart ECG.
    ECG = ECG(strcmp(string(ECG.sensor), "Heart"), :);

    % Keep only successfully processed ECG rows.
    if ismember('ran_successfully', ECG.Properties.VariableNames)
        ECG = ECG(ECG.ran_successfully == true, :);
    end

    fprintf('Heart ECG rows added to FULL table source: %d\n', height(ECG));

    % ECG rows need the same required metadata columns as Stage 1.
    ECG.signal_name = repmat({'ecg'}, height(ECG), 1);

    if ~ismember('file_status', ECG.Properties.VariableNames)
        ECG.file_status = repmat({'ecg_processed'}, height(ECG), 1);
    end

    % Remove columns that are execution bookkeeping, not dataset features.
    drop_ecg_cols = { ...
        'ran_successfully', ...
        'error_message'};

    for d = 1:numel(drop_ecg_cols)
        if ismember(drop_ecg_cols{d}, ECG.Properties.VariableNames)
            ECG.(drop_ecg_cols{d}) = [];
        end
    end

    % Combine Stage 1 and ECG tables despite different feature columns.
    T = local_union_append_tables(T, ECG);

else
    warning('build_full_master_table:MissingECGSummary', ...
        ['ECG summary file not found. Building FULL table without ECG: ', ...
         '%s'], ecg_input_file);
end

%% ------------------------------------------------------------------------
% Normalize metadata columns to consistent text format
% -------------------------------------------------------------------------

text_cols = {'participant_id','sensor','segment_name','segment_type','file_status','signal_name'};

for c = 1:numel(text_cols)
    col = text_cols{c};

    if ismember(col, T.Properties.VariableNames)
        T.(col) = cellstr(string(T.(col)));
    end
end

%% ------------------------------------------------------------------------
% Keep only analytically relevant signal-source combinations
% -------------------------------------------------------------------------

keep_heart_signals = { ...
    'ecg', ...
    'hr_live', ...
    'hrvrmssd_live', ...
    'temp', ...
    'acc', ...
    'angularrate', ...
    'nn_live', ...
    'bpmbxb_live'};

keep_hip_signals = { ...
    'acc', ...
    'angularrate', ...
    'movementacceleration', ...
    'stepcount'};

T.signal_name = string(T.signal_name);
T.sensor = string(T.sensor);

keep_heart_signals = string(keep_heart_signals);
keep_hip_signals   = string(keep_hip_signals);

is_heart_keep = (T.sensor == "Heart") & ismember(T.signal_name, keep_heart_signals);
is_hip_keep   = (T.sensor == "Hip")   & ismember(T.signal_name, keep_hip_signals);

T = T(is_heart_keep | is_hip_keep, :);

fprintf('\nRows after analytical source filtering: %d\n', height(T));
fprintf('Columns after ECG merge/filtering: %d\n', width(T));

%% ------------------------------------------------------------------------
% Required columns
% -------------------------------------------------------------------------

id_cols = {'participant_id','sensor','segment_name','segment_type','file_status','signal_name'};

for i = 1:numel(id_cols)
    if ~ismember(id_cols{i}, T.Properties.VariableNames)
        error('build_full_master_table:MissingColumn', ...
            'Required column missing: %s', id_cols{i});
    end
end

base_id_cols = {'participant_id','sensor','segment_name','segment_type','file_status'};
candidate_feature_cols = setdiff(T.Properties.VariableNames, id_cols, 'stable');

%% ------------------------------------------------------------------------
% Create one row per participant/sensor/segment
% -------------------------------------------------------------------------

wide_table = unique(T(:, base_id_cols), 'rows', 'stable');

%% ------------------------------------------------------------------------
% Add only meaningful signal-specific features
% -------------------------------------------------------------------------

for i = 1:height(T)

    participant_id = T.participant_id{i};
    sensor = T.sensor{i};
    segment_name = T.segment_name{i};
    signal_name = T.signal_name{i};

    key_mask = ...
        strcmp(wide_table.participant_id, participant_id) & ...
        strcmp(wide_table.sensor, sensor) & ...
        strcmp(wide_table.segment_name, segment_name);

    if ~any(key_mask)
        warning('No matching wide row for %s | %s | %s', ...
            participant_id, sensor, segment_name);
        continue;
    end

    for j = 1:numel(candidate_feature_cols)

        old_col = candidate_feature_cols{j};
        value = T.(old_col)(i);

        % Skip empty values so meaningless signal-feature combinations
        % are not created.
        if local_is_missing_or_empty(value)
            continue;
        end

        new_col = matlab.lang.makeValidName([signal_name '_' old_col]);

        if ~ismember(new_col, wide_table.Properties.VariableNames)
            wide_table.(new_col) = local_empty_column_like(T.(old_col), height(wide_table));
        end

        wide_table.(new_col)(key_mask) = value;
    end
end

%% ------------------------------------------------------------------------
% Save
% -------------------------------------------------------------------------

output_file = fullfile(cfg.paths.features_root, 'FULL_master_table_stage1_cleanwide.csv');
writetable(wide_table, output_file);

fprintf('\nSaved clean wide FULL master table:\n%s\n', output_file);
fprintf('Rows: %d\n', height(wide_table));
fprintf('Columns: %d\n', width(wide_table));

fprintf('\n=====================================\n');
fprintf('BUILD FULL MASTER TABLE END\n');
fprintf('=====================================\n');

end

%% ========================================================================
function T_out = local_union_append_tables(T1, T2)
%LOCAL_UNION_APPEND_TABLES Append two tables with different columns.
%
% Missing columns are created using type-compatible empty/default values.

all_vars = union(T1.Properties.VariableNames, T2.Properties.VariableNames, 'stable');

for i = 1:numel(all_vars)
    var_name = all_vars{i};

    if ~ismember(var_name, T1.Properties.VariableNames)
        T1.(var_name) = local_empty_column_like(T2.(var_name), height(T1));
    end

    if ~ismember(var_name, T2.Properties.VariableNames)
        T2.(var_name) = local_empty_column_like(T1.(var_name), height(T2));
    end
end

T1 = T1(:, all_vars);
T2 = T2(:, all_vars);

T_out = [T1; T2];

end

%% ========================================================================
function tf = local_is_missing_or_empty(value)

tf = false;

if isnumeric(value)
    tf = all(isnan(value));

elseif islogical(value)
    % logical false is still meaningful, so do not skip it
    tf = false;

elseif iscell(value)
    if isempty(value)
        tf = true;
    else
        v = value{1};

        if isempty(v)
            tf = true;
        elseif ischar(v)
            tf = isempty(strtrim(v));
        elseif isstring(v)
            tf = ismissing(v) || strlength(v) == 0;
        elseif isnumeric(v)
            tf = all(isnan(v));
        elseif islogical(v)
            tf = false;
        end
    end

elseif isstring(value)
    tf = ismissing(value) || strlength(value) == 0;

elseif iscategorical(value)
    tf = isundefined(value);

else
    tf = false;
end

end

%% ========================================================================
function empty_col = local_empty_column_like(example_col, n)

if isnumeric(example_col)
    empty_col = NaN(n, 1);

elseif islogical(example_col)
    empty_col = false(n, 1);

elseif iscell(example_col)
    empty_col = repmat({''}, n, 1);

elseif isstring(example_col)
    empty_col = strings(n, 1);

elseif iscategorical(example_col)
    empty_col = categorical(repmat({''}, n, 1));

else
    empty_col = repmat({''}, n, 1);
end

end