function [results, warnings_log, models] = run_log_sensitivity_models(T, cfg)
%RUN_LOG_SENSITIVITY_MODELS Limited-scope log-outcome sensitivity analysis
%   for cfg.log_sensitivity_outcome (SwingTimeVariability by default):
%   refits the EXACT SAME fixed-effects structure as the raw primary
%   random_slope model, with the natural-log-transformed, separately
%   z-scored outcome (z_log_<outcome>, built by transform_and_standardize.m)
%   in place of the raw z-scored outcome:
%
%       z_log_<outcome> ~ HRV_z * speed_factor + walking_task +
%           kinesis_condition + (1 + speed_factor | participant_id)
%
%   Scope is deliberately limited to 3 resting conditions x 3 HRV
%   predictors, PRIMARY random_slope structure only = 9 models total.
%   cfg.enable_log_sensitivity=false skips this stage entirely (returns
%   valid empty tables) and leaves the rest of the pipeline unaffected.
%
%   These models:
%     - are labelled inferential_role = 'log_outcome_sensitivity' (never
%       'primary' or 'exploratory_sensitivity') and model_family =
%       'log_sensitivity', so identify_candidate_pairs.m's and
%       build_robustness_comparison.m's inferential_role/model_variant
%       filters can never pick them up;
%     - are returned in their own results table, never concatenated into
%       primary_results;
%     - never trigger follow-up modelling -- run_followup_models.m is only
%       ever called with candidates derived from primary_results;
%     - get their own, separate Benjamini-Hochberg FDR family (9 tests),
%       never mixed with the primary/sensitivity families computed in
%       run_primary_models.m.
%
%   Reuses fit_one_lmm.m, extract_hrv_terms.m, compute_hrv_simple_slope_4kmh.m,
%   extract_fixed_effect_term.m, compute_r2_glmm.m, and run_model_diagnostics.m
%   unchanged -- this stage only supplies a different outcome column and a
%   narrower loop; it does not alter how any individual model is fit or
%   diagnosed.

rows = {};
models = {};
warnings_log = {};

if ~cfg.enable_log_sensitivity
    results = rows_to_table(rows);
    return;
end

outcome_raw = cfg.log_sensitivity_outcome;
log_gait_col = ['z_log_' outcome_raw];

if ~ismember(log_gait_col, T.Properties.VariableNames)
    warnings_log{end+1} = sprintf( ...
        'Log sensitivity: %s not found (was transform_and_standardize.m able to build it?) -- stage skipped.', ...
        log_gait_col);
    results = rows_to_table(rows);
    return;
end

model_id = 0;

