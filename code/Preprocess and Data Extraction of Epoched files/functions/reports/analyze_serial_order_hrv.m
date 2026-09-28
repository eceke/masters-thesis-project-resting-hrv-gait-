function analyze_serial_order_hrv()
%ANALYZE_SERIAL_ORDER_HRV Analyze EO1-EC-EO2 resting HRV serial-order patterns.
%
% Purpose:
%   Exploratory/QC analysis of resting-state HRV across EO1, EC, and EO2.
%   This script does not modify the main HRV-gait dataset and does not
%   average EO1 and EO2.
%
% Input:
%   Output/Feature Tables/LMM_serial_order_HRV_rest.csv
%
% Outputs:
%   Output/Feature Tables/Serial_Order_HRV_Analysis.xlsx
%   Output/Feature Tables/Serial_Order_HRV_Subject_Wide.csv
%   Output/Feature Tables/Serial_Order_HRV_Within_Subject_Deltas.csv
%
% Interpretation boundary:
%   If EO1, EC, EO2 were recorded in a fixed order, condition effects and
%   time/order effects cannot be fully separated. Treat this as a QC and
%   exploratory serial-order analysis, not as the main thesis analysis.

fprintf('\n=====================================\n');
fprintf('ANALYZE SERIAL ORDER HRV START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(fileparts(mfilename('fullpath'))))));

cfg = get_preprocessing_config();

input_file = fullfile(cfg.paths.features_root, 'LMM_serial_order_HRV_rest.csv');
output_xlsx = fullfile(cfg.paths.features_root, 'Serial_Order_HRV_Analysis.xlsx');
output_wide_csv = fullfile(cfg.paths.features_root, 'Serial_Order_HRV_Subject_Wide.csv');
output_delta_csv = fullfile(cfg.paths.features_root, 'Serial_Order_HRV_Within_Subject_Deltas.csv');

if ~isfile(input_file)
    error('analyze_serial_order_hrv:MissingInput', ...
        ['Serial-order HRV table not found:\n%s\n', ...
         'Run build_serial_order_hrv_table before analyze_serial_order_hrv.'], ...
        input_file);
end

T = readtable(input_file);

fprintf('\nLoaded serial-order HRV table:\n%s\n', input_file);
fprintf('Rows: %d\n', height(T));
fprintf('Columns: %d\n', width(T));

required_cols = { ...
    'participant_id', ...
    'rest_condition', ...
    'rest_order', ...
    'meanHR_ecg', ...
    'RMSSD_ecg', ...
    'SDNN_ecg', ...
    'pNN50_ecg', ...
    'LF_ecg', ...
    'HF_ecg', ...
    'LFHF_ecg', ...
    'ecg_rr_count_valid', ...
    'ecg_rr_valid_fraction'};

missing_cols = required_cols(~ismember(required_cols, T.Properties.VariableNames));

if ~isempty(missing_cols)
    fprintf('\nMissing required columns:\n');
    disp(missing_cols');
    error('analyze_serial_order_hrv:MissingColumns', ...
        'Required columns are missing from LMM_serial_order_HRV_rest.csv.');
end

T.participant_id = cellstr(string(T.participant_id));
T.rest_condition = cellstr(string(T.rest_condition));

metrics = { ...
    'meanHR_ecg', ...
    'RMSSD_ecg', ...
    'SDNN_ecg', ...
    'pNN50_ecg', ...
    'LF_ecg', ...
    'HF_ecg', ...
    'LFHF_ecg'};

condition_names = {'EO1', 'EC', 'EO2'};
condition_orders = [1, 2, 3];

Overview = local_build_overview(T, condition_names);
Descriptive = local_build_descriptive_summary(T, metrics, condition_names, condition_orders);
Wide = local_build_subject_wide(T, metrics, condition_names);
Deltas = local_build_within_subject_deltas(Wide, metrics);
DirectionCounts = local_build_direction_counts(Deltas, metrics);
StatTests = local_build_statistical_tests(Wide, metrics);
StatTests = local_add_fdr_columns(StatTests);
Interpretation = local_build_interpretation_summary(DirectionCounts, StatTests, metrics);

writetable(Wide, output_wide_csv);
writetable(Deltas, output_delta_csv);

if isfile(output_xlsx)
    delete(output_xlsx);
end

writetable(Overview, output_xlsx, 'Sheet', 'Overview');
writetable(Descriptive, output_xlsx, 'Sheet', 'Descriptive_Summary');
writetable(Wide, output_xlsx, 'Sheet', 'Subject_Wide_Table');
writetable(Deltas, output_xlsx, 'Sheet', 'Within_Subject_Deltas');
writetable(DirectionCounts, output_xlsx, 'Sheet', 'Direction_Counts');
writetable(StatTests, output_xlsx, 'Sheet', 'Statistical_Tests');
writetable(Interpretation, output_xlsx, 'Sheet', 'Interpretation_Summary');

fprintf('\nSaved serial-order HRV analysis workbook:\n%s\n', output_xlsx);
fprintf('Saved subject-wide table:\n%s\n', output_wide_csv);
fprintf('Saved within-subject delta table:\n%s\n', output_delta_csv);

fprintf('\n--- OVERVIEW ---\n');
disp(Overview);

fprintf('\n--- DESCRIPTIVE SUMMARY ---\n');
disp(Descriptive);

fprintf('\n--- DIRECTION COUNTS ---\n');
disp(DirectionCounts);

fprintf('\n--- STATISTICAL TESTS ---\n');
disp(StatTests);

fprintf('\n--- INTERPRETATION SUMMARY ---\n');
disp(Interpretation);

fprintf('\n=====================================\n');
fprintf('ANALYZE SERIAL ORDER HRV END\n');
fprintf('=====================================\n');

end

%% ========================================================================
function Overview = local_build_overview(T, condition_names)

participants = unique(T.participant_id, 'stable');
n_expected = numel(participants) * numel(condition_names);

Overview = table();
Overview.metric = { ...
    'n_rows'; ...
    'n_unique_participants'; ...
    'n_expected_rows_for_complete_EO1_EC_EO2'; ...
    'n_missing_expected_rows'; ...
    'n_duplicate_participant_condition_rows'};
Overview.value = [ ...
    height(T); ...
    numel(participants); ...
    n_expected; ...
    n_expected - height(T); ...
    local_count_duplicate_participant_condition_rows(T)];

end

%% ========================================================================
function n_dup = local_count_duplicate_participant_condition_rows(T)

K = T(:, {'participant_id', 'rest_condition'});
[~, unique_idx] = unique(K, 'rows', 'stable');
n_dup = height(T) - numel(unique_idx);

end

%% ========================================================================
function Descriptive = local_build_descriptive_summary(T, metrics, condition_names, condition_orders)

n_out = numel(metrics) * numel(condition_names);

metric_name = cell(n_out, 1);
rest_condition = cell(n_out, 1);
rest_order = NaN(n_out, 1);
n_total = NaN(n_out, 1);
n_available = NaN(n_out, 1);
n_missing = NaN(n_out, 1);
mean_value = NaN(n_out, 1);
std_value = NaN(n_out, 1);
median_value = NaN(n_out, 1);
min_value = NaN(n_out, 1);
max_value = NaN(n_out, 1);

row_idx = 0;

for m = 1:numel(metrics)
    metric = metrics{m};

    for c = 1:numel(condition_names)
        cond = condition_names{c};
        mask = strcmp(T.rest_condition, cond);
        x = T.(metric)(mask);

        row_idx = row_idx + 1;
        metric_name{row_idx} = metric;
        rest_condition{row_idx} = cond;
        rest_order(row_idx) = condition_orders(c);
        n_total(row_idx) = numel(x);
        n_available(row_idx) = sum(~isnan(x));
        n_missing(row_idx) = sum(isnan(x));
        mean_value(row_idx) = mean(x, 'omitnan');
        std_value(row_idx) = std(x, 'omitnan');
        median_value(row_idx) = median(x, 'omitnan');
        min_value(row_idx) = min(x, [], 'omitnan');
        max_value(row_idx) = max(x, [], 'omitnan');
    end
end

Descriptive = table(metric_name, rest_condition, rest_order, n_total, ...
    n_available, n_missing, mean_value, std_value, median_value, ...
    min_value, max_value);

end

%% ========================================================================
function Wide = local_build_subject_wide(T, metrics, condition_names)

participants = unique(T.participant_id, 'stable');
sort_key = local_participant_sort_key(participants);
[~, idx] = sort(sort_key);
participants = participants(idx);

Wide = table();
Wide.participant_id = participants;

for m = 1:numel(metrics)
    metric = metrics{m};

    for c = 1:numel(condition_names)
        cond = condition_names{c};
        out_col = sprintf('%s_%s', metric, cond);
        Wide.(out_col) = NaN(numel(participants), 1);

        for p = 1:numel(participants)
            mask = strcmp(T.participant_id, participants{p}) & strcmp(T.rest_condition, cond);

            if sum(mask) == 1
                Wide.(out_col)(p) = T.(metric)(mask);
            elseif sum(mask) > 1
                vals = T.(metric)(mask);
                Wide.(out_col)(p) = vals(1);
            end
        end
    end
end

end

%% ========================================================================
function Deltas = local_build_within_subject_deltas(Wide, metrics)

Deltas = table();
Deltas.participant_id = Wide.participant_id;

for m = 1:numel(metrics)
    metric = metrics{m};

    eo1_col = sprintf('%s_EO1', metric);
    ec_col = sprintf('%s_EC', metric);
    eo2_col = sprintf('%s_EO2', metric);

    if ~all(ismember({eo1_col, ec_col, eo2_col}, Wide.Properties.VariableNames))
        continue;
    end

    x_eo1 = Wide.(eo1_col);
    x_ec = Wide.(ec_col);
    x_eo2 = Wide.(eo2_col);

    Deltas.(sprintf('%s_EC_minus_EO1', metric)) = x_ec - x_eo1;
    Deltas.(sprintf('%s_EO2_minus_EC', metric)) = x_eo2 - x_ec;
    Deltas.(sprintf('%s_EO2_minus_EO1', metric)) = x_eo2 - x_eo1;
end

end

%% ========================================================================
function DirectionCounts = local_build_direction_counts(Deltas, metrics)

comparison_suffixes = { ...
    'EC_minus_EO1', ...
    'EO2_minus_EC', ...
    'EO2_minus_EO1'};

n_out = numel(metrics) * numel(comparison_suffixes);

metric_name = cell(n_out, 1);
comparison = cell(n_out, 1);
n_available = NaN(n_out, 1);
n_increase = NaN(n_out, 1);
n_decrease = NaN(n_out, 1);
n_no_change = NaN(n_out, 1);
percent_increase = NaN(n_out, 1);
percent_decrease = NaN(n_out, 1);
mean_delta = NaN(n_out, 1);
median_delta = NaN(n_out, 1);

row_idx = 0;

for m = 1:numel(metrics)
    metric = metrics{m};

    for c = 1:numel(comparison_suffixes)
        comp = comparison_suffixes{c};
        col = sprintf('%s_%s', metric, comp);

        row_idx = row_idx + 1;
        metric_name{row_idx} = metric;
        comparison{row_idx} = comp;

        if ~ismember(col, Deltas.Properties.VariableNames)
            continue;
        end

        d = Deltas.(col);
        d = d(isfinite(d) & ~isnan(d));

        n_available(row_idx) = numel(d);
        n_increase(row_idx) = sum(d > 0);
        n_decrease(row_idx) = sum(d < 0);
        n_no_change(row_idx) = sum(d == 0);

        if ~isempty(d)
            percent_increase(row_idx) = (n_increase(row_idx) ./ numel(d)) .* 100;
            percent_decrease(row_idx) = (n_decrease(row_idx) ./ numel(d)) .* 100;
            mean_delta(row_idx) = mean(d, 'omitnan');
            median_delta(row_idx) = median(d, 'omitnan');
        end
    end
end

DirectionCounts = table(metric_name, comparison, n_available, ...
    n_increase, n_decrease, n_no_change, percent_increase, ...
    percent_decrease, mean_delta, median_delta);

end

%% ========================================================================
function StatTests = local_build_statistical_tests(Wide, metrics)

comparisons = { ...
    'EO1', 'EC',  'EC_minus_EO1'; ...
    'EC',  'EO2', 'EO2_minus_EC'; ...
    'EO1', 'EO2', 'EO2_minus_EO1'};

n_out = numel(metrics) * size(comparisons, 1);

metric_name = cell(n_out, 1);
condition_A = cell(n_out, 1);
condition_B = cell(n_out, 1);
comparison = cell(n_out, 1);
n_pairs = NaN(n_out, 1);
mean_A = NaN(n_out, 1);
mean_B = NaN(n_out, 1);
mean_diff_B_minus_A = NaN(n_out, 1);
median_diff_B_minus_A = NaN(n_out, 1);
sd_diff = NaN(n_out, 1);
cohen_dz = NaN(n_out, 1);
ttest_t = NaN(n_out, 1);
ttest_df = NaN(n_out, 1);
ttest_p = NaN(n_out, 1);
wilcoxon_p = NaN(n_out, 1);

row_idx = 0;

for m = 1:numel(metrics)
    metric = metrics{m};

    for c = 1:size(comparisons, 1)
        cond_A = comparisons{c, 1};
        cond_B = comparisons{c, 2};
        comp = comparisons{c, 3};

        row_idx = row_idx + 1;
        metric_name{row_idx} = metric;
        condition_A{row_idx} = cond_A;
        condition_B{row_idx} = cond_B;
        comparison{row_idx} = comp;

        col_A = sprintf('%s_%s', metric, cond_A);
        col_B = sprintf('%s_%s', metric, cond_B);

        if ~all(ismember({col_A, col_B}, Wide.Properties.VariableNames))
            continue;
        end

        xA = Wide.(col_A);
        xB = Wide.(col_B);
        valid = isfinite(xA) & isfinite(xB) & ~isnan(xA) & ~isnan(xB);
        xA = xA(valid);
        xB = xB(valid);
        d = xB - xA;

        n_pairs(row_idx) = numel(d);

        if isempty(d)
            continue;
        end

        mean_A(row_idx) = mean(xA, 'omitnan');
        mean_B(row_idx) = mean(xB, 'omitnan');
        mean_diff_B_minus_A(row_idx) = mean(d, 'omitnan');
        median_diff_B_minus_A(row_idx) = median(d, 'omitnan');
        sd_diff(row_idx) = std(d, 'omitnan');

        if isfinite(sd_diff(row_idx)) && sd_diff(row_idx) > 0
            cohen_dz(row_idx) = mean_diff_B_minus_A(row_idx) ./ sd_diff(row_idx);
        end

        if numel(d) >= 3 && exist('ttest', 'file') == 2
            try
                [~, p, ~, stats] = ttest(d);
                ttest_p(row_idx) = p;
                ttest_t(row_idx) = stats.tstat;
                ttest_df(row_idx) = stats.df;
            catch
                ttest_p(row_idx) = NaN;
                ttest_t(row_idx) = NaN;
                ttest_df(row_idx) = NaN;
            end
        end

        if numel(d) >= 3 && any(d ~= 0) && exist('signrank', 'file') == 2
            try
                wilcoxon_p(row_idx) = signrank(d, 0);
            catch
                wilcoxon_p(row_idx) = NaN;
            end
        end
    end
end

StatTests = table(metric_name, condition_A, condition_B, comparison, ...
    n_pairs, mean_A, mean_B, mean_diff_B_minus_A, ...
    median_diff_B_minus_A, sd_diff, cohen_dz, ...
    ttest_t, ttest_df, ttest_p, wilcoxon_p);

end

%% ========================================================================
function StatTests = local_add_fdr_columns(StatTests)

if ismember('ttest_p', StatTests.Properties.VariableNames)
    StatTests.ttest_p_fdr_bh = local_bh_fdr(StatTests.ttest_p);
end

if ismember('wilcoxon_p', StatTests.Properties.VariableNames)
    StatTests.wilcoxon_p_fdr_bh = local_bh_fdr(StatTests.wilcoxon_p);
end

end

%% ========================================================================
function q = local_bh_fdr(p)

p = double(p(:));
q = NaN(size(p));

valid = isfinite(p) & ~isnan(p);
p_valid = p(valid);

m = numel(p_valid);
if m == 0
    return;
end

[p_sorted, sort_idx] = sort(p_valid, 'ascend');
q_sorted = p_sorted .* m ./ (1:m)';

for i = m-1:-1:1
    q_sorted(i) = min(q_sorted(i), q_sorted(i+1));
end

q_sorted(q_sorted > 1) = 1;

q_valid = NaN(m, 1);
q_valid(sort_idx) = q_sorted;
q(valid) = q_valid;

end

%% ========================================================================
function Interpretation = local_build_interpretation_summary(DirectionCounts, StatTests, metrics)

n_out = numel(metrics);
metric_name = cell(n_out, 1);
eo2_minus_eo1_mean_delta = NaN(n_out, 1);
eo2_minus_eo1_n_decrease = NaN(n_out, 1);
eo2_minus_eo1_n_available = NaN(n_out, 1);
eo2_minus_eo1_percent_decrease = NaN(n_out, 1);
eo2_minus_eo1_ttest_p = NaN(n_out, 1);
eo2_minus_eo1_ttest_p_fdr_bh = NaN(n_out, 1);
eo2_minus_eo1_wilcoxon_p = NaN(n_out, 1);
eo2_minus_eo1_wilcoxon_p_fdr_bh = NaN(n_out, 1);
descriptive_pattern = cell(n_out, 1);

for m = 1:numel(metrics)
    metric = metrics{m};
    metric_name{m} = metric;

    dc_mask = strcmp(DirectionCounts.metric_name, metric) & ...
        strcmp(DirectionCounts.comparison, 'EO2_minus_EO1');

    if any(dc_mask)
        eo2_minus_eo1_mean_delta(m) = DirectionCounts.mean_delta(dc_mask);
        eo2_minus_eo1_n_decrease(m) = DirectionCounts.n_decrease(dc_mask);
        eo2_minus_eo1_n_available(m) = DirectionCounts.n_available(dc_mask);
        eo2_minus_eo1_percent_decrease(m) = DirectionCounts.percent_decrease(dc_mask);
    end

    st_mask = strcmp(StatTests.metric_name, metric) & ...
        strcmp(StatTests.comparison, 'EO2_minus_EO1');

    if any(st_mask)
        eo2_minus_eo1_ttest_p(m) = StatTests.ttest_p(st_mask);
        eo2_minus_eo1_wilcoxon_p(m) = StatTests.wilcoxon_p(st_mask);

        if ismember('ttest_p_fdr_bh', StatTests.Properties.VariableNames)
            eo2_minus_eo1_ttest_p_fdr_bh(m) = StatTests.ttest_p_fdr_bh(st_mask);
        end

        if ismember('wilcoxon_p_fdr_bh', StatTests.Properties.VariableNames)
            eo2_minus_eo1_wilcoxon_p_fdr_bh(m) = StatTests.wilcoxon_p_fdr_bh(st_mask);
        end
    end

    if isfinite(eo2_minus_eo1_mean_delta(m))
        if eo2_minus_eo1_mean_delta(m) > 0
            descriptive_pattern{m} = 'EO2 higher than EO1 on average';
        elseif eo2_minus_eo1_mean_delta(m) < 0
            descriptive_pattern{m} = 'EO2 lower than EO1 on average';
        else
            descriptive_pattern{m} = 'EO2 and EO1 equal on average';
        end
    else
        descriptive_pattern{m} = 'Not available';
    end
end

Interpretation = table(metric_name, eo2_minus_eo1_mean_delta, ...
    eo2_minus_eo1_n_decrease, eo2_minus_eo1_n_available, ...
    eo2_minus_eo1_percent_decrease, eo2_minus_eo1_ttest_p, ...
    eo2_minus_eo1_ttest_p_fdr_bh, eo2_minus_eo1_wilcoxon_p, ...
    eo2_minus_eo1_wilcoxon_p_fdr_bh, descriptive_pattern);

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
