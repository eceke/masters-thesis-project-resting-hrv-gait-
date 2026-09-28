function analysis = compute_followup_rest_condition_analysis(m, hrv_col, cfg)
%COMPUTE_FOLLOWUP_REST_CONDITION_ANALYSIS For a fitted follow-up model
%   ( gait_z ~ HRV_z*rest_condition + HRV_z*speed_factor + walking_task +
%     kinesis_condition + random_effects -- NO HRV x rest_condition x
%     speed triple interaction ), extracts three distinct kinds of test
%   from the model's fixed effects, each as a linear combination of
%   coefficients using the model's own CoefficientCovariance matrix /
%   coefTest machinery (compute_lmm_contrast.m):
%
%   1) analysis.simple_slopes -- SIX condition-by-speed simple slopes (one
%      struct per rest_condition x speed combination, ordered
%      cfg.rest_condition_levels x cfg.speed_levels). Each answers: is the
%      HRV-gait association different from zero at THIS specific resting
%      condition and speed? Because the model has no triple interaction,
%      the HRV x speed effect is assumed identical across all three
%      resting conditions, so each condition's 4 km/h slope is that
%      condition's 1 km/h slope plus the SAME HRV x speed term. The
%      reference-level (EO1) rows are produced by literally calling
%      extract_hrv_terms.m and compute_hrv_simple_slope_4kmh.m -- the same
%      functions used for the existing backward-compatible estimate_HRV /
%      estimate_HRV_4kmh output columns -- so they are numerically
%      identical to those columns by construction.
%   2) analysis.contrasts -- THREE pairwise resting-condition slope
%      contrasts (EC vs EO1, EO2 vs EO1, EC vs EO2). Each answers: is the
%      HRV-gait association different BETWEEN two given resting
%      conditions? Because there is no triple interaction, a
%      resting-condition contrast is not speed-specific -- it is reported
%      once per condition pair. EC vs EO1
%      and EO2 vs EO1 are each a single model coefficient (the interaction
%      dummy itself, already relative to EO1); EC vs EO2 is a genuine
%      two-coefficient linear combination (beta_EC - beta_EO2) that
%      requires their covariance and is computed directly.
%   3) analysis.omnibus -- ONE joint test of whether the HRV-gait
%      association differs AT ALL across EO1/EC/EO2 (H0: both HRV x
%      rest_condition interaction coefficients are simultaneously zero,
%      via fitlme's coefTest with a 2-row hypothesis matrix). This does
%      NOT replace the simple slopes or the pairwise contrasts above -- it
%      only answers whether there is some difference somewhere among them.
%
%   Never errors: any slope/contrast/omnibus entry that can't be computed
%   (missing coefficient, degenerate covariance, failed coefTest) is left
%   as NaN; the rest of the analysis still runs.

rest_col = cfg.rest_condition_col;
speed_col = cfg.speed_col;
rest_levels = cfg.rest_condition_levels;
speed_levels = cfg.speed_levels;
ref_level = rest_levels{1};
other_levels = rest_levels(2:end);

terms = extract_hrv_terms(m, hrv_col, speed_col, rest_col);

coefT = m.Coefficients;
if ~istable(coefT)
    coefT = dataset2table(coefT);
end
p = height(coefT);

% ---- map each HRV x rest_condition interaction row to its level (e.g. 'EC') ----
level_idx = nan(size(other_levels));
prefix = [rest_col '_'];
hrv_x_rest = terms.hrv_x_rest;
for r = 1:height(hrv_x_rest)
    lvl = local_level_from_name(hrv_x_rest.Name{r}, prefix);
    li = find(strcmp(other_levels, lvl), 1);
    if ~isempty(li)
        idx_r = find(strcmp(coefT.Name, hrv_x_rest.Name{r}), 1);
        if ~isempty(idx_r)
            level_idx(li) = idx_r;
        end
    end
end

idx_main = find(strcmp(coefT.Name, terms.main.name), 1);
idx_speed = find(strcmp(coefT.Name, terms.hrv_x_speed.name), 1);

% ---- (1) six condition-by-speed simple slopes ----
slopes = struct('rest_condition', {}, 'speed', {}, 'estimate', {}, 'se', {}, ...
                 'tStat', {}, 'df', {}, 'pValue', {}, 'ci_lower', {}, 'ci_upper', {});
for ri = 1:numel(rest_levels)
    rc = rest_levels{ri};
    for si = 1:numel(speed_levels)
        sp = speed_levels{si};
        if strcmp(rc, ref_level)
            if strcmp(sp, cfg.speed_reference)
                s = terms.main;
            else
                s = compute_hrv_simple_slope_4kmh(m, hrv_col, speed_col);
            end
        else
            oi = find(strcmp(other_levels, rc), 1);
            c = local_build_slope_contrast(p, idx_main, level_idx(oi), idx_speed, ...
                ~strcmp(sp, cfg.speed_reference));
            if isempty(c)
                s = local_nan_contrast();
            else
                s = compute_lmm_contrast(m, c);
            end
        end
        slopes(end+1) = local_pack_slope_row(rc, sp, s); %#ok<AGROW>
    end
end
analysis.simple_slopes = slopes;

% ---- (2) three pairwise resting-condition slope contrasts ----
% Weights are against other_levels{1} (e.g. EC) and other_levels{2}
% (e.g. EO2) respectively -- matches cfg.rest_condition_levels(2:end).
contrast_specs = { ...
    sprintf('%s_vs_%s', other_levels{1}, ref_level),      [ 1,  0]; ...
    sprintf('%s_vs_%s', other_levels{2}, ref_level),      [ 0,  1]; ...
    sprintf('%s_vs_%s', other_levels{1}, other_levels{2}), [ 1, -1] ...
};
contrasts = struct('contrast_name', {}, 'estimate', {}, 'se', {}, 'tStat', {}, ...
                    'df', {}, 'pValue', {}, 'ci_lower', {}, 'ci_upper', {});
for k = 1:size(contrast_specs, 1)
    coeffs_k = contrast_specs{k, 2};
    c = zeros(p, 1);
    ok = true;
    for j = 1:2
        if coeffs_k(j) ~= 0
            if isnan(level_idx(j))
                ok = false;
                break;
            end
            c(level_idx(j)) = c(level_idx(j)) + coeffs_k(j);
        end
    end
    if ok
        r = compute_lmm_contrast(m, c);
    else
        r = local_nan_contrast();
    end
    contrasts(end+1) = struct('contrast_name', contrast_specs{k, 1}, 'estimate', r.estimate, ...
        'se', r.se, 'tStat', r.tStat, 'df', r.df, 'pValue', r.pValue, ...
        'ci_lower', r.ci_lower, 'ci_upper', r.ci_upper); %#ok<AGROW>
end
analysis.contrasts = contrasts;

% ---- (3) omnibus joint test: HRV x rest_condition interaction overall ----
omnibus = struct('F', NaN, 'df1', NaN, 'df2', NaN, 'pValue', NaN);
if ~any(isnan(level_idx))
    try
        H = zeros(numel(level_idx), p);
        for j = 1:numel(level_idx)
            H(j, level_idx(j)) = 1;
        end
        [pValue, F, df1, df2] = coefTest(m, H);
        omnibus.F = F;
        omnibus.df1 = df1;
        omnibus.df2 = df2;
        omnibus.pValue = pValue;
    catch
        % leave omnibus as all-NaN
    end
end
analysis.omnibus = omnibus;

end

function level = local_level_from_name(name, prefix)
    level = '';
    parts = strsplit(name, ':');
    if numel(parts) ~= 2
        return;
    end
    for i = 1:2
        if strncmp(parts{i}, prefix, numel(prefix))
            level = parts{i}(numel(prefix)+1:end);
            return;
        end
    end
end

function c = local_build_slope_contrast(p, idx_main, idx_level, idx_speed, add_speed)
    if isempty(idx_main) || isnan(idx_level) || (add_speed && isempty(idx_speed))
        c = [];
        return;
    end
    c = zeros(p, 1);
    c(idx_main) = c(idx_main) + 1;
    c(idx_level) = c(idx_level) + 1;
    if add_speed
        c(idx_speed) = c(idx_speed) + 1;
    end
end

function s = local_nan_contrast()
    s = struct('estimate', NaN, 'se', NaN, 'tStat', NaN, 'df', NaN, ...
                'pValue', NaN, 'ci_lower', NaN, 'ci_upper', NaN);
end

function row = local_pack_slope_row(rc, sp, s)
    row = struct('rest_condition', rc, 'speed', sp, 'estimate', s.estimate, ...
                 'se', s.se, 'tStat', s.tStat, 'df', s.df, 'pValue', s.pValue, ...
                 'ci_lower', s.ci_lower, 'ci_upper', s.ci_upper);
end
