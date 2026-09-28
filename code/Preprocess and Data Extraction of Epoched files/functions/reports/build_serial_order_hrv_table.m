function build_serial_order_hrv_table()
%BUILD_SERIAL_ORDER_HRV_TABLE Build resting-state HRV serial-order table.
%
% Purpose:
%   Creates an analysis-ready resting-state HRV table for checking the
%   behavior of EO1, EC, and EO2 separately.
%
% Important thesis decision:
%   EO1, EC, and EO2 are kept separate. No EO averaging is performed here.
%
% Input:
%   Output/Feature Tables/ANALYSIS_TABLE_participant_segment.csv
%
% Outputs:
%   Output/Feature Tables/LMM_serial_order_HRV_rest.csv
%   Output/Feature Tables/Serial_Order_HRV_QC.xlsx

fprintf('\n=====================================\n');
fprintf('BUILD SERIAL ORDER HRV TABLE START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(fileparts(mfilename('fullpath'))))));

cfg = get_preprocessing_config();

input_file = fullfile(cfg.paths.features_root, 'ANALYSIS_TABLE_participant_segment.csv');
output_csv = fullfile(cfg.paths.features_root, 'LMM_serial_order_HRV_rest.csv');
output_qc_xlsx = fullfile(cfg.paths.features_root, 'Serial_Order_HRV_QC.xlsx');

if ~isfile(input_file)
    error('build_serial_order_hrv_table:MissingInput', ...
        ['Analysis table not found:\n%s\n', ...
         'Run run_build_analysis_table before build_serial_order_hrv_table.'], ...
        input_file);
end

T = readtable(input_file);

fprintf('\nLoaded analysis table:\n%s\n', input_file);
fprintf('Rows: %d\n', height(T));
fprintf('Columns: %d\n', width(T));

required_cols = { ...
    'participant_id', ...
    'segment_name', ...
    'heart_ecg_meanHR_ecg', ...
    'heart_ecg_RMSSD_ecg', ...
    'heart_ecg_SDNN_ecg', ...
    'heart_ecg_pNN50_ecg', ...
    'heart_ecg_LF_ecg', ...
    'heart_ecg_HF_ecg', ...
    'heart_ecg_LFHF_ecg', ...
    'heart_ecg_ecg_rr_count_valid', ...
    'heart_ecg_ecg_rr_valid_fraction'};

missing_cols = required_cols(~ismember(required_cols, T.Properties.VariableNames));

if ~isempty(missing_cols)
    fprintf('\nMissing required columns:\n');
    disp(missing_cols');
    error('build_serial_order_hrv_table:MissingColumns', ...
        ['Required HRV columns are missing from ANALYSIS_TABLE_participant_segment.csv.\n', ...
         'Most likely run_clean_ecg_all, build_full_master_table, ', ...
         'run_merge_kinesis_to_full_table, and run_build_analysis_table need to be rerun.']);
end

T.participant_id = cellstr(string(T.participant_id));
T.segment_name = cellstr(string(T.segment_name));

rest_segments = {'RS_EO1', 'RS_EC', 'RS_EO2'};
rest_mask = ismember(T.segment_name, rest_segments);
Rest = T(rest_mask, :);

if isempty(Rest)
    error('build_serial_order_hrv_table:NoRestRows', ...
        'No RS_EO1, RS_EC, or RS_EO2 rows found in the analysis table.');
end

rest_condition = strings(height(Rest), 1);
rest_order = NaN(height(Rest), 1);

for i = 1:height(Rest)
    seg = string(Rest.segment_name{i});

    if seg == "RS_EO1"
        rest_condition(i) = "EO1";
        rest_order(i) = 1;
    elseif seg == "RS_EC"
        rest_condition(i) = "EC";
        rest_order(i) = 2;
    elseif seg == "RS_EO2"
        rest_condition(i) = "EO2";
        rest_order(i) = 3;
    end
end

S = table();
S.participant_id = Rest.participant_id;
S.rest_condition = cellstr(rest_condition);
S.rest_order = rest_order;
S.meanHR_ecg = Rest.heart_ecg_meanHR_ecg;
S.RMSSD_ecg = Rest.heart_ecg_RMSSD_ecg;
S.SDNN_ecg = Rest.heart_ecg_SDNN_ecg;
S.pNN50_ecg = Rest.heart_ecg_pNN50_ecg;
S.LF_ecg = Rest.heart_ecg_LF_ecg;
S.HF_ecg = Rest.heart_ecg_HF_ecg;
S.LFHF_ecg = Rest.heart_ecg_LFHF_ecg;
S.ecg_rr_count_valid = Rest.heart_ecg_ecg_rr_count_valid;
S.ecg_rr_valid_fraction = Rest.heart_ecg_ecg_rr_valid_fraction;

S.participant_sort_key = local_participant_sort_key(S.participant_id);

% Robust manual sorting:
% participant_sort_key sorts VP1, VP2, VP3...
% rest_order sorts EO1, EC, EO2 within each participant.
sort_value = S.participant_sort_key .* 100 + S.rest_order;
[~, sort_idx] = sort(sort_value, 'ascend');

S = S(sort_idx, :);
S.participant_sort_key = [];

writetable(S, output_csv);

fprintf('\nSaved serial-order HRV table:\n%s\n', output_csv);
fprintf('Rows: %d\n', height(S));
fprintf('Columns: %d\n', width(S));

%% QC tables
expected_rows = numel(unique(S.participant_id)) * 3;

qc_overview = table();
qc_overview.metric = { ...
    'n_rows'; ...
    'n_unique_participants'; ...
    'expected_rows_for_complete_EO1_EC_EO2'; ...
    'n_missing_expected_rows'; ...
    'n_duplicate_participant_condition_rows'};
qc_overview.value = [ ...
    height(S); ...
    numel(unique(S.participant_id)); ...
    expected_rows; ...
    expected_rows - height(S); ...
    local_count_duplicate_participant_condition_rows(S)];

condition_counts = local_condition_counts(S);
metric_summary = local_metric_summary(S);
participant_completeness = local_participant_completeness(S);

if isfile(output_qc_xlsx)
    delete(output_qc_xlsx);
end

writetable(qc_overview, output_qc_xlsx, 'Sheet', 'Overview');
writetable(condition_counts, output_qc_xlsx, 'Sheet', 'Condition_Counts');
writetable(metric_summary, output_qc_xlsx, 'Sheet', 'Metric_Summary');
writetable(participant_completeness, output_qc_xlsx, 'Sheet', 'Participant_Completeness');

fprintf('\nSaved serial-order HRV QC workbook:\n%s\n', output_qc_xlsx);

fprintf('\n--- SERIAL ORDER QC OVERVIEW ---\n');
disp(qc_overview);

fprintf('\n--- CONDITION COUNTS ---\n');
disp(condition_counts);

fprintf('\n--- FIRST 9 ROWS ---\n');
disp(head(S, min(9, height(S))));

fprintf('\n=====================================\n');
fprintf('BUILD SERIAL ORDER HRV TABLE END\n');
fprintf('=====================================\n');

end

%% ========================================================================
function sort_key = local_participant_sort_key(participant_id)

participant_id = cellstr(string(participant_id));
sort_key = NaN(numel(participant_id), 1);

for i = 1:numel(participant_id)
    tok = regexp(participant_id{i}, '\\d+', 'match', 'once');
    if ~isempty(tok)
        sort_key(i) = str2double(tok);
    else
        sort_key(i) = i;
    end
end

end

%% ========================================================================
function n_dup = local_count_duplicate_participant_condition_rows(S)

if isempty(S)
    n_dup = 0;
    return;
end

K = S(:, {'participant_id', 'rest_condition'});
[~, unique_idx] = unique(K, 'rows', 'stable');
n_dup = height(S) - numel(unique_idx);

end

%% ========================================================================
function C = local_condition_counts(S)

condition_names = {'EO1'; 'EC'; 'EO2'};
condition_orders = [1; 2; 3];

C = table();
C.rest_condition = condition_names;
C.rest_order = condition_orders;
C.n_rows = zeros(3, 1);
C.n_unique_participants = zeros(3, 1);

for i = 1:3
    mask = strcmp(S.rest_condition, condition_names{i});
    C.n_rows(i) = sum(mask);
    C.n_unique_participants(i) = numel(unique(S.participant_id(mask)));
end

end

%% ========================================================================
function M = local_metric_summary(S)

metric_cols = { ...
    'meanHR_ecg', ...
    'RMSSD_ecg', ...
    'SDNN_ecg', ...
    'pNN50_ecg', ...
    'LF_ecg', ...
    'HF_ecg', ...
    'LFHF_ecg', ...
    'ecg_rr_count_valid', ...
    'ecg_rr_valid_fraction'};

condition_names = {'EO1'; 'EC'; 'EO2'};
condition_orders = [1; 2; 3];

n_rows_out = numel(condition_names) * numel(metric_cols);

rest_condition = cell(n_rows_out, 1);
rest_order = NaN(n_rows_out, 1);
variable_name = cell(n_rows_out, 1);
mean_value = NaN(n_rows_out, 1);
missing_count = NaN(n_rows_out, 1);
usable_participant_count = NaN(n_rows_out, 1);
n_rows = NaN(n_rows_out, 1);

row_idx = 0;

for c = 1:numel(condition_names)
    cond = condition_names{c};
    cond_mask = strcmp(S.rest_condition, cond);

    for m = 1:numel(metric_cols)
        row_idx = row_idx + 1;
        metric = metric_cols{m};
        x = S.(metric)(cond_mask);

        rest_condition{row_idx} = cond;
        rest_order(row_idx) = condition_orders(c);
        variable_name{row_idx} = metric;
        mean_value(row_idx) = mean(x, 'omitnan');
        missing_count(row_idx) = sum(isnan(x));
        usable_participant_count(row_idx) = sum(~isnan(x));
        n_rows(row_idx) = numel(x);
    end
end

M = table(rest_condition, rest_order, variable_name, mean_value, ...
    missing_count, usable_participant_count, n_rows);

end

%% ========================================================================
function P = local_participant_completeness(S)

participants = unique(S.participant_id, 'stable');

P = table();
P.participant_id = participants;
P.has_EO1 = false(numel(participants), 1);
P.has_EC = false(numel(participants), 1);
P.has_EO2 = false(numel(participants), 1);
P.n_rest_conditions = zeros(numel(participants), 1);
P.complete_EO1_EC_EO2 = false(numel(participants), 1);

for i = 1:numel(participants)
    mask = strcmp(S.participant_id, participants{i});
    conds = S.rest_condition(mask);

    P.has_EO1(i) = any(strcmp(conds, 'EO1'));
    P.has_EC(i) = any(strcmp(conds, 'EC'));
    P.has_EO2(i) = any(strcmp(conds, 'EO2'));
    P.n_rest_conditions(i) = sum([P.has_EO1(i), P.has_EC(i), P.has_EO2(i)]);
    P.complete_EO1_EC_EO2(i) = P.has_EO1(i) && P.has_EC(i) && P.has_EO2(i);
end

end
