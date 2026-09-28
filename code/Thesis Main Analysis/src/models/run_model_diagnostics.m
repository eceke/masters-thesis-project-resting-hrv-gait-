function diag = run_model_diagnostics(m, cfg, opts)
%RUN_MODEL_DIAGNOSTICS Post-fit assumption checks for a fitted
%   LinearMixedModel (Step 6.5 / Step 11): residual normality,
%   homoscedasticity, influential points, and random-effects normality.
%   Diagnostics never remove or refit the model themselves -- they only
%   populate flags and a warning message for the results table.
%
%   opts.do_loo_influence (logical) additionally runs the more expensive
%   leave-one-participant-out influence check (Step 11, follow-up models
%   only); opts.hrv_col / opts.participant_col are required when it is true.
%
%   Beyond the five original flags (residual_normality_flag,
%   homoscedasticity_flag, influential_points_flag,
%   random_effect_normality_flag, diagnostic_warning_message),
%   this also reports the descriptive statistics behind each flag -- test
%   name/statistic, skewness/kurtosis, per-cell residual SD, influential
%   observation context, per-random-effect-term normality. 

if nargin < 3
    opts = struct();
end
if ~isfield(opts, 'do_loo_influence'); opts.do_loo_influence = false; end
if ~isfield(opts, 'hrv_col'); opts.hrv_col = ''; end
if ~isfield(opts, 'participant_col'); opts.participant_col = 'participant_id'; end

diag = struct('residual_normality_flag', NaN, ...
              'residual_normality_test_name', 'Lilliefors (Kolmogorov-Smirnov)', ...
              'residual_normality_stat', NaN, 'residual_normality_p', NaN, ...
              'residual_normality_skewness', NaN, 'residual_normality_kurtosis', NaN, ...
              'residual_normality_n', NaN, ...
              'homoscedasticity_flag', NaN, ...
              'homoscedasticity_test_name', 'auxiliary regression of |Pearson residual| on fitted value', ...
              'homoscedasticity_p', NaN, ...
              'homoscedasticity_speed_variance_ratio', NaN, ...
              'homoscedasticity_cell_variance_ratio', NaN, ...
              'influential_points_flag', false, 'influential_points_detail', '', ...
              'influential_points_threshold_z', cfg.influence_flag_z, ...
              'influential_points_n_over_threshold', 0, ...
              'influential_points_max_abs_standardized_residual', NaN, ...
              'influential_points_participant_ids', '', ...
              'influential_points_observation_context', '', ...
              'influential_points_loo_flag', NaN, ...
              'influential_points_loo_max_abs_delta', NaN, ...
              'influential_points_loo_flagged_participants', '', ...
              'random_effect_normality_flag', NaN, ...
              'random_effect_intercept_normality_p', NaN, ...
              'random_effect_intercept_skewness', NaN, ...
              'random_effect_intercept_kurtosis', NaN, ...
              'random_effect_intercept_sd', NaN, ...
              'random_effect_slope_normality_p', NaN, ...
              'random_effect_slope_skewness', NaN, ...
              'random_effect_slope_kurtosis', NaN, ...
              'random_effect_slope_sd', NaN, ...
              'random_effect_intercept_slope_correlation', NaN, ...
              'diagnostic_warning_message', '', ...
              'diagnostic_summary', '');

% Per-speed / per-walking-task / per-task-x-speed-cell residual SD fields
% are named dynamically from cfg.speed_levels / cfg.walking_task_levels
% and added to `diag` as they are computed below.
for si = 1:numel(cfg.speed_levels)
    diag.(sprintf('homoscedasticity_residual_sd_speed_%s', cfg.speed_levels{si})) = NaN;
end
for ti = 1:numel(cfg.walking_task_levels)
    diag.(sprintf('homoscedasticity_residual_sd_task_%s', cfg.walking_task_levels{ti})) = NaN;
end
for ti = 1:numel(cfg.walking_task_levels)
    for si = 1:numel(cfg.speed_levels)
        diag.(sprintf('homoscedasticity_residual_sd_%s_%skmh', ...
            cfg.walking_task_levels{ti}, cfg.speed_levels{si})) = NaN;
    end
end

warnings = {};
summary_parts = {};

