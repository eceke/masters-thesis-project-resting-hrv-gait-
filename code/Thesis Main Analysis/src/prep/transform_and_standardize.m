function [T, qc] = transform_and_standardize(T, cfg)
%TRANSFORM_AND_STANDARDIZE Build z-scored HRV predictors and gait outcomes
%   (Step 4). meanHR_ecg is z-scored directly; RMSSD_ecg and HF_ecg are
%   natural-log transformed first (right-skewed HRV metrics), then z-scored.
%   Non-positive values are set to missing by safe_log_transform and counted
%   here for the QC report.

qc = struct();
qc.log_transform_invalid = struct();
qc.standardization = struct();

%% HRV predictors
% Each resting-state cardiac measurement is repeated across the four
% walking-condition rows. Use each participant-by-rest-condition
% measurement only once when calculating the mean and SD.

hrv_key_cols = { ...
    cfg.participant_col, ...
    cfg.rest_condition_col ...
};

[~, hrv_unique_idx] = unique( ...
    T(:, hrv_key_cols), ...
    'rows', ...
    'stable' ...
);

hrv_names = cfg.hrv_var_names;

for i = 1:numel(hrv_names)
    v = hrv_names{i};
    spec = cfg.hrv_vars.(v);
    x = T.(v);

    if spec.log_transform
        [x_transformed, ~, invalid_mask] = safe_log_transform(x);

        % Count invalid values at the level of unique resting-state
        % measurements rather than repeated long-format rows.
        qc.log_transform_invalid.(v) = ...
            sum(invalid_mask(hrv_unique_idx));
    else
        x_transformed = x;
        qc.log_transform_invalid.(v) = 0;
    end

    % Calculate scaling parameters from unique physiological measurements.
    x_unique = x_transformed(hrv_unique_idx);
    mu = mean(x_unique, 'omitnan');
    sigma = std(x_unique, 0, 'omitnan');

    if isnan(sigma) || sigma == 0
        error( ...
            'transform_and_standardize:invalidHRVStandardDeviation', ...
            'Cannot standardize %s because its SD is zero or undefined.', ...
            v ...
        );
    end

    % Apply the same scaling parameters to all long-format rows.
    T.(['z_' v]) = (x_transformed - mu) ./ sigma;

    qc.standardization.(v).mean = mu;
    qc.standardization.(v).sd = sigma;
    qc.standardization.(v).n_unique_measurements = ...
        sum(~isnan(x_unique));
end

%% Gait outcomes
% Each gait measurement is repeated across the three resting-state rows.
% Use each participant-by-task-by-speed gait measurement only once when
% calculating the mean and SD.

gait_key_cols = { ...
    cfg.participant_col, ...
    cfg.walking_task_col, ...
    cfg.speed_col ...
};

[~, gait_unique_idx] = unique( ...
    T(:, gait_key_cols), ...
    'rows', ...
    'stable' ...
);

for i = 1:numel(cfg.gait_vars)
    v = cfg.gait_vars{i};
    x = T.(v);

    % Calculate scaling parameters from unique gait measurements.
    x_unique = x(gait_unique_idx);
    mu = mean(x_unique, 'omitnan');
    sigma = std(x_unique, 0, 'omitnan');

    if isnan(sigma) || sigma == 0
        error( ...
            'transform_and_standardize:invalidGaitStandardDeviation', ...
            'Cannot standardize %s because its SD is zero or undefined.', ...
            v ...
        );
    end

    % Apply the same scaling parameters to all long-format rows.
    T.(['z_' v]) = (x - mu) ./ sigma;

    qc.standardization.(v).mean = mu;
    qc.standardization.(v).sd = sigma;
    qc.standardization.(v).n_unique_measurements = ...
        sum(~isnan(x_unique));
end

%% Log-outcome sensitivity variable (limited scope: cfg.log_sensitivity_outcome only)
% Builds a natural-log-transformed, separately z-scored copy of ONE gait
% outcome (SwingTimeVariability by default) for run_log_sensitivity_models.m.

log_outcome = cfg.log_sensitivity_outcome;
if cfg.enable_log_sensitivity && ~isempty(log_outcome) && ismember(log_outcome, T.Properties.VariableNames)
    x = T.(log_outcome);
    [x_log, ~, ~] = safe_log_transform(x);

    % QC count: every raw value that is zero, negative, or non-finite
    % (NaN/+-Inf) -- i.e. not valid for ln(). Counted once per unique
    % participant x walking_task x speed measurement (gait_unique_idx,
    % built above), consistent with how the raw gait QC is scoped.
    % "~isfinite(x) | x <= 0" is a single combined condition per
    % observation (equivalent to NOT(finite AND positive)), so it cannot
    % double-count: a NaN/Inf value is already caught by ~isfinite and
    % never separately re-counted by the "x <= 0" clause (NaN/+Inf both
    % evaluate that clause to false), and a finite non-positive value is
    % never separately re-counted by ~isfinite (it is already finite).
    x_unique_raw = x(gait_unique_idx);
    qc.log_transform_invalid.(log_outcome) = sum(~isfinite(x_unique_raw) | x_unique_raw <= 0);
    qc.log_transform_n_missing.(log_outcome) = sum(isnan(x_unique_raw));

    x_unique = x_log(gait_unique_idx);
    mu = mean(x_unique, 'omitnan');
    sigma = std(x_unique, 0, 'omitnan');

    if isnan(sigma) || sigma == 0
        error( ...
            'transform_and_standardize:invalidLogGaitStandardDeviation', ...
            'Cannot standardize log(%s) because its SD is zero or undefined.', ...
            log_outcome ...
        );
    end

    T.(['z_log_' log_outcome]) = (x_log - mu) ./ sigma;

    qc.standardization.(['log_' log_outcome]).mean = mu;
    qc.standardization.(['log_' log_outcome]).sd = sigma;
    qc.standardization.(['log_' log_outcome]).n_unique_measurements = ...
        sum(~isnan(x_unique));
end

end
