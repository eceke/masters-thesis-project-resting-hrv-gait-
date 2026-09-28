function out = clean_tempmean(cfg, record)
%CLEAN_TEMPMEAN Preprocess tempmean_live.csv.
%
% tempmean_live is treated as a low-resolution/context temperature summary.
% Strategy:
%   - load preferred Physical source
%   - apply broad plausibility threshold
%   - invalid values -> NaN
%   - no interpolation by default
%   - smoothing only if explicitly enabled, but default should be false

%% Validate
if nargin < 2
    error('clean_tempmean:MissingInputs', ...
        'Both cfg and record are required.');
end

%% Init
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
out.meta.function_name = 'clean_tempmean';
out.meta.role = 'temperature_context_summary';

%% Resolve source
tempmean_info = local_get_file_info(record, 'tempmean_live.csv');

out.source = tempmean_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'tempmean_live.csv');

%% Missing physical source handling
if ~tempmean_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical tempmean_live.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load physical tempmean
loaded = load_simple_csv_column( ...
    tempmean_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'tempmean_live');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_tempmean:LoadFailed', ...
        'tempmean_live.csv could not be parsed numerically: %s', ...
        tempmean_info.preferred_path);
end

tempmean_data = loaded.data;

if isempty(tempmean_data)
    out.warnings{end+1} = 'tempmean_live.csv loaded but contains zero rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = tempmean_info.preferred_source;
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

if size(tempmean_data, 2) ~= 1
    out.warnings{end+1} = sprintf( ...
        'tempmean_live.csv expected 1 column but found %d. Using first column only.', ...
        size(tempmean_data, 2));
    tempmean_data = tempmean_data(:, 1);
end

tempmean = double(tempmean_data(:));
n = numel(tempmean);

%% Flagged table
F = table();
F.sample_idx = (1:n)';
F.tempmean = tempmean;

F.is_missing_original = isnan(F.tempmean);

F.is_below_min = F.tempmean < cfg.tempmean.min;
F.is_above_max = F.tempmean > cfg.tempmean.max;
F.is_threshold_flag = F.is_below_min | F.is_above_max;

F.is_invalid = F.is_missing_original | F.is_threshold_flag;

out.flagged_table = F;

%% Cleaned
cleaned = F.tempmean;
cleaned(F.is_invalid) = NaN;

interpolated_mask = false(n,1);
smoothed_mask = false(n,1);

% Interpolation intentionally controlled by global flag.
if isfield(cfg.flags, 'enable_interpolation') && cfg.flags.enable_interpolation
    original_nan_mask = isnan(cleaned);
    if any(original_nan_mask)
        cleaned_interp = fillmissing(cleaned, 'linear', 'EndValues', 'none');
        interpolated_mask = original_nan_mask & ~isnan(cleaned_interp);
        cleaned = cleaned_interp;
    end
end

% Smoothing should normally be OFF for this signal.
if isfield(cfg.flags, 'enable_smoothing') && cfg.flags.enable_smoothing && ...
        isfield(cfg.tempmean, 'enable_smoothing') && cfg.tempmean.enable_smoothing

    if strcmpi(cfg.tempmean.smoothing_method, 'movmean')
        before = cleaned;
        cleaned = movmean(cleaned, cfg.tempmean.smoothing_window, 'omitnan');

        smoothed_mask = ~isnan(before) & ~isnan(cleaned) & ...
            (abs(cleaned - before) > eps(before));
    else
        out.warnings{end+1} = sprintf( ...
            'Unknown tempmean smoothing method "%s". No smoothing applied.', ...
            cfg.tempmean.smoothing_method);
    end
end

C = F;
C.tempmean_cleaned = cleaned;
C.was_interpolated = interpolated_mask;
C.was_smoothed = smoothed_mask;

out.cleaned_table = C;

%% Summary
valid_mask = ~isnan(C.tempmean_cleaned);
valid_values = C.tempmean_cleaned(valid_mask);

summary = local_nan_summary();

summary.tempmean_n_samples = n;
summary.tempmean_n_valid = sum(valid_mask);
summary.tempmean_valid_fraction = mean(valid_mask);
summary.tempmean_invalid_ratio = mean(F.is_invalid);

if ~isempty(valid_values)
    summary.tempmean_mean = mean(valid_values, 'omitnan');
    summary.tempmean_std = std(valid_values, 'omitnan');
    summary.tempmean_min = min(valid_values, [], 'omitnan');
    summary.tempmean_max = max(valid_values, [], 'omitnan');
    summary.tempmean_median = median(valid_values, 'omitnan');
    summary.tempmean_range = summary.tempmean_max - summary.tempmean_min;
end

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);

qc.source_available = true;
qc.source_used = tempmean_info.preferred_source;

qc.total_rows = n;
qc.missing_count_original = sum(F.is_missing_original);
qc.threshold_flag_count = sum(F.is_threshold_flag);
qc.below_min_count = sum(F.is_below_min);
qc.above_max_count = sum(F.is_above_max);
qc.invalid_count_total = sum(F.is_invalid);

qc.interpolated_count = sum(interpolated_mask);
qc.smoothed_count = sum(smoothed_mask);

qc.final_valid_count = sum(valid_mask);
qc.final_nan_count = sum(~valid_mask);
qc.valid_fraction_final = mean(valid_mask);

qc.threshold_min = cfg.tempmean.min;
qc.threshold_max = cfg.tempmean.max;

qc.warning_mass_flagging = mean(F.is_invalid) >= cfg.qc.mass_flagging_fraction_warning;
qc.warning_all_nan_output = all(~valid_mask);

if numel(valid_values) <= 1
    qc.warning_zero_variance = false;
else
    qc.warning_zero_variance = std(valid_values, 'omitnan') <= cfg.qc.zero_variance_tolerance;
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of tempmean rows invalid.', ...
        100 * mean(F.is_invalid));
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned tempmean values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned tempmean output has near-zero variance.';
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

error('clean_tempmean:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);

end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();

s.tempmean_n_samples = 0;
s.tempmean_n_valid = 0;
s.tempmean_valid_fraction = NaN;
s.tempmean_invalid_ratio = NaN;

s.tempmean_mean = NaN;
s.tempmean_std = NaN;
s.tempmean_min = NaN;
s.tempmean_max = NaN;
s.tempmean_median = NaN;
s.tempmean_range = NaN;

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
qc.invalid_count_total = NaN;

qc.interpolated_count = NaN;
qc.smoothed_count = NaN;

qc.final_valid_count = NaN;
qc.final_nan_count = NaN;
qc.valid_fraction_final = NaN;

qc.threshold_min = cfg.tempmean.min;
qc.threshold_max = cfg.tempmean.max;

qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_messages = '';

end