for rc = 1:numel(cfg.rest_condition_levels)
    rest_level = cfg.rest_condition_levels{rc};
    T_rc = T(T.(cfg.rest_condition_col) == rest_level, :);

    for hv = 1:numel(cfg.hrv_var_names)
        hrv_raw = cfg.hrv_var_names{hv};
        hrv_col = ['z_' hrv_raw];
        model_id = model_id + 1;

        needed_cols = {log_gait_col, hrv_col, cfg.speed_col, cfg.walking_task_col, ...
                       cfg.kinesis_col, cfg.participant_col};
        [T_model, n_removed, participants_excluded, n_participants_used] = ...
            complete_case_subset(T_rc, needed_cols, cfg.participant_col);
        n_rows_model = height(T_model);

        row = init_result_row(model_id, 'log_sensitivity', rest_level, outcome_raw, hrv_raw, 'random_slope');
        row.random_effect_structure_used = 'random_intercept_plus_speed_slope';
        row.inferential_role = 'log_outcome_sensitivity';
        row.outcome_column_used = log_gait_col;
        row.n_rows = n_rows_model;
        row.n_missing_rows_removed = n_removed;
        row.n_participants = n_participants_used;
        row.participants_excluded_for_this_model = strjoin(participants_excluded, ';');

        formula = sprintf('%s ~ %s * %s + %s + %s + %s', ...
            log_gait_col, hrv_col, cfg.speed_col, cfg.walking_task_col, cfg.kinesis_col, cfg.re_full);

        if n_participants_used < cfg.min_participants_per_model || n_rows_model < cfg.min_rows_per_model
            row.warning_message = 'skipped: insufficient non-missing data for this log-sensitivity combination';
            warnings_log{end+1} = sprintf('LogSensitivity %d (%s): %s', model_id, row.model_label, row.warning_message); %#ok<AGROW>
            rows{end+1} = row; %#ok<AGROW>
            models{end+1} = []; %#ok<AGROW>
            continue;
        end

        fitres = fit_one_lmm(T_model, formula, cfg);
        row.converged = fitres.converged;
        row.singular_fit = fitres.singular_fit;
        row.warning_message = fitres.warning_message;

        if isempty(fitres.model)
            row.warning_message = [row.warning_message ' | model fitting failed entirely'];
            warnings_log{end+1} = sprintf('LogSensitivity %d (%s): fitting failed', model_id, row.model_label); %#ok<AGROW>
            rows{end+1} = row; %#ok<AGROW>
            models{end+1} = []; %#ok<AGROW>
            continue;
        end

        m = fitres.model;
        terms = extract_hrv_terms(m, hrv_col, cfg.speed_col);

        row.estimate_HRV = terms.main.estimate;
        row.SE_HRV = terms.main.se;
        row.t_HRV = terms.main.tStat;
        row.p_HRV_raw = terms.main.pValue;
        row.CI_HRV_lower = terms.main.ci_lower;
        row.CI_HRV_upper = terms.main.ci_upper;

        row.estimate_HRVxSpeed = terms.hrv_x_speed.estimate;
        row.SE_HRVxSpeed = terms.hrv_x_speed.se;
        row.t_HRVxSpeed = terms.hrv_x_speed.tStat;
        row.p_HRVxSpeed_raw = terms.hrv_x_speed.pValue;
        row.CI_HRVxSpeed_lower = terms.hrv_x_speed.ci_lower;
        row.CI_HRVxSpeed_upper = terms.hrv_x_speed.ci_upper;

        slope_4kmh = compute_hrv_simple_slope_4kmh(m, hrv_col, cfg.speed_col);
        row.estimate_HRV_4kmh = slope_4kmh.estimate;
        row.SE_HRV_4kmh = slope_4kmh.se;
        row.t_HRV_4kmh = slope_4kmh.tStat;
        row.p_HRV_4kmh_raw = slope_4kmh.pValue;
        row.CI_HRV_4kmh_lower = slope_4kmh.ci_lower;
        row.CI_HRV_4kmh_upper = slope_4kmh.ci_upper;

        wt_term = extract_fixed_effect_term(m, cfg.walking_task_col);
        row.walking_task_term_name = wt_term.name;
        row.estimate_WalkingTask = wt_term.estimate;
        row.SE_WalkingTask = wt_term.se;
        row.t_WalkingTask = wt_term.tStat;
        row.p_WalkingTask_raw = wt_term.pValue;
        row.CI_WalkingTask_lower = wt_term.ci_lower;
        row.CI_WalkingTask_upper = wt_term.ci_upper;

        [r2m, r2c] = compute_r2_glmm(m);
        row.R2_marginal = r2m;
        row.R2_conditional = r2c;

        row.AIC = m.ModelCriterion.AIC;
        row.BIC = m.ModelCriterion.BIC;

        diag_opts = struct('do_loo_influence', false, 'hrv_col', hrv_col, ...
                            'participant_col', cfg.participant_col);
        d = run_model_diagnostics(m, cfg, diag_opts);
        d_fields = fieldnames(d);
        for fi = 1:numel(d_fields)
            row.(d_fields{fi}) = d.(d_fields{fi});
        end

        if ~isempty(fitres.warning_message)
            warnings_log{end+1} = sprintf('LogSensitivity %d (%s): %s', model_id, row.model_label, fitres.warning_message); %#ok<AGROW>
        end

        fprintf('  [log-sensitivity %d/%d] %s | log(%s) ~ %s  (n=%d, participants=%d)\n', ...
            model_id, numel(cfg.rest_condition_levels) * numel(cfg.hrv_var_names), ...
            rest_level, outcome_raw, hrv_raw, row.n_rows, row.n_participants);

        rows{end+1} = row; %#ok<AGROW>
        models{end+1} = m; %#ok<AGROW>
    end
end

results = rows_to_table(rows);

% Own, separate BH-FDR family (9 tests) -- never mixed with the
% primary/sensitivity families computed in run_primary_models.m.
if height(results) > 0
    results.p_HRV_FDR = fdr_bh(results.p_HRV_raw);
    results.p_HRVxSpeed_FDR = fdr_bh(results.p_HRVxSpeed_raw);
    results.p_WalkingTask_FDR = fdr_bh(results.p_WalkingTask_raw);
    results.p_HRV_4kmh_FDR = fdr_bh(results.p_HRV_4kmh_raw);
end

end
