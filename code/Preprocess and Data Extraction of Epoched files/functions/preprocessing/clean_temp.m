function out = clean_temp(cfg, record)
%CLEAN_TEMP Preprocess temp.csv using preferred Physical source.
%
% PURPOSE
%   Cleans segment-level temperature data and returns:
%   - loaded raw/physical/preferred data
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
% REQUIRED DISCOVERY CONTENT
%   record.files must include temp.csv resolution info.
%
% DESIGN PRINCIPLES
%   - preferred source = physical if available
%   - do not silently delete problematic values
%   - keep flagged and cleaned versions distinct
%   - warn on mass-flagging
%   - robust to missing/empty input
%
% NOTES
%   This function returns results; the batch runner saves the output files.
%   - If temp source is unavailable, output summary metrics become NaN and
%     QC flags explain why.

%% ------------------------------------------------------------------------
% Validate inputs
if nargin < 2
    error('clean_temp:MissingInputs', ...
        'Both cfg and record are required.');
end

if ~isfield(record, 'files') || isempty(record.files)
    error('clean_temp:BadRecord', ...
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
out.meta.function_name = 'clean_temp';

%% ------------------------------------------------------------------------
% Resolve temp source info from discovery record
temp_info = local_get_file_info(record, 'temp.csv');

out.source.expected_name = temp_info.expected_name;
out.source.raw_path = temp_info.raw_path;
out.source.raw_exists = temp_info.raw_exists;
out.source.physical_path = temp_info.physical_path;
out.source.physical_exists = temp_info.physical_exists;
out.source.preferred_source = temp_info.preferred_source;
out.source.preferred_path = temp_info.preferred_path;
out.source.status = temp_info.status;

% Hard/soft interpretation from config
temp_requirement = get_file_requirement_level(cfg, record.sensor, 'temp.csv');
out.source.requirement_level = temp_requirement;

%% ------------------------------------------------------------------------
% Handle missing preferred source
if ~temp_info.physical_exists
    out.warnings{end+1} = sprintf([ ...
        'Preferred Physical temp source is missing for %s | %s | %s. ' ...
        'Returning NaN summaries.'], ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_mass_flagging = false;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_zero_variance = false;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% ------------------------------------------------------------------------
% Load preferred physical temp source
loaded = load_simple_csv_column( ...
    temp_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'temp');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_temp:LoadFailed', ...
        'Temperature file could not be parsed numerically: %s', temp_info.preferred_path);
end

temp_data = loaded.data;

if isempty(temp_data)
    out.warnings{end+1} = 'Temperature file loaded but contains zero rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = temp_info.preferred_source;
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

if size(temp_data,2) ~= 1
    out.warnings{end+1} = sprintf( ...
        'temp.csv expected 1 column but found %d. Using first column only.', ...
        size(temp_data,2));
    temp_data = temp_data(:,1);
end

temp_raw = double(temp_data(:));
n = numel(temp_raw);

%% ------------------------------------------------------------------------
% Build base table
T = table();
T.sample_idx = (1:n)';
T.temp_physical = temp_raw;

% Missing flags
T.is_missing_original = isnan(T.temp_physical);

% Threshold flags
T.is_below_min = T.temp_physical < cfg.temp.min;
T.is_above_max = T.temp_physical > cfg.temp.max;

% Combined invalid flag
T.is_threshold_flag = T.is_below_min | T.is_above_max;
T.is_invalid = T.is_missing_original | T.is_threshold_flag;

% Keep flagged version before cleaning
out.flagged_table = T;

%% ------------------------------------------------------------------------
% Cleaned series: invalid values -> NaN
cleaned = T.temp_physical;
cleaned(T.is_invalid) = NaN;

% Optional interpolation precedes optional smoothing.
% interpolation first, then light smoothing only on cleaned series.)
interpolated_mask = false(n,1);

%% ------------------------------------------------------------------------
% Optional interpolation
if isfield(cfg, 'flags') && cfg.flags.enable_interpolation && ...
        isfield(cfg.temp, 'enable_smoothing')
    % Interpolation policy is controlled globally; for temperature we allow
    % interpolation if enabled. Use linear fill for internal gaps only.
    original_nan_mask = isnan(cleaned);

    if any(original_nan_mask)
        cleaned_interp = fillmissing(cleaned, 'linear', 'EndValues', 'none');
        interpolated_mask = original_nan_mask & ~isnan(cleaned_interp);
        cleaned = cleaned_interp;
    end
