function out = merge_kinesis_to_full_table(cfg, full_table, kinesis_cleaned)
%MERGE_KINESIS_TO_FULL_TABLE Merge cleaned Kinesis outcomes into FULL table.
%
% Merge key:
%   participant_id + segment_name
%
% Kinesis only maps to walking segments:
%   BW_1KMH
%   BW_4KMH
%   FWW_1KMH
%   FWW_4KMH
%
% Rest segments remain in the table, but Kinesis columns stay missing.

if nargin < 3
    error('merge_kinesis_to_full_table:MissingInputs', ...
        'cfg, full_table, and kinesis_cleaned are required.');
end

out = struct();
out.merged_table = table();
out.qc = struct();
out.warnings = {};

F = full_table;
K = kinesis_cleaned.cleaned_table;

%% Normalize key columns
F.participant_id = cellstr(string(F.participant_id));
F.segment_name = cellstr(string(F.segment_name));

K.participant_id = cellstr(string(K.participant_id));
K.segment_name = cellstr(string(K.segment_name));

%% Keep only Kinesis walking rows
walking_segments = {'BW_1KMH','BW_4KMH','FWW_1KMH','FWW_4KMH'};
K = K(ismember(K.segment_name, walking_segments), :);

%% Check duplicate keys in Kinesis
keyK = K(:, {'participant_id','segment_name'});
[~, unique_idx] = unique(keyK, 'rows', 'stable');

duplicate_mask = true(height(K), 1);
duplicate_mask(unique_idx) = false;

if any(duplicate_mask)
    out.warnings{end+1} = sprintf( ...
        'Duplicate Kinesis participant-segment rows found: %d.', ...
        sum(duplicate_mask));
end

%% Select Kinesis columns to merge
key_cols = {'participant_id','segment_name'};

kinesis_cols = K.Properties.VariableNames;
merge_cols = setdiff(kinesis_cols, { ...
    'kinesis_task', ...
    'kinesis_speed', ...
    'is_duplicate_kinesis_key'}, 'stable');

% Keep keys + condition + gait features
K_merge = K(:, merge_cols);

%% Merge
M = outerjoin( ...
    F, ...
    K_merge, ...
    'Keys', key_cols, ...
    'MergeKeys', true, ...
    'Type', 'left');

%% Add participant-level condition also to rest segments
% Because Kinesis condition is participant-level and should be available
% for all rows, including RS_EO1 / RS_EC / RS_EO2.
PCT = kinesis_cleaned.participant_condition_table;
PCT.participant_id = cellstr(string(PCT.participant_id));

if ismember('kinesis_condition', M.Properties.VariableNames)
    M.kinesis_condition_original_segment_only = M.kinesis_condition;
    M.kinesis_condition = [];
end

M = outerjoin( ...
    M, ...
    PCT(:, {'participant_id','kinesis_condition'}), ...
    'Keys', 'participant_id', ...
    'MergeKeys', true, ...
    'Type', 'left');

%% QC checks
is_walk = ismember(M.segment_name, walking_segments);
has_condition = ~cellfun(@isempty, cellstr(string(M.kinesis_condition)));

gait_feature_cols = M.Properties.VariableNames(startsWith(M.Properties.VariableNames, 'kinesis_'));
gait_feature_cols = setdiff(gait_feature_cols, { ...
    'kinesis_condition', ...
    'kinesis_condition_original_segment_only'}, 'stable');

has_any_gait = false(height(M), 1);

for i = 1:numel(gait_feature_cols)
    col = gait_feature_cols{i};

    if isnumeric(M.(col))
        has_any_gait = has_any_gait | ~isnan(M.(col));
    else
        has_any_gait = has_any_gait | ~ismissing(M.(col));
    end
end

walk_without_gait = is_walk & ~has_any_gait;
rest_with_gait = ~is_walk & has_any_gait;
rows_without_condition = ~has_condition;

if any(walk_without_gait)
    out.warnings{end+1} = sprintf( ...
        'Walking rows without Kinesis gait features: %d.', ...
        sum(walk_without_gait));
end

if any(rest_with_gait)
    out.warnings{end+1} = sprintf( ...
        'Rest rows unexpectedly have Kinesis gait features: %d.', ...
        sum(rest_with_gait));
end

if any(rows_without_condition)
    out.warnings{end+1} = sprintf( ...
        'Rows without participant-level Kinesis condition: %d.', ...
        sum(rows_without_condition));
end

%% Store
out.merged_table = M;

out.qc.n_full_rows_before_merge = height(F);
out.qc.n_kinesis_rows_used = height(K);
out.qc.n_rows_after_merge = height(M);
out.qc.n_walking_rows = sum(is_walk);
out.qc.n_rest_rows = sum(~is_walk);
out.qc.n_walk_rows_without_gait = sum(walk_without_gait);
out.qc.n_rest_rows_with_gait = sum(rest_with_gait);
out.qc.n_rows_without_condition = sum(rows_without_condition);
out.qc.n_duplicate_kinesis_rows = sum(duplicate_mask);
out.qc.n_kinesis_feature_columns = numel(gait_feature_cols);
out.qc.warning_messages = strjoin(out.warnings, ' | ');

end