function export_all_outputs(output_dir, data)
%EXPORT_ALL_OUTPUTS Write every pipeline deliverable (Step 12) to
%   output_dir: one CSV per table, the SAME set of tables collected as
%   sheets in a single Excel workbook (hrv_gait_pipeline_results.xlsx) for
%   readers who just want to open one file, plus a .mat snapshot containing
%   the fitted model objects for later interactive inspection (e.g.
%   anova(), plotResiduals() on any individual model).
%
%   data.robustness_comparison (build_robustness_comparison.m),
%   data.sensitivity_only_patterns, data.followup_simple_slopes, and
%   data.followup_rest_condition_contrasts are always valid tables, empty
%   (0 rows) when there are no candidates or no successful follow-up fits

if ~isfolder(output_dir)
    mkdir(output_dir);
end

qcT = struct2table(data.qc_summary);

if ~isempty(data.warnings_log)
    warnT = cell2table(data.warnings_log(:), 'VariableNames', {'warning'});
else
    warnT = cell2table(cell(0, 1), 'VariableNames', {'warning'});
end

% Diagnostics report: model identity, fit status, diagnostic flags,
% supporting test statistics, residual summaries, random-effect checks,
% fit statistics, and a human-readable diagnostic summary.
diag_cols = {'model_id', 'model_family', 'model_variant', 'inferential_role', 'outcome_column_used', ...
             'rest_condition', 'gait_outcome', 'hrv_predictor', 'random_effect_structure_used', ...
             'converged', 'singular_fit', ...
             'residual_normality_flag', 'residual_normality_test_name', 'residual_normality_stat', ...
             'residual_normality_p', 'residual_normality_skewness', 'residual_normality_kurtosis', ...
             'residual_normality_n', ...
             'homoscedasticity_flag', 'homoscedasticity_test_name', 'homoscedasticity_p', ...
             'homoscedasticity_residual_sd_speed_1', 'homoscedasticity_residual_sd_speed_4', ...
             'homoscedasticity_residual_sd_task_BW', 'homoscedasticity_residual_sd_task_FWW', ...
             'homoscedasticity_residual_sd_BW_1kmh', 'homoscedasticity_residual_sd_BW_4kmh', ...
             'homoscedasticity_residual_sd_FWW_1kmh', 'homoscedasticity_residual_sd_FWW_4kmh', ...
             'homoscedasticity_speed_variance_ratio', 'homoscedasticity_cell_variance_ratio', ...
             'influential_points_flag', 'influential_points_threshold_z', ...
             'influential_points_n_over_threshold', 'influential_points_max_abs_standardized_residual', ...
             'influential_points_participant_ids', 'influential_points_observation_context', ...
             'influential_points_loo_flag', 'influential_points_loo_max_abs_delta', ...
             'influential_points_loo_flagged_participants', 'influential_points_detail', ...
             'random_effect_normality_flag', ...
             'random_effect_intercept_normality_p', 'random_effect_intercept_skewness', ...
             'random_effect_intercept_kurtosis', 'random_effect_intercept_sd', ...
             'random_effect_slope_normality_p', 'random_effect_slope_skewness', ...
             'random_effect_slope_kurtosis', 'random_effect_slope_sd', ...
             'random_effect_intercept_slope_correlation', ...
             'diagnostic_warning_message', 'diagnostic_summary', ...
             'R2_marginal', 'R2_conditional', 'AIC', 'BIC'};
% model_uid: a deterministic, human-readable text key (family label +
% existing model_id, e.g. 'primary_1', 'followup_1', 'logsens_1') added
% ONLY to this combined report, purely for readability -- model_id itself,
% row order, and the row-to-model-object mapping used elsewhere (candidate
% selection, follow-up linkage, diagnostic plot filenames) are untouched.
diag_parts = { ...
    local_add_model_uid(safe_select(data.primary_results, diag_cols), 'primary'); ...
    local_add_model_uid(safe_select(data.followup_results, diag_cols), 'followup'); ...
    local_add_model_uid(safe_select(data.log_sensitivity_results, diag_cols), 'logsens') ...
};
diag_report = table();
for di = 1:numel(diag_parts)
    part = diag_parts{di};
    if width(part) == 0
        continue;
    end
    if width(diag_report) == 0
        diag_report = part;
    elseif isequal(diag_report.Properties.VariableNames, part.Properties.VariableNames)
        diag_report = [diag_report; part]; %#ok<AGROW>
    end
end

% followup_model_results shares primary_results' schema (both are built
% from init_result_row.m); when there are no candidates it is genuinely
% 0x0 (rows_to_table of an empty cell array cannot know its own columns),
% so a schema-only, zero-row template derived from init_result_row.m
% itself (never a hand-maintained column list, so it cannot drift out of
% sync) is used for export ONLY -- data.followup_results itself, and the
% .mat snapshot below, are untouched.
followup_results_for_export = data.followup_results;
if istable(followup_results_for_export) && width(followup_results_for_export) == 0
    followup_results_for_export = local_empty_results_schema();
end