% ---- residual normality (Lilliefors test on Pearson residuals) ----
try
    res = residuals(m, 'ResidualType', 'Pearson');
    res_valid = res(~isnan(res));
    if numel(res_valid) >= 4
        [h, p, kstat] = lillietest(res_valid);
        diag.residual_normality_flag = logical(h); % true = departs from normality
        diag.residual_normality_stat = kstat;
        diag.residual_normality_p = p;
        diag.residual_normality_skewness = skewness(res_valid);
        diag.residual_normality_kurtosis = kurtosis(res_valid);
        diag.residual_normality_n = numel(res_valid);
        summary_parts{end+1} = sprintf( ...
            'residuals %s normality (Lilliefors stat=%.3f, p=%.3f, skew=%.2f, kurt=%.2f, n=%d)', ...
            local_departs_word(diag.residual_normality_flag), kstat, p, ...
            diag.residual_normality_skewness, diag.residual_normality_kurtosis, diag.residual_normality_n); %#ok<AGROW>
    else
        warnings{end+1} = 'residual normality: too few residuals for lillietest'; %#ok<AGROW>
    end
catch ME
    warnings{end+1} = sprintf('residual normality check failed: %s', ME.message); %#ok<AGROW>
end

% ---- homoscedasticity: regress |residuals| on fitted values, plus a
% breakdown of residual SD by speed, walking task, and the task x speed
% cells, so a flagged heteroscedasticity can be traced to its likely
% source rather than only flagged ----
try
    res = residuals(m, 'ResidualType', 'Pearson');
    fit_vals = fitted(m);
    ok = ~isnan(res) & ~isnan(fit_vals);
    if sum(ok) >= 5
        aux = fitlm(fit_vals(ok), abs(res(ok)));
        p_het = aux.Coefficients.pValue(2);
        diag.homoscedasticity_p = p_het;
        diag.homoscedasticity_flag = p_het < cfg.alpha; % true = evidence of heteroscedasticity
    else
        warnings{end+1} = 'homoscedasticity check: too few observations'; %#ok<AGROW>
    end

    Tv = m.Variables;
    has_speed = ismember(cfg.speed_col, Tv.Properties.VariableNames);
    has_task = ismember(cfg.walking_task_col, Tv.Properties.VariableNames);

    speed_var = nan(numel(cfg.speed_levels), 1);
    if has_speed
        for si = 1:numel(cfg.speed_levels)
            mask_s = Tv.(cfg.speed_col) == cfg.speed_levels{si};
            sd_s = std(res(mask_s & ~isnan(res)));
            diag.(sprintf('homoscedasticity_residual_sd_speed_%s', cfg.speed_levels{si})) = sd_s;
            speed_var(si) = sd_s^2;
        end
    end
    if all(~isnan(speed_var)) && min(speed_var) > 0
        diag.homoscedasticity_speed_variance_ratio = max(speed_var) / min(speed_var);
    end

    if has_task
        for ti = 1:numel(cfg.walking_task_levels)
            mask_t = Tv.(cfg.walking_task_col) == cfg.walking_task_levels{ti};
            sd_t = std(res(mask_t & ~isnan(res)));
            diag.(sprintf('homoscedasticity_residual_sd_task_%s', cfg.walking_task_levels{ti})) = sd_t;
        end
    end

    cell_var = [];
    if has_task && has_speed
        for ti = 1:numel(cfg.walking_task_levels)
            for si = 1:numel(cfg.speed_levels)
                mask_c = Tv.(cfg.walking_task_col) == cfg.walking_task_levels{ti} & ...
                         Tv.(cfg.speed_col) == cfg.speed_levels{si};
                sd_c = std(res(mask_c & ~isnan(res)));
                diag.(sprintf('homoscedasticity_residual_sd_%s_%skmh', ...
                    cfg.walking_task_levels{ti}, cfg.speed_levels{si})) = sd_c;
                cell_var(end+1) = sd_c^2; %#ok<AGROW>
            end
        end
    end
    if ~isempty(cell_var) && all(~isnan(cell_var)) && min(cell_var) > 0
        diag.homoscedasticity_cell_variance_ratio = max(cell_var) / min(cell_var);
    end

    summary_parts{end+1} = sprintf( ...
        'heteroscedasticity %s (p=%.3f; speed variance ratio=%.2f, cell variance ratio=%.2f)', ...
        local_departs_word(diag.homoscedasticity_flag), diag.homoscedasticity_p, ...
        diag.homoscedasticity_speed_variance_ratio, diag.homoscedasticity_cell_variance_ratio); %#ok<AGROW>
catch ME
    warnings{end+1} = sprintf('homoscedasticity check failed: %s', ME.message); %#ok<AGROW>
end

