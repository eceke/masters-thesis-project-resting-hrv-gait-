function loo = compute_loo_influence(m, cfg, opts)
%COMPUTE_LOO_INFLUENCE Leave-one-participant-out sensitivity check for ALL
%   SIX condition-by-speed HRV simple slopes of a fitted follow-up model
%   (EO1/EC/EO2 x 1/4 km/h -- see compute_followup_rest_condition_analysis.m
%   for how each slope is computed as a linear combination of fixed-effects
%   coefficients, using the model's own coefficient covariance). Refitting
%   once per participant is only affordable for the smaller follow-up
%   model family, so this is invoked with do_loo_influence=true there, and
%   skipped during the 63-model primary sweep (which instead uses a fast
%   standardized-residual heuristic -- see run_model_diagnostics).
%
%   A participant is flagged if removing them shifts ANY of the six slopes
%   by more than cfg.loo_influence_se_multiple standard errors of that
%   slope's own full-data estimate. Each of the six slopes is evaluated
%   independently per participant, so a failure/NaN on one slope never
%   blocks the others -- if a given slope can't be evaluated for a
%   participant, only that slope is skipped for them, the rest still are.
%   Never errors: a leave-one-out refit that fails skips that participant
%   entirely (all six slopes); a slope/SE that can't be computed is simply
%   left out of that slope's evaluation. This function only ever produces
%   diagnostic flags -- it never removes a participant, re-selects a
%   model, or changes candidate-selection results.

T = m.Variables;
pcol = opts.participant_col;
participants = unique(T.(pcol));

full_analysis = compute_followup_rest_condition_analysis(m, opts.hrv_col, cfg);
full_slopes = full_analysis.simple_slopes;
n_slopes = numel(full_slopes);

slope_keys = cell(n_slopes, 1);
for k = 1:n_slopes
    slope_keys{k} = sprintf('%s_%skmh', full_slopes(k).rest_condition, full_slopes(k).speed);
end

formula = char(m.Formula);
fit_method = m.FitMethod;

deltas = nan(numel(participants), n_slopes);
flagged_any = false(numel(participants), 1);
flagged_by_slope = cell(n_slopes, 1);
for k = 1:n_slopes
    flagged_by_slope{k} = {};
end

for i = 1:numel(participants)
    mask = T.(pcol) ~= participants(i);
    T_sub = T(mask, :);
    try
        m_i = fitlme(T_sub, formula, 'FitMethod', fit_method);
    catch
        continue; % leave-one-out refit failed for this participant -- skip entirely
    end

    try
        analysis_i = compute_followup_rest_condition_analysis(m_i, opts.hrv_col, cfg);
    catch
        continue; % none of the six slopes evaluable for this participant -- skip entirely
    end

    for k = 1:n_slopes
        beta_full = full_slopes(k).estimate;
        se_full = full_slopes(k).se;
        beta_i = analysis_i.simple_slopes(k).estimate;
        if isnan(beta_full) || isnan(beta_i)
            continue; % this slope not evaluable -- other slopes still assessed below
        end
        deltas(i, k) = beta_i - beta_full;
        if ~isnan(se_full) && se_full > 0 && ...
                abs(deltas(i, k)) > cfg.loo_influence_se_multiple * se_full
            flagged_by_slope{k}{end+1} = char(participants(i)); %#ok<AGROW>
            flagged_any(i) = true;
        end
    end
end

flagged_participants = {};
for k = 1:n_slopes
    flagged_participants = [flagged_participants, flagged_by_slope{k}]; %#ok<AGROW>
end
flagged_participants = unique(flagged_participants, 'stable');

% Explicit NaN filtering: NaN entries (failed LOO refits, or a slope not evaluable for
% a given participant) never contaminate that slope's max, and a slope
% with zero valid deltas is left as NaN rather than propagating into the
% cross-slope maximum below.
max_abs_delta_by_slope = nan(n_slopes, 1);
for k = 1:n_slopes
    valid_k = abs(deltas(:, k));
    valid_k = valid_k(~isnan(valid_k));
    if ~isempty(valid_k)
        max_abs_delta_by_slope(k) = max(valid_k);
    end
end

% Cross-slope maximum, again ignoring any slope left at NaN above (i.e. a
% slope with no valid LOO delta at all) rather than letting it propagate.
valid_slopes = find(~isnan(max_abs_delta_by_slope));
if isempty(valid_slopes)
    max_abs_delta = NaN;
    worst_idx = [];
else
    [max_abs_delta, local_idx] = max(max_abs_delta_by_slope(valid_slopes));
    worst_idx = valid_slopes(local_idx);
end

loo = struct();
loo.any_flagged = any(flagged_any);
loo.flagged_participants = flagged_participants;
loo.max_abs_delta = max_abs_delta;
if isnan(max_abs_delta)
    loo.max_abs_delta_rest_condition = '';
    loo.max_abs_delta_speed = '';
else
    loo.max_abs_delta_rest_condition = full_slopes(worst_idx).rest_condition;
    loo.max_abs_delta_speed = full_slopes(worst_idx).speed;
end

% Per-slope breakdown, keyed by e.g. 'EO1_1kmh', 'EC_4kmh', ...
loo.slope_max_abs_delta = struct();
loo.slope_flagged_participants = struct();
detail_parts = cell(n_slopes, 1);
for k = 1:n_slopes
    key = slope_keys{k};
    loo.slope_max_abs_delta.(key) = max_abs_delta_by_slope(k);
    loo.slope_flagged_participants.(key) = flagged_by_slope{k};
    detail_parts{k} = sprintf('%s: max|delta beta|=%.3f, flagged=%s', ...
        key, max_abs_delta_by_slope(k), strjoin(flagged_by_slope{k}, ';'));
end
loo.detail = [strjoin(detail_parts, '; ') ';'];

end
