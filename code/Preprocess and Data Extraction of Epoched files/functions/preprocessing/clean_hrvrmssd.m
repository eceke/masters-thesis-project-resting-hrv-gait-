function out = clean_hrvrmssd(cfg, record)
%CLEAN_HRVRMSSD Clean device-derived RMSSD using hrvisvalid flags.
%
% Uses:
%   - hrvrmssd_live.csv
%   - hrvisvalid_live.csv
%
% Main rule:
%   if hrvisvalid == cfg.hrvisvalid.invalid_value, RMSSD is invalid.

%% Validate
if nargin < 2
    error('clean_hrvrmssd:MissingInputs', ...
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
out.meta.function_name = 'clean_hrvrmssd';

%% Resolve sources
rmssd_info = local_get_file_info(record, 'hrvrmssd_live.csv');
valid_info = local_get_file_info(record, 'hrvisvalid_live.csv');

out.source.rmssd = rmssd_info;
out.source.validity = valid_info;
out.source.rmssd_requirement_level = get_file_requirement_level(cfg, record.sensor, 'hrvrmssd_live.csv');
out.source.validity_requirement_level = get_file_requirement_level(cfg, record.sensor, 'hrvisvalid_live.csv');

%% Missing physical source handling
if ~rmssd_info.physical_exists || ~valid_info.physical_exists
    missing_list = {};
    if ~rmssd_info.physical_exists
        missing_list{end+1} = 'hrvrmssd_live.csv'; %#ok<AGROW>
    end
    if ~valid_info.physical_exists
        missing_list{end+1} = 'hrvisvalid_live.csv'; %#ok<AGROW>
    end

    out.warnings{end+1} = sprintf( ...
        'Missing Physical source(s): %s. Returning NaN summaries.', ...
        strjoin(missing_list, ', '));

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load files
rmssd_loaded = load_simple_csv_column( ...
    rmssd_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'hrvrmssd_live');

valid_loaded = load_simple_csv_column( ...
    valid_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'hrvisvalid_live');

out.loaded.rmssd_loader_output = rmssd_loaded;
out.loaded.validity_loader_output = valid_loaded;

rmssd = double(rmssd_loaded.data(:));
validity = double(valid_loaded.data(:));

%% Row-count check
n_rmssd = numel(rmssd);
n_validity = numel(validity);

if n_rmssd ~= n_validity
    out.warnings{end+1} = sprintf( ...
        'Row-count mismatch: hrvrmssd_live has %d rows, hrvisvalid_live has %d rows. Truncating to minimum length.', ...
        n_rmssd, n_validity);

    n = min(n_rmssd, n_validity);
    rmssd = rmssd(1:n);
    validity = validity(1:n);
else
    n = n_rmssd;
end

if n == 0
    out.warnings{end+1} = 'RMSSD/validity files loaded but contain zero usable rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = 'physical';
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Flagged table
T = table();
T.sample_idx = (1:n)';
T.rmssd_ms = rmssd;
T.hrvisvalid = validity;

T.is_missing_original = isnan(T.rmssd_ms);
T.is_validity_missing = isnan(T.hrvisvalid);

T.is_invalid_by_device = T.hrvisvalid == cfg.hrvisvalid.invalid_value;
T.is_valid_by_device = T.hrvisvalid == cfg.hrvisvalid.valid_value;

% If validity is neither 0 nor 1, flag as suspicious/invalid.
T.is_unknown_validity_value = ...
    ~T.is_validity_missing & ...
    ~T.is_invalid_by_device & ...
    ~T.is_valid_by_device;

T.is_below_min = T.rmssd_ms < cfg.hrvrmssd.min;
T.is_above_max = T.rmssd_ms > cfg.hrvrmssd.max;
T.is_threshold_flag = T.is_below_min | T.is_above_max;

T.is_invalid = ...
    T.is_missing_original | ...
    T.is_validity_missing | ...
    T.is_invalid_by_device | ...
    T.is_unknown_validity_value | ...
    T.is_threshold_flag;

out.flagged_table = T;

%% Cleaned table
cleaned = T.rmssd_ms;
cleaned(T.is_invalid) = NaN;

interpolated_mask = false(n,1);
smoothed_mask = false(n,1);

% No interpolation by default because global cfg.flags.enable_interpolation = false.
% Even if enabled globally, HRV-live smoothing/interpolation should remain cautious.
if isfield(cfg.flags, 'enable_interpolation') && cfg.flags.enable_interpolation && ...
        isfield(cfg.hrvrmssd, 'enable_interpolation') && cfg.hrvrmssd.enable_interpolation

    original_nan_mask = isnan(cleaned);
    if any(original_nan_mask)
        cleaned_interp = fillmissing(cleaned, 'linear', 'EndValues', 'none');
        interpolated_mask = original_nan_mask & ~isnan(cleaned_interp);
        cleaned = cleaned_interp;
    end
end

if isfield(cfg.flags, 'enable_smoothing') && cfg.flags.enable_smoothing && ...
        isfield(cfg.hrvrmssd, 'enable_smoothing') && cfg.hrvrmssd.enable_smoothing

    if strcmpi(cfg.hrvrmssd.smoothing_method, 'movmean')
        before = cleaned;
        cleaned = movmean(cleaned, cfg.hrvrmssd.smoothing_window, 'omitnan');
        smoothed_mask = ~isnan(before) & ~isnan(cleaned) & ...
            (abs(cleaned - before) > eps(before));
    end
end

C = T;
C.rmssd_cleaned_ms = cleaned;
C.was_interpolated = interpolated_mask;
C.was_smoothed = smoothed_mask;

out.cleaned_table = C;

%% Summary
valid_mask_final = ~isnan(C.rmssd_cleaned_ms);
valid_values = C.rmssd_cleaned_ms(valid_mask_final);

if isempty(valid_values)
    summary = local_nan_summary();
else
    summary = struct();
    summary.rmssd_live_mean = mean(valid_values, 'omitnan');
    summary.rmssd_live_std = std(valid_values, 'omitnan');
    summary.rmssd_live_min = min(valid_values, [], 'omitnan');
    summary.rmssd_live_max = max(valid_values, [], 'omitnan');
    summary.rmssd_live_median = median(valid_values, 'omitnan');
    summary.rmssd_live_valid_fraction = mean(valid_mask_final);
    summary.rmssd_live_n_valid = sum(valid_mask_final);
end

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = 'physical';
qc.total_rows = n;

qc.rmssd_rows_original = n_rmssd;
qc.validity_rows_original = n_validity;
qc.row_count_mismatch = n_rmssd ~= n_validity;

qc.missing_count_original = sum(T.is_missing_original);
qc.validity_missing_count = sum(T.is_validity_missing);
qc.invalid_by_device_count = sum(T.is_invalid_by_device);
qc.unknown_validity_value_count = sum(T.is_unknown_validity_value);
qc.threshold_flag_count = sum(T.is_threshold_flag);
qc.below_min_count = sum(T.is_below_min);
qc.above_max_count = sum(T.is_above_max);
qc.invalid_count_total = sum(T.is_invalid);
qc.interpolated_count = sum(interpolated_mask);

qc.final_valid_count = sum(valid_mask_final);
qc.final_nan_count = sum(~valid_mask_final);
qc.valid_fraction_final = mean(valid_mask_final);

qc.threshold_min = cfg.hrvrmssd.min;
qc.threshold_max = cfg.hrvrmssd.max;

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
        'Mass flagging warning: %.1f%% of RMSSD-live rows invalid.', ...
        100 * flag_fraction);
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned RMSSD-live values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned RMSSD-live output has near-zero variance.';
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

error('clean_hrvrmssd:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();
s.rmssd_live_mean = NaN;
s.rmssd_live_std = NaN;
s.rmssd_live_min = NaN;
s.rmssd_live_max = NaN;
s.rmssd_live_median = NaN;
s.rmssd_live_valid_fraction = NaN;
s.rmssd_live_n_valid = 0;
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
qc.rmssd_rows_original = NaN;
qc.validity_rows_original = NaN;
qc.row_count_mismatch = false;

qc.missing_count_original = NaN;
qc.validity_missing_count = NaN;
qc.invalid_by_device_count = NaN;
qc.unknown_validity_value_count = NaN;
qc.threshold_flag_count = NaN;
qc.below_min_count = NaN;
qc.above_max_count = NaN;
qc.invalid_count_total = NaN;
qc.interpolated_count = NaN;
qc.final_valid_count = NaN;
qc.final_nan_count = NaN;
qc.valid_fraction_final = NaN;

qc.threshold_min = cfg.hrvrmssd.min;
qc.threshold_max = cfg.hrvrmssd.max;

qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_messages = '';
end