% ---- influential points: fast standardized-residual heuristic, with
% observation-level context (participant / rest_condition / walking_task /
% speed) for every flagged observation ----
try
    res_std = residuals(m, 'ResidualType', 'Standardized');
    valid_idx = find(~isnan(res_std));
    res_valid = res_std(valid_idx);
    n_obs_valid = numel(res_valid);
    n_extreme = sum(abs(res_valid) > cfg.influence_flag_z);
    diag.influential_points_flag = n_extreme > 0;
    diag.influential_points_n_over_threshold = n_extreme;
    if n_obs_valid > 0
        diag.influential_points_max_abs_standardized_residual = max(abs(res_valid));
    end
    diag.influential_points_detail = sprintf('%d observation(s) with |standardized residual| > %.1f', ...
        n_extreme, cfg.influence_flag_z);

    if n_extreme > 0
        Tv = m.Variables;
        flagged_idx = valid_idx(abs(res_valid) > cfg.influence_flag_z);
        has_p = ismember(cfg.participant_col, Tv.Properties.VariableNames);
        has_rest = ismember(cfg.rest_condition_col, Tv.Properties.VariableNames);
        has_task = ismember(cfg.walking_task_col, Tv.Properties.VariableNames);
        has_speed = ismember(cfg.speed_col, Tv.Properties.VariableNames);

        context_parts = cell(numel(flagged_idx), 1);
        pid_list = cell(numel(flagged_idx), 1);
        for k = 1:numel(flagged_idx)
            r = flagged_idx(k);
            pid = ''; if has_p; pid = char(Tv.(cfg.participant_col)(r)); end
            rc = ''; if has_rest; rc = char(Tv.(cfg.rest_condition_col)(r)); end
            wt = ''; if has_task; wt = char(Tv.(cfg.walking_task_col)(r)); end
            sp = ''; if has_speed; sp = char(Tv.(cfg.speed_col)(r)); end
            pid_list{k} = pid;
            context_parts{k} = sprintf('%s|rest=%s|task=%s|speed=%s|std.resid=%.2f', ...
                pid, rc, wt, sp, res_std(r));
        end
        diag.influential_points_participant_ids = strjoin(unique(pid_list, 'stable'), ';');
        diag.influential_points_observation_context = strjoin(context_parts, ';');
    end

    summary_parts{end+1} = sprintf('influential points: %d/%d observation(s) beyond |std.resid|>%.1f (max=%.2f)', ...
        n_extreme, n_obs_valid, cfg.influence_flag_z, diag.influential_points_max_abs_standardized_residual); %#ok<AGROW>
catch ME
    warnings{end+1} = sprintf('influential points (residual heuristic) check failed: %s', ME.message); %#ok<AGROW>
end

if opts.do_loo_influence && ~isempty(opts.hrv_col)
    try
        loo = compute_loo_influence(m, cfg, opts);
        diag.influential_points_flag = diag.influential_points_flag || loo.any_flagged;
        diag.influential_points_loo_flag = loo.any_flagged;
        diag.influential_points_loo_max_abs_delta = loo.max_abs_delta;
        diag.influential_points_loo_flagged_participants = strjoin(loo.flagged_participants, ';');
        diag.influential_points_detail = sprintf('%s | LOO: %s', ...
            diag.influential_points_detail, loo.detail);
        summary_parts{end+1} = sprintf('leave-one-participant-out influence flagged=%s (max|delta beta|=%.3f%s)', ...
            local_departs_word(loo.any_flagged), loo.max_abs_delta, ...
            local_participants_suffix(loo.flagged_participants)); %#ok<AGROW>
    catch ME
        warnings{end+1} = sprintf('leave-one-participant-out influence check failed: %s', ME.message); %#ok<AGROW>
    end
end

