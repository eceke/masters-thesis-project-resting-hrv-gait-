function out = clean_hr(cfg, record)
%CLEAN_HR Preprocess hr_live.csv using preferred Physical source.
%
% PURPOSE
%   Cleans low-resolution heart-rate summary data and returns:
%   - source info
%   - flagged table
%   - cleaned table
%   - summary metrics
%   - QC metrics
%   - warnings
%
% INPUT
%   cfg    : config struct from get_preprocessing_config()
%   record : one discovery record from discover_participants_and_segments()
%
% OUTPUT
%   out : struct with fields
%       .meta
%       .source
%       .loaded
%       .flagged_table
%       .cleaned_table
%       .summary
%       .qc
%       .warnings
%
% NOTES
%   - preferred source = physical if available
%   - invalid values are converted to NaN in cleaned output
%   - interpolation is only applied if globally enabled
%   - smoothing is only applied if enabled in cfg.hr
%   - local outlier detection is optional and config-driven

%% ------------------------------------------------------------------------
% Validate inputs
if nargin < 2
    error('clean_hr:MissingInputs', ...
        'Both cfg and record are required.');
end

if ~isfield(record, 'files') || isempty(record.files)
    error('clean_hr:BadRecord', ...
        'record.files is missing or empty.');
end

%% ------------------------------------------------------------------------
% Initialize output
out = struct();
out.meta = struct();
out.source = struct();
out.loaded = struct();
out.flagged_table = table();
out.cleaned_table = table();
out.summary = struct();
out.qc = struct();
out.warnings = {};

out.meta.participant_id = record.participant_id;
out.meta.sensor = record.sensor;
out.meta.segment_name = record.segment_name;
out.meta.segment_type = record.segment_type;
out.meta.segment_path = record.segment_path;
out.meta.function_name = 'clean_hr';

%% ------------------------------------------------------------------------
% Resolve source
hr_info = local_get_file_info(record, 'hr_live.csv');

out.source.expected_name = hr_info.expected_name;
out.source.raw_path = hr_info.raw_path;
out.source.raw_exists = hr_info.raw_exists;
out.source.physical_path = hr_info.physical_path;
out.source.physical_exists = hr_info.physical_exists;
out.source.preferred_source = hr_info.preferred_source;
out.source.preferred_path = hr_info.preferred_path;
out.source.status = hr_info.status;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'hr_live.csv');

%% ------------------------------------------------------------------------
% Handle missing preferred source
if ~hr_info.physical_exists
    out.warnings{end+1} = sprintf([ ...
        'Preferred Physical HR source is missing for %s | %s | %s. ' ...
        'Returning NaN summaries.'], ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% ------------------------------------------------------------------------
% Load preferred HR source
loaded = load_simple_csv_column( ...
    hr_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'hr_live');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_hr:LoadFailed', ...
        'Heart-rate file could not be parsed numerically: %s', hr_info.preferred_path);
end

hr_data = loaded.data;

if isempty(hr_data)
    out.warnings{end+1} = 'HR file loaded but contains zero rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = hr_info.preferred_source;
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

if size(hr_data,2) ~= 1
    out.warnings{end+1} = sprintf( ...
        'hr_live.csv expected 1 column but found %d. Using first column only.', ...
        size(hr_data,2));
    hr_data = hr_data(:,1);
end

hr_raw = double(hr_data(:));
n = numel(hr_raw);

%% ------------------------------------------------------------------------
% Build base flagged table
T = table();
T.sample_idx = (1:n)';
T.hr_bpm = hr_raw;

% Missing
T.is_missing_original = isnan(T.hr_bpm);

% Threshold flags
T.is_below_min = T.hr_bpm < cfg.hr.min;
T.is_above_max = T.hr_bpm > cfg.hr.max;
T.is_threshold_flag = T.is_below_min | T.is_above_max;

% Local outlier rule (optional)
T.is_local_outlier = false(n,1);

if isfield(cfg.hr, 'enable_local_outlier_rule') && cfg.hr.enable_local_outlier_rule
    valid_for_outlier = ~isnan(T.hr_bpm);

    % Need enough points for a local robust rule
    if sum(valid_for_outlier) >= max(3, cfg.hr.local_outlier_window)
        local_med = movmedian(T.hr_bpm, cfg.hr.local_outlier_window, 'omitnan');
        abs_dev = abs(T.hr_bpm - local_med);
        local_mad = movmedian(abs_dev, cfg.hr.local_outlier_window, 'omitnan');

        robust_scale = 1.4826 .* local_mad;
        outlier_mask = abs_dev > (cfg.hr.local_outlier_thresh .* robust_scale);

        % Avoid flagging points where robust scale is zero or NaN
        outlier_mask(isnan(outlier_mask)) = false;
        outlier_mask(robust_scale == 0 | isnan(robust_scale)) = false;

        T.is_local_outlier = outlier_mask;
    end
end

% Combined invalid flag
T.is_invalid = T.is_missing_original | T.is_threshold_flag | T.is_local_outlier;

out.flagged_table = T;

%% ------------------------------------------------------------------------
% Cleaned series
cleaned = T.hr_bpm;
cleaned(T.is_invalid) = NaN;

interpolated_mask = false(n,1);
smoothed_mask = false(n,1);