end

%% ------------------------------------------------------------------------
% Optional light smoothing
smoothed_mask = false(n,1);

if isfield(cfg.flags, 'enable_smoothing') && cfg.flags.enable_smoothing && ...
        isfield(cfg.temp, 'enable_smoothing') && cfg.temp.enable_smoothing

    if strcmpi(cfg.temp.smoothing_method, 'movmean')
        cleaned_before_smooth = cleaned;
        cleaned = movmean(cleaned, cfg.temp.smoothing_window, 'omitnan');
        smoothed_mask = ~isnan(cleaned_before_smooth) & ~isnan(cleaned) & ...
            (abs(cleaned - cleaned_before_smooth) > eps(cleaned_before_smooth));
    else
        out.warnings{end+1} = sprintf( ...
            'Unknown temp smoothing method "%s". No smoothing applied.', ...
            cfg.temp.smoothing_method);
    end
end

%% ------------------------------------------------------------------------
% Build cleaned table
C = T;
C.temp_cleaned = cleaned;
C.was_interpolated = interpolated_mask;
C.was_smoothed = smoothed_mask;

out.cleaned_table = C;

%% ------------------------------------------------------------------------
% Summary metrics
valid_mask_final = ~isnan(C.temp_cleaned);
valid_values = C.temp_cleaned(valid_mask_final);

if isempty(valid_values)
    summary = local_nan_summary();
else
    summary = struct();
    summary.temp_mean = mean(valid_values, 'omitnan');
    summary.temp_std = std(valid_values, 'omitnan');
    summary.temp_min = min(valid_values, [], 'omitnan');
    summary.temp_max = max(valid_values, [], 'omitnan');
    summary.temp_median = median(valid_values, 'omitnan');
    summary.temp_valid_fraction = mean(valid_mask_final);
    summary.temp_n_valid = sum(valid_mask_final);
end

out.summary = summary;

%% ------------------------------------------------------------------------
% QC metrics
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = temp_info.preferred_source;
qc.total_rows = n;
qc.missing_count_original = sum(T.is_missing_original);
qc.threshold_flag_count = sum(T.is_threshold_flag);
qc.below_min_count = sum(T.is_below_min);
qc.above_max_count = sum(T.is_above_max);
qc.invalid_count_total = sum(T.is_invalid);
qc.interpolated_count = sum(interpolated_mask);
qc.final_valid_count = sum(valid_mask_final);
qc.final_nan_count = sum(~valid_mask_final);
qc.valid_fraction_final = mean(valid_mask_final);
qc.threshold_min = cfg.temp.min;
qc.threshold_max = cfg.temp.max;

% Warnings
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
        'Mass flagging warning: %.1f%% of temp values flagged/invalid.', ...
        100 * flag_fraction);
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned temp values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned temp output has near-zero variance.';
end

qc.warning_messages = strjoin(out.warnings, ' | ');
out.qc = qc;

end

%% ========================================================================
function file_info = local_get_file_info(record, expected_name)
% Return file_info struct for one expected file from discovery record.

file_info = [];

for i = 1:numel(record.files)
    if strcmp(record.files(i).expected_name, expected_name)
        file_info = record.files(i);
        return;
    end
end

error('clean_temp:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function s = local_nan_summary()
% NaN-filled summary template for unavailable temp data.

s = struct();
s.temp_mean = NaN;
s.temp_std = NaN;
s.temp_min = NaN;
s.temp_max = NaN;
s.temp_median = NaN;
s.temp_valid_fraction = NaN;
s.temp_n_valid = 0;
end

%% ------------------------------------------------------------------------
function qc = local_base_qc(cfg, record)
% Base QC struct template.

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
qc.final_valid_count = NaN;
qc.final_nan_count = NaN;
qc.valid_fraction_final = NaN;

qc.threshold_min = cfg.temp.min;
qc.threshold_max = cfg.temp.max;

qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_messages = '';
end