% Every CSV deliverable, paired with its Excel sheet name (Excel sheet
% names are capped at 31 characters and can't contain : \ / ? * [ ]).
outputs = { ...
    'final_analysis_table',       'Final Analysis Table',       data.T_final; ...
    'missingness_by_variable',    'Missingness by Variable',    data.missingness.by_variable; ...
    'missingness_by_participant', 'Missingness by Participant', data.missingness.by_participant; ...
    'rows_per_rest_condition',    'Rows per Rest Condition',    data.missingness.rows_per_rest_condition; ...
    'rows_per_walking_task',      'Rows per Walking Task',      data.missingness.rows_per_walking_task; ...
    'rows_per_speed_factor',      'Rows per Speed Factor',      data.missingness.rows_per_speed_factor; ...
    'primary_model_results',      'Primary Model Results',      data.primary_results; ...
    'robustness_comparison',      'Robustness Comparison',      data.robustness_comparison; ...
    'candidate_followup_pairs',   'Candidate Followup Pairs',   data.candidates; ...
    'sensitivity_only_candidate_patterns', 'Sensitivity-Only Patterns', data.sensitivity_only_patterns; ...
    'followup_model_results',     'Followup Model Results',     followup_results_for_export; ...
    'followup_simple_slopes',     'Followup Simple Slopes',     data.followup_simple_slopes; ...
    'followup_rest_condition_contrasts', 'Rest Condition Contrasts', data.followup_rest_condition_contrasts; ...
    'model_diagnostics_report',   'Model Diagnostics Report',   diag_report; ...
    'log_sensitivity_results',    'Log Sensitivity Results',    data.log_sensitivity_results; ...
    'swing_time_variability_log_comparison', 'STV Log Comparison', data.swing_time_log_comparison; ...
    'qc_summary',                 'QC Summary',                 qcT; ...
    'model_warnings_log',         'Model Warnings Log',         warnT ...
};

old_stale_csv = fullfile(output_dir, 'swing_time_log_comparison.csv');
if isfile(old_stale_csv)
    delete(old_stale_csv);
end

xlsx_path = fullfile(output_dir, 'hrv_gait_pipeline_results.xlsx');
if isfile(xlsx_path)
    delete(xlsx_path); % rebuild the workbook from scratch on every run
end

for i = 1:size(outputs, 1)
    csv_stem = outputs{i, 1};
    sheet_name = outputs{i, 2};
    T = outputs{i, 3};

    write_or_note(fullfile(output_dir, [csv_stem '.csv']), T);
    write_excel_sheet(xlsx_path, T, sheet_name);
end

save(fullfile(output_dir, 'hrv_gait_pipeline_results.mat'), '-struct', 'data');

% Limited diagnostic-plot folder (flagged models only, see
% export_diagnostic_plots.m). Wrapped so a headless/no-graphics
% environment, or any single model's plot failing, never blocks the
% CSV/Excel/.mat outputs already written above.
try
    export_diagnostic_plots(output_dir, { ...
        struct('label', 'primary', 'results', data.primary_results, 'models', {data.primary_models}); ...
        struct('label', 'followup', 'results', data.followup_results, 'models', {data.followup_models}); ...
        struct('label', 'logsens', 'results', data.log_sensitivity_results, 'models', {data.log_sensitivity_models}) ...
    });
catch ME
    fprintf('  Diagnostic plot export skipped (%s)\n', ME.message);
end

fprintf('\nAll outputs written to: %s\n', output_dir);
fprintf('  Excel workbook (all tables as sheets): %s\n', xlsx_path);

end

function write_or_note(path, T)
    % A 0-row-but-N-column table (N>0) still has real, meaningful column
    % headers (e.g. zero candidates found, zero follow-up warnings) and is
    % written normally so those headers survive in the CSV; only a truly
    % 0x0 table (no columns at all -- nothing to write a header for) falls
    % back to the placeholder note. Matches write_excel_sheet below.
    if ~istable(T) || width(T) == 0
        fid = fopen(path, 'w');
        fprintf(fid, 'no rows produced for this output\n');
        fclose(fid);
        return;
    end
    writetable(T, path);
end

function write_excel_sheet(xlsx_path, T, sheet_name)
    if ~istable(T) || width(T) == 0
        T = table({'no rows produced for this output'}, 'VariableNames', {'Note'});
    end
    writetable(T, xlsx_path, 'FileType', 'spreadsheet', 'Sheet', sheet_name);
end

function T2 = safe_select(T, cols)
    if ~istable(T) || width(T) == 0
        T2 = table();
        return;
    end
    cols_present = intersect(cols, T.Properties.VariableNames, 'stable');
    T2 = T(:, cols_present);
end

function T2 = local_add_model_uid(T, prefix)
%LOCAL_ADD_MODEL_UID Adds a model_uid text column (right after model_id) to
%   the combined diagnostics report, deterministically built as
%   '<prefix>_<model_id>' (e.g. 'primary_1', 'followup_1', 'logsens_1').
%   prefix identifies which pipeline stage a row came from (primary /
%   followup / log-sensitivity results) -- distinct from, and does not
%   change, the existing model_family column. Purely a readability
%   addition to this one report: does not change model_id, row order, or
%   any model-to-row mapping used elsewhere (diagnostic plots, candidate/
%   follow-up linkage).
    if ~istable(T) || width(T) == 0 || ~ismember('model_id', T.Properties.VariableNames)
        T2 = T;
        return;
    end
    model_uid = arrayfun(@(id) sprintf('%s_%d', prefix, id), T.model_id, 'UniformOutput', false);
    T2 = addvars(T, model_uid, 'After', 'model_id');
end

function T2 = local_empty_results_schema()
%LOCAL_EMPTY_RESULTS_SCHEMA Zero-row template with the full primary/
%   followup/log-sensitivity results-table schema, derived directly from
%   init_result_row.m (the single source of truth for that schema) rather
%   than a hand-maintained column list, so it can never drift out of sync.
%   Used only to give a genuinely empty follow-up results table (e.g. no
%   candidates) real column headers in the exported CSV/sheet, instead of
%   a placeholder note.
    template_row = init_result_row(0, '', '', '', '', '');
    template_table = rows_to_table({template_row});
    T2 = template_table([], :);
end