%% ------------------------------------------------------------------------
% Optional interpolation controlled by cfg.flags.enable_interpolation
if isfield(cfg.flags, 'enable_interpolation') && cfg.flags.enable_interpolation && ...
        isfield(cfg.hr, 'enable_interpolation') && cfg.hr.enable_interpolation

    original_nan_mask = isnan(cleaned);

    if any(original_nan_mask)
        cleaned_interp = fillmissing(cleaned, 'linear', 'EndValues', 'none');
        interpolated_mask = original_nan_mask & ~isnan(cleaned_interp);
        cleaned = cleaned_interp;
    end
end

%% ------------------------------------------------------------------------
% Optional smoothing
if isfield(cfg.flags, 'enable_smoothing') && cfg.flags.enable_smoothing && ...
        isfield(cfg.hr, 'enable_smoothing') && cfg.hr.enable_smoothing

    if strcmpi(cfg.hr.smoothing_method, 'movmean')
        cleaned_before_smooth = cleaned;
        cleaned = movmean(cleaned, cfg.hr.smoothing_window, 'omitnan');

        smoothed_mask = ~isnan(cleaned_before_smooth) & ~isnan(cleaned) & ...
            (abs(cleaned - cleaned_before_smooth) > eps(cleaned_before_smooth));
    else
        out.warnings{end+1} = sprintf( ...
            'Unknown HR smoothing method "%s". No smoothing applied.', ...
            cfg.hr.smoothing_method);
    end
end

%% ------------------------------------------------------------------------
% Build cleaned table
C = T;
C.hr_cleaned_bpm = cleaned;
C.was_interpolated = interpolated_mask;
C.was_smoothed = smoothed_mask;

out.cleaned_table = C;

%% ------------------------------------------------------------------------
% Summary metrics
valid_mask_final = ~isnan(C.hr_cleaned_bpm);
valid_values = C.hr_cleaned_bpm(valid_mask_final);

if isempty(valid_values)
    summary = local_nan_summary();
else
    summary = struct();
    summary.hr_mean = mean(valid_values, 'omitnan');
    summary.hr_std = std(valid_values, 'omitnan');
    summary.hr_min = min(valid_values, [], 'omitnan');
    summary.hr_max = max(valid_values, [], 'omitnan');
    summary.hr_median = median(valid_values, 'omitnan');
    summary.hr_valid_fraction = mean(valid_mask_final);
    summary.hr_n_valid = sum(valid_mask_final);
end

out.summary = summary;

%% ------------------------------------------------------------------------
% QC metrics
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = hr_info.preferred_source;
qc.total_rows = n;
qc.missing_count_original = sum(T.is_missing_original);
qc.threshold_flag_count = sum(T.is_threshold_flag);
qc.below_min_count = sum(T.is_below_min);
qc.above_max_count = sum(T.is_above_max);
qc.local_outlier_count = sum(T.is_local_outlier);
qc.invalid_count_total = sum(T.is_invalid);
qc.interpolated_count = sum(interpolated_mask);
qc.final_valid_count = sum(valid_mask_final);
qc.final_nan_count = sum(~valid_mask_final);
qc.valid_fraction_final = mean(valid_mask_final);
qc.threshold_min = cfg.hr.min;
qc.threshold_max = cfg.hr.max;

flag_fraction = mean(T.is_invalid);
qc.warning_mass_flagging = flag_fraction >= cfg.qc.mass_flagging_fraction_warning;
qc.warning_all_nan_output = all(~valid_mask_final);

if numel(valid_values) <= 1
    qc.warning_zero_variance = false;
else
    qc.warning_zero_variance = std(valid_values, 'omitnan') <= cfg.qc.zero_variance_tolerance;
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of HR values flagged/invalid.', ...
        100 * flag_fraction);
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned HR values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned HR output has near-zero variance.';
end

qc.warning_messages = strjoin(out.warnings, ' | ');
out.qc = qc;

end

%% ========================================================================
function file_info = local_get_file_info(record, expected_name)

file_info = [];

for i = 1:numel(record.files)
    if strcmp(record.files(i).expected_name, expected_name)
        file_info = record.files(i);
        return;
    end
end

error('clean_hr:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();
s.hr_mean = NaN;
s.hr_std = NaN;
s.hr_min = NaN;
s.hr_max = NaN;
s.hr_median = NaN;
s.hr_valid_fraction = NaN;
s.hr_n_valid = 0;
end

%% ------------------------------------------------------------------------
function qc = local_base_qc(cfg, record)

qc = struct();
qc.participant_id = record.participant_id;
qc.sensor = record.sensor;
qc.segment_name = record.segment_name;
qc.segment_type = record.segment_type;

qc.source_available = false;
qc.source_used = '';

qc.total_rows = NaN;
qc.missing_count_original = NaN;
qc.threshold_flag_count = NaN;
qc.below_min_count = NaN;
qc.above_max_count = NaN;
qc.local_outlier_count = NaN;
qc.invalid_count_total = NaN;
qc.interpolated_count = NaN;
qc.final_valid_count = NaN;
qc.final_nan_count = NaN;
qc.valid_fraction_final = NaN;

qc.threshold_min = cfg.hr.min;
qc.threshold_max = cfg.hr.max;

qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_messages = '';
end