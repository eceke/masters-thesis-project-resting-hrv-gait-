function report = build_missingness_report(T, cfg)
%BUILD_MISSINGNESS_REPORT Summarize missing data before model fitting
%   (Step 5): counts by variable, by participant, and available rows per
%   rest_condition / walking_task / speed_factor. Includes the log-transform
%   invalidation counts so non-positive RMSSD/HF values are visible here too.

report = struct();

value_cols = [cfg.hrv_var_names(:)', strcat('z_', cfg.hrv_var_names(:)'), ...
              cfg.gait_vars, strcat('z_', cfg.gait_vars)];
value_cols = intersect(value_cols, T.Properties.VariableNames, 'stable');

% ---- by variable ----
n_missing = zeros(numel(value_cols), 1);
for i = 1:numel(value_cols)
    n_missing(i) = sum(isnan(T.(value_cols{i})));
end
var_names = value_cols(:);

% Log-outcome sensitivity variables (limited scope: cfg.log_sensitivity_outcome
% only, see transform_and_standardize.m) -- appended to by_variable ONLY
% (value_cols above, used by the by-participant section below, is left
% untouched). z_log_<outcome> is a real T column; log_<outcome> itself
% (log-transformed, not yet z-scored) is never persisted to T, so its
% missingness is computed here directly with the exact same
% safe_log_transform.m the pipeline already uses for that variable -- not
% a new transform, just reporting on the existing one, with the same
% n_missing/pct_missing calculation used for every other row here.
log_outcome = cfg.log_sensitivity_outcome;
if cfg.enable_log_sensitivity && ~isempty(log_outcome) && ismember(log_outcome, T.Properties.VariableNames)
    z_log_col = ['z_log_' log_outcome];
    if ismember(z_log_col, T.Properties.VariableNames)
        var_names = [var_names; {z_log_col}];
        n_missing = [n_missing; sum(isnan(T.(z_log_col)))];
    end
    log_x = safe_log_transform(T.(log_outcome));
    var_names = [var_names; {['log_' log_outcome]}];
    n_missing = [n_missing; sum(isnan(log_x))];
end

report.by_variable = table(var_names, n_missing, ...
    round(100 * n_missing / height(T), 2), ...
    'VariableNames', {'variable', 'n_missing', 'pct_missing'});

% ---- by participant ----
participants = categories(categorical(T.(cfg.participant_col)));
n_missing_pp = zeros(numel(participants), 1);
n_rows_pp = zeros(numel(participants), 1);
for i = 1:numel(participants)
    mask = T.(cfg.participant_col) == participants{i};
    sub = T(mask, value_cols);
    n_missing_pp(i) = sum(sum(ismissing(sub)));
    n_rows_pp(i) = height(sub);
end
report.by_participant = table(participants, n_rows_pp, n_missing_pp, ...
    'VariableNames', {'participant_id', 'n_rows', 'n_missing_values'});

% ---- rows available per design factor ----
report.rows_per_rest_condition = groupcounts(T, cfg.rest_condition_col);
report.rows_per_walking_task   = groupcounts(T, cfg.walking_task_col);
report.rows_per_speed_factor   = groupcounts(T, cfg.speed_col);

end
