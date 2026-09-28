function build_lmm_analysis_tables()
%BUILD_LMM_ANALYSIS_TABLES Build HRV-gait analysis-ready LMM tables.
%
% Purpose:
%   Creates the main analysis-ready datasets for the thesis question:
%       resting-state HRV -> walking gait prediction
%
% Important thesis decisions implemented here:
%   - Memory/Fast Words variables are not included.
%   - EO1, EC, and EO2 are kept separate.
%   - EO1 and EO2 are never averaged.
%   - Resting-state ECG-derived HRV variables are used as predictors.
%   - Walking Kinesis gait variables are used as outcomes.
%   - ECG RR quality-control variables are saved separately in HRV_QC.csv,
%     not included in the LMM long/wide analysis tables.
%
% Input:
%   Output/Feature Tables/ANALYSIS_TABLE_participant_segment.csv
%
% Outputs:
%   Output/Feature Tables/LMM_HRV_GAIT_long.csv
%   Output/Feature Tables/LMM_HRV_GAIT_wide.csv
%   Output/Feature Tables/HRV_QC.csv
%   Output/Feature Tables/Selected_HRV_Gait_Report.xlsx

fprintf('\n=====================================\n');
fprintf('BUILD LMM HRV-GAIT TABLES START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(fileparts(mfilename('fullpath'))))));

cfg = get_preprocessing_config();

input_file = fullfile(cfg.paths.features_root, 'ANALYSIS_TABLE_participant_segment.csv');
output_long_csv = fullfile(cfg.paths.features_root, 'LMM_HRV_GAIT_long.csv');
output_wide_csv = fullfile(cfg.paths.features_root, 'LMM_HRV_GAIT_wide.csv');
output_hrv_qc_csv = fullfile(cfg.paths.features_root, 'HRV_QC.csv');
output_report_xlsx = fullfile(cfg.paths.features_root, 'Selected_HRV_Gait_Report.xlsx');

if ~isfile(input_file)
    error('build_lmm_analysis_tables:MissingInput', ...
        ['Analysis table not found:\n%s\n', ...
         'Run run_build_analysis_table before build_lmm_analysis_tables.'], ...
        input_file);
end

T = readtable(input_file);

fprintf('\nLoaded analysis table:\n%s\n', input_file);
fprintf('Rows: %d\n', height(T));
fprintf('Columns: %d\n', width(T));

%% Normalize basic columns
required_base_cols = {'participant_id', 'segment_name', 'segment_type'};
local_assert_required_columns(T, required_base_cols, 'base metadata');

T.participant_id = cellstr(string(T.participant_id));
T.segment_name = cellstr(string(T.segment_name));
T.segment_type = cellstr(string(T.segment_type));

if ismember('kinesis_condition', T.Properties.VariableNames)
    T.kinesis_condition = cellstr(string(T.kinesis_condition));
else
    T.kinesis_condition = repmat({''}, height(T), 1);
end

%% Source-to-output variable definitions
% HRV predictors retained in the LMM analysis tables.
% LFnu, HFnu, LFHF, totalPower, and RR QC variables are intentionally not
% included in Long/Wide. RR QC is exported separately in HRV_QC.csv.
hrv_source = { ...
    'heart_ecg_meanHR_ecg', ...
    'heart_ecg_RMSSD_ecg', ...
    'heart_ecg_HF_ecg'};

hrv_output = { ...
    'meanHR_ecg', ...
    'RMSSD_ecg', ...
    'HF_ecg'};

hrv_role = { ...
    'main_predictor', ...
    'main_predictor', ...
    'main_predictor'};

qc_source = { ...
    'heart_ecg_ecg_rr_count_valid', ...
    'heart_ecg_ecg_rr_valid_fraction', ...
    'heart_ecg_LF_ecg', ...
    'heart_ecg_HF_ecg'};

qc_output = { ...
    'ecg_rr_count_valid', ...
    'ecg_rr_valid_fraction', ...
    'LF_ecg', ...
    'HF_ecg'};

gait_source = { ...
    'kinesis_AverageStrideLength_cm_', ...   % Stride Length
    'kinesis_Cadence_steps_min_', ...        % Cadence
    'kinesis_AverageStrideTime_s_', ...      % Stride Time
    'kinesis_AverageDoubleSupport', ...      % Double Support Time
    'kinesis_SwingTimeVariability___', ...   % Swing Time Variability
    'kinesis_AverageStanceTime_s_', ...      % Stance Time
    'kinesis_AverageSwingTime_s_'};          % Swing Time

gait_output = { ...
    'StrideLength', ...
    'Cadence', ...
    'StrideTime', ...
    'DoubleSupportTime', ...
    'SwingTimeVariability', ...
    'StanceTime', ...
    'SwingTime'};

local_assert_required_columns(T, hrv_source, 'selected ECG HRV predictors');
local_assert_required_columns(T, qc_source, 'ECG HRV QC variables');
local_assert_required_columns(T, gait_source, 'selected Kinesis gait outcomes');

%% Split rest and walking rows
rest_segments = {'RS_EO1', 'RS_EC', 'RS_EO2'};
walk_segments = {'BW_1KMH', 'BW_4KMH', 'FWW_1KMH', 'FWW_4KMH'};

Rest = T(ismember(T.segment_name, rest_segments), :);
Walk = T(ismember(T.segment_name, walk_segments), :);

if isempty(Rest)
    error('build_lmm_analysis_tables:NoRestRows', ...
        'No RS_EO1, RS_EC, or RS_EO2 rows found in the analysis table.');
end

if isempty(Walk)
    error('build_lmm_analysis_tables:NoWalkRows', ...
        'No BW_1KMH, BW_4KMH, FWW_1KMH, or FWW_4KMH rows found in the analysis table.');
end

%% Add rest metadata
rest_condition = strings(height(Rest), 1);
rest_order = NaN(height(Rest), 1);

for i = 1:height(Rest)
    [rest_condition(i), rest_order(i)] = local_rest_condition_and_order(Rest.segment_name{i});
end

Rest.rest_condition_tmp = cellstr(rest_condition);
Rest.rest_order_tmp = rest_order;
Rest.participant_sort_key_tmp = local_participant_sort_key(Rest.participant_id);
[~, idx_rest] = sortrows([Rest.participant_sort_key_tmp, Rest.rest_order_tmp]);
Rest = Rest(idx_rest, :);

%% Add walk metadata
walking_task = strings(height(Walk), 1);
walking_speed_kmh = NaN(height(Walk), 1);

for i = 1:height(Walk)
    [walking_task(i), walking_speed_kmh(i)] = local_walking_task_and_speed(Walk.segment_name{i});
end

Walk.walking_task_tmp = cellstr(walking_task);
Walk.walking_speed_kmh_tmp = walking_speed_kmh;
Walk.participant_sort_key_tmp = local_participant_sort_key(Walk.participant_id);
Walk.walk_segment_order_tmp = local_walk_segment_order(Walk.segment_name);
[~, idx_walk] = sortrows([Walk.participant_sort_key_tmp, Walk.walk_segment_order_tmp]);
Walk = Walk(idx_walk, :);

%% Build HRV QC table from resting HRV rows used as predictors
HRV_QC = table();
HRV_QC.participant_id = Rest.participant_id;
HRV_QC.segment = Rest.segment_name;
HRV_QC.rest_condition = Rest.rest_condition_tmp;
HRV_QC.rest_order = Rest.rest_order_tmp;
HRV_QC.ecg_rr_count_valid = Rest.heart_ecg_ecg_rr_count_valid;
HRV_QC.ecg_rr_valid_fraction = Rest.heart_ecg_ecg_rr_valid_fraction;

if isfield(cfg, 'ecg') && isfield(cfg.ecg, 'freq') && isfield(cfg.ecg.freq, 'min_valid_rr_count')
    min_rr_threshold = cfg.ecg.freq.min_valid_rr_count;
else
    min_rr_threshold = 120;
end

HRV_QC.min_rr_threshold = repmat(min_rr_threshold, height(Rest), 1);
HRV_QC.rr_count_meets_min = HRV_QC.ecg_rr_count_valid >= min_rr_threshold;

for h = 1:numel(hrv_source)
    success_col = [hrv_output{h} '_success'];
    x = Rest.(hrv_source{h});
    HRV_QC.(success_col) = isfinite(x) & ~isnan(x);
end

% Record HF and LF estimation success separately for QC.
HRV_QC.HF_success = isfinite(Rest.heart_ecg_HF_ecg) & ~isnan(Rest.heart_ecg_HF_ecg);
HRV_QC.LF_success = isfinite(Rest.heart_ecg_LF_ecg) & ~isnan(Rest.heart_ecg_LF_ecg);

hrv_success_cols = strcat(hrv_output, '_success');
HRV_QC.n_failed_HRV_predictors = zeros(height(HRV_QC), 1);
for h = 1:numel(hrv_success_cols)
    HRV_QC.n_failed_HRV_predictors = HRV_QC.n_failed_HRV_predictors + ~HRV_QC.(hrv_success_cols{h});
end
HRV_QC.all_HRV_success = HRV_QC.n_failed_HRV_predictors == 0;
HRV_QC.warning_flag = ~HRV_QC.rr_count_meets_min | ~HRV_QC.all_HRV_success;
HRV_QC.warning_reason = local_hrv_qc_warning_reason(HRV_QC, hrv_output);

HRV_QC.participant_sort_key_tmp = local_participant_sort_key(HRV_QC.participant_id);
HRV_QC.rest_order_tmp = Rest.rest_order_tmp;
[~, idx_qc] = sortrows([HRV_QC.participant_sort_key_tmp, HRV_QC.rest_order_tmp]);
HRV_QC = HRV_QC(idx_qc, :);
HRV_QC.participant_sort_key_tmp = [];
HRV_QC.rest_order_tmp = [];

%% Build long table: one row = participant x rest condition x walking segment
participants = unique(T.participant_id, 'stable');
participants = local_sort_participants(participants);

long_rows = struct([]);
long_idx = 0;

for p = 1:numel(participants)
    pid = participants{p};
    rest_idx = find(strcmp(Rest.participant_id, pid));
    walk_idx = find(strcmp(Walk.participant_id, pid));

    participant_condition = local_first_nonempty(T.kinesis_condition(strcmp(T.participant_id, pid)));

    for r = 1:numel(rest_idx)
        ri = rest_idx(r);

        for w = 1:numel(walk_idx)
            wi = walk_idx(w);
            long_idx = long_idx + 1;

            row = struct();
            row.participant_id = pid;
            row.kinesis_condition = participant_condition;
            row.rest_condition = Rest.rest_condition_tmp{ri};
            row.rest_order = Rest.rest_order_tmp(ri);
            row.walking_segment = Walk.segment_name{wi};
            row.walking_task = Walk.walking_task_tmp{wi};
            row.walking_speed_kmh = Walk.walking_speed_kmh_tmp(wi);

            for h = 1:numel(hrv_source)
                row.(hrv_output{h}) = Rest.(hrv_source{h})(ri);
            end

            for g = 1:numel(gait_source)
                row.(gait_output{g}) = Walk.(gait_source{g})(wi);
            end

            long_rows = local_append_struct_row(long_rows, row, long_idx); %#ok<AGROW>
        end
    end
end

Long = struct2table(long_rows);
Long.participant_sort_key_tmp = local_participant_sort_key(Long.participant_id);
Long.walk_segment_order_tmp = local_walk_segment_order(Long.walking_segment);
[~, idx_long] = sortrows([Long.participant_sort_key_tmp, Long.rest_order, Long.walk_segment_order_tmp]);
Long = Long(idx_long, :);
Long.participant_sort_key_tmp = [];
Long.walk_segment_order_tmp = [];

%% Build wide table: one row = participant x rest condition; walking gait columns are segment-prefixed
wide_rows = struct([]);
wide_idx = 0;

for p = 1:numel(participants)
    pid = participants{p};
    rest_idx = find(strcmp(Rest.participant_id, pid));
    participant_condition = local_first_nonempty(T.kinesis_condition(strcmp(T.participant_id, pid)));

    for r = 1:numel(rest_idx)
        ri = rest_idx(r);
        wide_idx = wide_idx + 1;

        row = struct();
        row.participant_id = pid;
        row.kinesis_condition = participant_condition;
        row.rest_condition = Rest.rest_condition_tmp{ri};
        row.rest_order = Rest.rest_order_tmp(ri);

        for h = 1:numel(hrv_source)
            row.(hrv_output{h}) = Rest.(hrv_source{h})(ri);
        end

        for ws = 1:numel(walk_segments)
            seg = walk_segments{ws};
            wi = find(strcmp(Walk.participant_id, pid) & strcmp(Walk.segment_name, seg), 1, 'first');

            for g = 1:numel(gait_source)
                out_name = matlab.lang.makeValidName([seg '_' gait_output{g}]);

                if isempty(wi)
                    row.(out_name) = NaN;
                else
                    row.(out_name) = Walk.(gait_source{g})(wi);
                end
            end
        end

        wide_rows = local_append_struct_row(wide_rows, row, wide_idx); %#ok<AGROW>
    end
end

Wide = struct2table(wide_rows);
Wide.participant_sort_key_tmp = local_participant_sort_key(Wide.participant_id);
[~, idx_wide] = sortrows([Wide.participant_sort_key_tmp, Wide.rest_order]);
Wide = Wide(idx_wide, :);
Wide.participant_sort_key_tmp = [];

%% Save CSV tables
writetable(Wide, output_wide_csv);
writetable(Long, output_long_csv);
writetable(HRV_QC, output_hrv_qc_csv);

fprintf('\nSaved wide HRV-gait LMM table:\n%s\n', output_wide_csv);
fprintf('Rows: %d\n', height(Wide));
fprintf('Columns: %d\n', width(Wide));

fprintf('\nSaved long HRV-gait LMM table:\n%s\n', output_long_csv);
fprintf('Rows: %d\n', height(Long));
fprintf('Columns: %d\n', width(Long));

fprintf('\nSaved HRV QC table:\n%s\n', output_hrv_qc_csv);
fprintf('Rows: %d\n', height(HRV_QC));
fprintf('Columns: %d\n', width(HRV_QC));

%% Build Excel workbook with analysis tables and QC/report sheets
Overview = local_overview_table(T, Rest, Walk, Long, Wide, HRV_QC, hrv_output, gait_output);
input_column_check = local_input_column_check(T, required_base_cols, hrv_source, qc_source, gait_source);
variable_mapping = local_variable_mapping(hrv_source, hrv_output, hrv_role, qc_source, qc_output, gait_source, gait_output);
rest_hrv_summary = local_group_metric_summary(Rest, 'rest_condition_tmp', 'rest_order_tmp', hrv_source, hrv_output);
walk_gait_summary = local_group_metric_summary(Walk, 'segment_name', 'walk_segment_order_tmp', gait_source, gait_output);
long_missingness = local_missingness_table(Long);
wide_missingness = local_missingness_table(Wide);
hrv_qc_summary = local_hrv_qc_summary(HRV_QC);
hrv_qc_missingness = local_missingness_table(HRV_QC);
model_readiness = local_model_readiness_table(Long, Wide, HRV_QC, hrv_output, gait_output, walk_segments);

if isfile(output_report_xlsx)
    delete(output_report_xlsx);
end

% First four sheets: direct deliverables.
writetable(Wide, output_report_xlsx, 'Sheet', 'LMM_HRV_GAIT_wide');
writetable(Long, output_report_xlsx, 'Sheet', 'LMM_HRV_GAIT_long');
writetable(HRV_QC, output_report_xlsx, 'Sheet', 'HRV_QC');
writetable(Overview, output_report_xlsx, 'Sheet', 'Overview');

% Additional QC and documentation sheets.
writetable(input_column_check, output_report_xlsx, 'Sheet', 'Input_Column_Check');
writetable(variable_mapping, output_report_xlsx, 'Sheet', 'Variable_Mapping');
writetable(rest_hrv_summary, output_report_xlsx, 'Sheet', 'Rest_HRV_Summary');
writetable(walk_gait_summary, output_report_xlsx, 'Sheet', 'Walk_Gait_Summary');
writetable(long_missingness, output_report_xlsx, 'Sheet', 'Long_Missingness');
writetable(wide_missingness, output_report_xlsx, 'Sheet', 'Wide_Missingness');
writetable(hrv_qc_summary, output_report_xlsx, 'Sheet', 'HRV_QC_Summary');
writetable(hrv_qc_missingness, output_report_xlsx, 'Sheet', 'HRV_QC_Missingness');
writetable(model_readiness, output_report_xlsx, 'Sheet', 'Model_Readiness');

fprintf('\nSaved selected HRV-gait Excel workbook:\n%s\n', output_report_xlsx);
fprintf(['Sheets: LMM_HRV_GAIT_wide, LMM_HRV_GAIT_long, HRV_QC, Overview, ', ...
    'Input_Column_Check, Variable_Mapping, Rest_HRV_Summary, Walk_Gait_Summary, ', ...
    'Long_Missingness, Wide_Missingness, HRV_QC_Summary, HRV_QC_Missingness, Model_Readiness\n']);

fprintf('\n--- OVERVIEW ---\n');
disp(Overview);

fprintf('\n--- MODEL READINESS ---\n');
disp(model_readiness);

fprintf('\n--- FIRST 8 LONG ROWS ---\n');
disp(Long(1:min(8, height(Long)), 1:min(12, width(Long))));

fprintf('\n=====================================\n');
fprintf('BUILD LMM HRV-GAIT TABLES END\n');
fprintf('=====================================\n');

end

%% ========================================================================
function rows = local_append_struct_row(rows, row, row_idx)

% MATLAB can throw "Subscripted assignment between dissimilar structures"
% when dynamically created structs have the same fields but not the same
% internal field order. This helper keeps the original table logic unchanged
% and only makes struct-row appending robust.

if row_idx == 1 || isempty(rows)
    rows = row;
else
    row = orderfields(row, rows(1));
    rows(row_idx, 1) = row;
end

end

%% ========================================================================
function local_assert_required_columns(T, required_cols, label)

missing_cols = required_cols(~ismember(required_cols, T.Properties.VariableNames));

if ~isempty(missing_cols)
    fprintf('\nMissing required columns for %s:\n', label);
    disp(missing_cols');
    error('build_lmm_analysis_tables:MissingColumns', ...
        ['Required columns are missing for %s.\n', ...
         'Do not continue until the upstream table is regenerated.'], ...
        label);
end

end

%% ========================================================================
function [condition, order_value] = local_rest_condition_and_order(segment_name)

segment_name = string(segment_name);

if segment_name == "RS_EO1"
    condition = "EO1";
    order_value = 1;
elseif segment_name == "RS_EC"
    condition = "EC";
    order_value = 2;
elseif segment_name == "RS_EO2"
    condition = "EO2";
    order_value = 3;
else
    condition = "";
    order_value = NaN;
end

end

%% ========================================================================
function [task, speed_kmh] = local_walking_task_and_speed(segment_name)

segment_name = string(segment_name);

task = "";
speed_kmh = NaN;

if startsWith(segment_name, "BW")
    task = "BW";
elseif startsWith(segment_name, "FWW")
    task = "FWW";
end

if contains(segment_name, "1KMH")
    speed_kmh = 1;
elseif contains(segment_name, "4KMH")
    speed_kmh = 4;
end

end

%% ========================================================================
function order_value = local_walk_segment_order(segment_name)

segment_name = cellstr(string(segment_name));
order_value = NaN(numel(segment_name), 1);

for i = 1:numel(segment_name)
    seg = string(segment_name{i});

    if seg == "BW_1KMH"
        order_value(i) = 1;
    elseif seg == "BW_4KMH"
        order_value(i) = 2;
    elseif seg == "FWW_1KMH"
        order_value(i) = 3;
    elseif seg == "FWW_4KMH"
        order_value(i) = 4;
    else
        order_value(i) = NaN;
    end
end

end

%% ========================================================================
function sort_key = local_participant_sort_key(participant_id)

participant_id = cellstr(string(participant_id));
sort_key = NaN(numel(participant_id), 1);

for i = 1:numel(participant_id)
    tok = regexp(participant_id{i}, '\d+', 'match', 'once');
    if ~isempty(tok)
        sort_key(i) = str2double(tok);
    else
        sort_key(i) = i;
    end
end

end

%% ========================================================================
function participants_sorted = local_sort_participants(participants)

participants = cellstr(string(participants));
keys = local_participant_sort_key(participants);
[~, idx] = sort(keys);
participants_sorted = participants(idx);

end

%% ========================================================================
function value = local_first_nonempty(values)

values = cellstr(string(values));
value = '';

for i = 1:numel(values)
    v = strtrim(values{i});
    if ~isempty(v) && ~strcmpi(v, '<missing>') && ~strcmpi(v, 'missing')
        value = v;
        return;
    end
end

end


%% ========================================================================
function Overview = local_overview_table(T, Rest, Walk, Long, Wide, HRV_QC, hrv_output, gait_output)

participants = unique(T.participant_id);
expected_rest_rows = numel(participants) * 3;
expected_walk_rows = numel(participants) * 4;
expected_long_rows = numel(participants) * 3 * 4;
expected_wide_rows = numel(participants) * 3;

metric = { ...
    'n_input_analysis_rows'; ...
    'n_unique_participants'; ...
    'n_rest_rows'; ...
    'expected_rest_rows_3_per_participant'; ...
    'n_walk_rows'; ...
    'expected_walk_rows_4_per_participant'; ...
    'n_long_rows'; ...
    'expected_long_rows_participant_x_rest_x_walk'; ...
    'n_wide_rows'; ...
    'expected_wide_rows_participant_x_rest'; ...
    'n_hrv_qc_rows'; ...
    'n_long_columns'; ...
    'n_wide_columns'; ...
    'n_hrv_qc_columns'; ...
    'n_hrv_predictors_in_long_wide'; ...
    'n_gait_outcomes'; ...
    'n_hrv_qc_warning_flags'};

value = [ ...
    height(T); ...
    numel(participants); ...
    height(Rest); ...
    expected_rest_rows; ...
    height(Walk); ...
    expected_walk_rows; ...
    height(Long); ...
    expected_long_rows; ...
    height(Wide); ...
    expected_wide_rows; ...
    height(HRV_QC); ...
    width(Long); ...
    width(Wide); ...
    width(HRV_QC); ...
    numel(hrv_output); ...
    numel(gait_output); ...
    sum(HRV_QC.warning_flag)];

Overview = table(metric, value);

end

%% ========================================================================
function V = local_variable_mapping(hrv_source, hrv_output, hrv_role, qc_source, qc_output, gait_source, gait_output)

n_hrv = numel(hrv_source);
n_qc = numel(qc_source);
n_gait = numel(gait_source);

variable_role = cell(n_hrv + n_qc + n_gait, 1);
analysis_use = cell(n_hrv + n_qc + n_gait, 1);
output_name = cell(n_hrv + n_qc + n_gait, 1);
source_column = cell(n_hrv + n_qc + n_gait, 1);
output_location = cell(n_hrv + n_qc + n_gait, 1);

for i = 1:n_hrv
    variable_role{i} = 'resting_ecg_hrv_predictor';
    analysis_use{i} = hrv_role{i};
    output_name{i} = hrv_output{i};
    source_column{i} = hrv_source{i};
    output_location{i} = 'long_and_wide';
end

for i = 1:n_qc
    idx = n_hrv + i;
    variable_role{idx} = 'resting_ecg_hrv_qc';
    analysis_use{idx} = 'quality_control_only';
    output_name{idx} = qc_output{i};
    source_column{idx} = qc_source{i};
    output_location{idx} = 'HRV_QC_csv_and_excel_sheet';
end

for i = 1:n_gait
    idx = n_hrv + n_qc + i;
    variable_role{idx} = 'walking_kinesis_gait_outcome';
    analysis_use{idx} = 'gait_outcome';
    output_name{idx} = gait_output{i};
    source_column{idx} = gait_source{i};
    output_location{idx} = 'long_and_wide';
end

V = table(variable_role, analysis_use, output_name, source_column, output_location);

end

%% ========================================================================
function C = local_input_column_check(T, base_cols, hrv_source, qc_source, gait_source)

all_required = [base_cols(:); hrv_source(:); qc_source(:); gait_source(:)];
source_group = [ ...
    repmat({'base_metadata'}, numel(base_cols), 1); ...
    repmat({'resting_ecg_hrv_predictor'}, numel(hrv_source), 1); ...
    repmat({'resting_ecg_hrv_qc'}, numel(qc_source), 1); ...
    repmat({'walking_kinesis_gait'}, numel(gait_source), 1)];

exists_in_analysis_table = ismember(all_required, T.Properties.VariableNames);

C = table(source_group, all_required, exists_in_analysis_table, ...
    'VariableNames', {'source_group', 'source_column', 'exists_in_analysis_table'});

end

%% ========================================================================
function S = local_group_metric_summary(T, group_col, order_col, source_cols, output_names)

if isempty(T)
    S = table();
    return;
end

groups = unique(T.(group_col), 'stable');

if nargin >= 3 && ~isempty(order_col) && ismember(order_col, T.Properties.VariableNames)
    group_order = NaN(numel(groups), 1);
    group_values_for_order = cellstr(string(T.(group_col)));
    for i = 1:numel(groups)
        mask = strcmp(group_values_for_order, string(groups{i}));
        x_order = T.(order_col)(mask);
        x_order = x_order(~isnan(x_order));
        if ~isempty(x_order)
            group_order(i) = x_order(1);
        else
            group_order(i) = i;
        end
    end
    [~, idx] = sort(group_order);
    groups = groups(idx);
end

row_group = cell(numel(groups) * numel(source_cols), 1);
row_metric = cell(numel(groups) * numel(source_cols), 1);
n_rows = NaN(numel(row_group), 1);
n_missing = NaN(numel(row_group), 1);
n_usable = NaN(numel(row_group), 1);
mean_value = NaN(numel(row_group), 1);
sd_value = NaN(numel(row_group), 1);
min_value = NaN(numel(row_group), 1);
max_value = NaN(numel(row_group), 1);

row_idx = 0;
group_values = cellstr(string(T.(group_col)));

for g = 1:numel(groups)
    gname = string(groups{g});
    gmask = strcmp(group_values, gname);

    for m = 1:numel(source_cols)
        row_idx = row_idx + 1;
        x = T.(source_cols{m})(gmask);
        x = double(x(:));
        valid = isfinite(x) & ~isnan(x);

        row_group{row_idx} = char(gname);
        row_metric{row_idx} = output_names{m};
        n_rows(row_idx) = numel(x);
        n_missing(row_idx) = sum(~valid);
        n_usable(row_idx) = sum(valid);

        if any(valid)
            xv = x(valid);
            mean_value(row_idx) = mean(xv);
            sd_value(row_idx) = local_std(xv);
            min_value(row_idx) = min(xv);
            max_value(row_idx) = max(xv);
        end
    end
end

S = table(row_group, row_metric, n_rows, n_missing, n_usable, ...
    mean_value, sd_value, min_value, max_value, ...
    'VariableNames', {'group', 'variable_name', 'n_rows', 'n_missing', ...
    'n_usable', 'mean_value', 'sd_value', 'min_value', 'max_value'});

end

%% ========================================================================
function M = local_missingness_table(T)

vars = T.Properties.VariableNames;
variable_name = vars(:);
n_rows = repmat(height(T), numel(vars), 1);
n_missing = NaN(numel(vars), 1);
missing_fraction = NaN(numel(vars), 1);

for i = 1:numel(vars)
    x = T.(vars{i});
    n_missing(i) = local_count_missing(x);
    missing_fraction(i) = n_missing(i) ./ height(T);
end

M = table(variable_name, n_rows, n_missing, missing_fraction);

end

%% ========================================================================
function Q = local_hrv_qc_summary(HRV_QC)

metric = {};
value = [];

metric{end+1,1} = 'n_hrv_qc_rows';
value(end+1,1) = height(HRV_QC);

metric{end+1,1} = 'n_unique_participants';
value(end+1,1) = numel(unique(HRV_QC.participant_id));

metric{end+1,1} = 'n_warning_flags';
value(end+1,1) = sum(HRV_QC.warning_flag);

metric{end+1,1} = 'n_rr_count_below_min';
value(end+1,1) = sum(~HRV_QC.rr_count_meets_min);

metric{end+1,1} = 'n_HF_failure';
value(end+1,1) = sum(~HRV_QC.HF_success);

metric{end+1,1} = 'n_LF_failure';
value(end+1,1) = sum(~HRV_QC.LF_success);

metric{end+1,1} = 'n_all_HRV_success';
value(end+1,1) = sum(HRV_QC.all_HRV_success);

if ismember('ecg_rr_valid_fraction', HRV_QC.Properties.VariableNames)
    x = HRV_QC.ecg_rr_valid_fraction;
    metric{end+1,1} = 'min_ecg_rr_valid_fraction';
    value(end+1,1) = min(x, [], 'omitnan');

    metric{end+1,1} = 'mean_ecg_rr_valid_fraction';
    value(end+1,1) = mean(x, 'omitnan');
end

if ismember('ecg_rr_count_valid', HRV_QC.Properties.VariableNames)
    x = HRV_QC.ecg_rr_count_valid;
    metric{end+1,1} = 'min_ecg_rr_count_valid';
    value(end+1,1) = min(x, [], 'omitnan');

    metric{end+1,1} = 'mean_ecg_rr_count_valid';
    value(end+1,1) = mean(x, 'omitnan');
end

Q = table(metric, value);

end

%% ========================================================================
function warning_reason = local_hrv_qc_warning_reason(HRV_QC, hrv_output)

warning_reason = cell(height(HRV_QC), 1);

for i = 1:height(HRV_QC)
    reasons = {};

    if ~HRV_QC.rr_count_meets_min(i)
        reasons{end+1} = 'rr_count_below_min'; %#ok<AGROW>
    end

    for h = 1:numel(hrv_output)
        success_col = [hrv_output{h} '_success'];
        if ismember(success_col, HRV_QC.Properties.VariableNames) && ~HRV_QC.(success_col)(i)
            reasons{end+1} = [hrv_output{h} '_missing']; %#ok<AGROW>
        end
    end

    if isempty(reasons)
        warning_reason{i} = 'none';
    else
        warning_reason{i} = strjoin(reasons, ';');
    end
end

end

%% ========================================================================
function n = local_count_missing(x)

if isnumeric(x)
    n = sum(isnan(x));
elseif islogical(x)
    n = 0;
elseif iscell(x)
    n = sum(cellfun(@(v) isempty(v) || ...
        (ischar(v) && isempty(strtrim(v))) || ...
        (isstring(v) && (ismissing(v) || strlength(v) == 0)), x));
elseif isstring(x)
    n = sum(ismissing(x) | strlength(x) == 0);
elseif iscategorical(x)
    n = sum(isundefined(x));
else
    n = 0;
end

end

%% ========================================================================
function R = local_model_readiness_table(Long, Wide, HRV_QC, hrv_output, gait_output, walk_segments)

main_predictors = {'meanHR_ecg', 'RMSSD_ecg', 'HF_ecg'};
secondary_predictors = {};

metric = {};
value = [];

metric{end+1,1} = 'long_n_rows';
value(end+1,1) = height(Long);

metric{end+1,1} = 'wide_n_rows';
value(end+1,1) = height(Wide);

metric{end+1,1} = 'hrv_qc_n_rows';
value(end+1,1) = height(HRV_QC);

metric{end+1,1} = 'hrv_qc_warning_flags';
value(end+1,1) = sum(HRV_QC.warning_flag);

for i = 1:numel(main_predictors)
    col = main_predictors{i};
    metric{end+1,1} = ['long_missing_main_' col];
    value(end+1,1) = local_count_missing(Long.(col));
end

for i = 1:numel(secondary_predictors)
    col = secondary_predictors{i};
    metric{end+1,1} = ['long_missing_secondary_' col];
    value(end+1,1) = local_count_missing(Long.(col));
end

for i = 1:numel(hrv_output)
    col = hrv_output{i};
    metric{end+1,1} = ['wide_missing_' col];
    value(end+1,1) = local_count_missing(Wide.(col));
end

for i = 1:numel(gait_output)
    col = gait_output{i};
    metric{end+1,1} = ['long_missing_' col];
    value(end+1,1) = local_count_missing(Long.(col));
end

for ws = 1:numel(walk_segments)
    for g = 1:numel(gait_output)
        col = matlab.lang.makeValidName([walk_segments{ws} '_' gait_output{g}]);
        if ismember(col, Wide.Properties.VariableNames)
            metric{end+1,1} = ['wide_missing_' col];
            value(end+1,1) = local_count_missing(Wide.(col));
        end
    end
end

R = table(metric, value);

end

%% ========================================================================
function s = local_std(x)

x = x(isfinite(x) & ~isnan(x));

if numel(x) <= 1
    s = NaN;
else
    s = std(x, 0);
end

end