% random effects normality, reported separately per component
% (intercept vs. random speed slope) so a flag can be traced to its
% source;
try
    [B, Bnames] = randomEffects(m);
    reTbl = Bnames;
    reTbl.Estimate = B;
    grp_names = unique(reTbl.Name, 'stable');
    flags = false(numel(grp_names), 1);

    % Random intercept-speed slope correlation is read from the fitted
    % model's covariance parameters, as in the singularity check in
    % fit_one_lmm.m. It is defined only when the grouping variable has
    % more than one random-effect term (the random_slope variant).
    
    corr_val = NaN;
    n_re_terms = numel(grp_names);
    if n_re_terms < 2
        % Not applicable -- leave NaN, no warning (this is by design for
        % the random_intercept_only variant, not an extraction failure).
    else
        try
            [~, ~, covStats] = covarianceParameters(m);
            corr_found = false;
            types_seen = {};
            for g = 1:numel(covStats)
                tbl = covStats{g};
                if ~istable(tbl)
                    tbl = dataset2table(tbl);
                end
                if ~ismember('Type', tbl.Properties.VariableNames)
                    % covarianceParameters' STATS cell array has one extra
                    % final entry describing the RESIDUAL error term (no
                    % Type column) rather than a random-effect covariance
                    % parameter -- see fit_one_lmm.m's model_is_singular
                    % for the same handling.
                    continue;
                end
                type_str = cellstr(string(tbl.Type));
                types_seen = [types_seen; type_str(:)]; %#ok<AGROW>
                isCorr = strcmpi(type_str, 'corr');
                if any(isCorr)
                    corr_idx = find(isCorr, 1);
                    candidate = tbl.Estimate(corr_idx);
                    if ~isnan(candidate) && candidate >= -1 && candidate <= 1
                        corr_val = candidate;
                        corr_found = true;
                    else
                        warnings{end+1} = sprintf( ...
                            ['random-effect intercept-slope correlation outside the valid ' ...
                             '[-1,1] range (%.6g) -- discarded as unreliable, left as NaN'], candidate); %#ok<AGROW>
                    end
                end
            end
            if ~corr_found && isnan(corr_val)
                warnings{end+1} = sprintf( ...
                    ['random-effect intercept-slope correlation not found even though this ' ...
                     'model has %d random-effect terms (covariance parameter type(s) seen: %s) ' ...
                     '-- left as NaN'], n_re_terms, strjoin(unique(types_seen, 'stable'), ', ')); %#ok<AGROW>
            end
        catch ME
            warnings{end+1} = sprintf( ...
                'random-effect intercept-slope correlation could not be computed: %s', ME.message); %#ok<AGROW>
        end
    end
    diag.random_effect_intercept_slope_correlation = corr_val;

    intercept_departs = NaN;
    slope_departs = NaN;
    for i = 1:numel(grp_names)
        name_i = grp_names{i};
        vals = reTbl.Estimate(strcmp(reTbl.Name, name_i));
        is_intercept = strcmpi(name_i, '(Intercept)');

        p_i = NaN; skew_i = NaN; kurt_i = NaN; h_i = NaN;
        if numel(vals) >= 4
            [h, p_i] = lillietest(vals);
            h_i = logical(h);
            flags(i) = h_i;
            skew_i = skewness(vals);
            kurt_i = kurtosis(vals);
        end
        sd_i = std(vals);

        if is_intercept
            diag.random_effect_intercept_normality_p = p_i;
            diag.random_effect_intercept_skewness = skew_i;
            diag.random_effect_intercept_kurtosis = kurt_i;
            diag.random_effect_intercept_sd = sd_i;
            intercept_departs = h_i;
        else
            diag.random_effect_slope_normality_p = p_i;
            diag.random_effect_slope_skewness = skew_i;
            diag.random_effect_slope_kurtosis = kurt_i;
            diag.random_effect_slope_sd = sd_i;
            slope_departs = h_i;
        end
    end
    diag.random_effect_normality_flag = any(flags);

    srcs = {};
    if islogical(intercept_departs) && intercept_departs; srcs{end+1} = 'intercept'; end %#ok<AGROW>
    if islogical(slope_departs) && slope_departs; srcs{end+1} = 'slope'; end %#ok<AGROW>
    if isempty(srcs)
        source_txt = 'none flagged';
    else
        source_txt = strjoin(srcs, ' & ');
    end
    summary_parts{end+1} = sprintf('random effects normality %s (source: %s)', ...
        local_departs_word(diag.random_effect_normality_flag), source_txt); %#ok<AGROW>
catch ME
    warnings{end+1} = sprintf('random effects normality check failed: %s', ME.message); %#ok<AGROW>
end

diag.diagnostic_warning_message = strjoin(warnings, ' | ');
diag.diagnostic_summary = strjoin(summary_parts, ' | ');

end

function s = local_departs_word(tf)
%LOCAL_DEPARTS_WORD Human-readable yes/no/undetermined for a logical flag
%   that may also be NaN (check not computed) -- used only for the
%   diagnostic_summary text
    if islogical(tf) && tf
        s = 'departs from expectation';
    elseif islogical(tf) && ~tf
        s = 'consistent with expectation';
    else
        s = 'undetermined';
    end
end

function s = local_participants_suffix(participants)
    if isempty(participants)
        s = '';
    else
        s = sprintf('; participant(s): %s', strjoin(participants, ';'));
    end
end
