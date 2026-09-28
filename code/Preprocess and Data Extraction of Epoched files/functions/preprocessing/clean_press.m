function out = clean_press(cfg, record)
%CLEAN_PRESS Preprocess press.csv.
%
% Pressure is treated as exploratory/context/QC data.
% Strategy:
%   - load preferred Physical source
%   - apply broad plausibility thresholds
%   - invalid values -> NaN
%   - no smoothing
%   - no interpolation

%% Validate
if nargin < 2
    error('clean_press:MissingInputs', ...
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
out.meta.function_name = 'clean_press';
out.meta.role = 'exploratory_context_qc';

%% Resolve source
press_info = local_get_file_info(record, 'press.csv');

out.source = press_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'press.csv');

%% Missing physical source handling
if ~press_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical press.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load physical press
loaded = load_simple_csv_column( ...
    press_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'press');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_press:LoadFailed', ...
        'press.csv could not be parsed numerically: %s', ...
        press_info.preferred_path);
end

press_data = loaded.data;

if isempty(press_data)
    out.warnings{end+1} = 'press.csv loaded but contains zero rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = press_info.preferred_source;
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

if size(press_data, 2) ~= 1
    out.warnings{end+1} = sprintf( ...
        'press.csv expected 1 column but found %d. Using first column only.', ...
        size(press_data, 2));
    press_data = press_data(:, 1);
end

press = double(press_data(:));
n = numel(press);

%% Flagged table
F = table();
F.sample_idx = (1:n)';
F.press = press;

F.is_missing_original = isnan(F.press);

F.is_below_min = F.press < cfg.press.min;
F.is_above_max = F.press > cfg.press.max;
F.is_threshold_flag = F.is_below_min | F.is_above_max;

F.is_invalid = F.is_missing_original | F.is_threshold_flag;

out.flagged_table = F;

%% Cleaned table
cleaned = F.press;
cleaned(F.is_invalid) = NaN;

C = F;
C.press_cleaned = cleaned;

out.cleaned_table = C;

%% Summary
valid_mask = ~isnan(C.press_cleaned);
valid_values = C.press_cleaned(valid_mask);

summary = local_nan_summary();

summary.press_n_samples = n;
summary.press_n_valid = sum(valid_mask);
summary.press_valid_fraction = mean(valid_mask);
summary.press_invalid_ratio = mean(F.is_invalid);

if ~isempty(valid_values)
    summary.press_mean = mean(valid_values, 'omitnan');
    summary.press_std = std(valid_values, 'omitnan');
    summary.press_min = min(valid_values, [], 'omitnan');
    summary.press_max = max(valid_values, [], 'omitnan');
    summary.press_median = median(valid_values, 'omitnan');
    summary.press_range = summary.press_max - summary.press_min;
end

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);

qc.source_available = true;
qc.source_used = press_info.preferred_source;

qc.total_rows = n;
qc.missing_count_original = sum(F.is_missing_original);
qc.threshold_flag_count = sum(F.is_threshold_flag);
qc.below_min_count = sum(F.is_below_min);
qc.above_max_count = sum(F.is_above_max);
qc.invalid_count_total = sum(F.is_invalid);

qc.final_valid_count = sum(valid_mask);
qc.final_nan_count = sum(~valid_mask);
qc.valid_fraction_final = mean(valid_mask);

qc.threshold_min = cfg.press.min;
qc.threshold_max = cfg.press.max;

qc.warning_mass_flagging = mean(F.is_invalid) >= cfg.qc.mass_flagging_fraction_warning;
qc.warning_all_nan_output = all(~valid_mask);

if numel(valid_values) <= 1
    qc.warning_zero_variance = false;
else
    qc.warning_zero_variance = std(valid_values, 'omitnan') <= cfg.qc.zero_variance_tolerance;
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of press rows invalid.', ...
        100 * mean(F.is_invalid));
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned press values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned press output has near-zero variance.';
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

error('clean_press:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);

end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();

s.press_n_samples = 0;
s.press_n_valid = 0;
s.press_valid_fraction = NaN;
s.press_invalid_ratio = NaN;

s.press_mean = NaN;
s.press_std = NaN;
s.press_min = NaN;
s.press_max = NaN;
s.press_median = NaN;
s.press_range = NaN;

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

qc.final_valid_count = NaN;
qc.final_nan_count = NaN;
qc.valid_fraction_final = NaN;

qc.threshold_min = cfg.press.min;
qc.threshold_max = cfg.press.max;

qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_messages = '';

end