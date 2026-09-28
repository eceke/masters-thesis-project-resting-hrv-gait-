function out = clean_acc(cfg, record)
%CLEAN_ACC Preprocess 3-axis acceleration data.
%
% Uses acc.csv from preferred Physical source.
%
% Role:
%   Hip   = primary motion source
%   Heart = secondary / QC / comparison motion source
%
% Output:
%   out.flagged_table
%   out.cleaned_table
%   out.summary
%   out.qc

%% Validate
if nargin < 2
    error('clean_acc:MissingInputs', 'Both cfg and record are required.');
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
out.meta.function_name = 'clean_acc';

if strcmpi(record.sensor, 'Hip')
    out.meta.motion_role = 'primary_motion';
elseif strcmpi(record.sensor, 'Heart')
    out.meta.motion_role = 'secondary_motion_qc_comparison';
else
    out.meta.motion_role = 'unknown_motion_role';
end

%% Resolve source
acc_info = local_get_file_info(record, 'acc.csv');

out.source = acc_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'acc.csv');

%% Missing physical source handling
if ~acc_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical acc.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load physical ACC
loaded = load_simple_csv_column( ...
    acc_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', [], ...
    'VariableName', 'acc');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_acc:LoadFailed', ...
        'ACC file could not be parsed numerically: %s', acc_info.preferred_path);
end

acc_data = double(loaded.data);

if isempty(acc_data)
    out.warnings{end+1} = 'ACC file loaded but contains zero rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = acc_info.preferred_source;
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

n_rows = size(acc_data, 1);
n_cols = size(acc_data, 2);

if ~ismember(n_cols, cfg.acc.expect_num_axes)
    out.warnings{end+1} = sprintf( ...
        'Unexpected ACC column count: expected one of [%s], found %d.', ...
        num2str(cfg.acc.expect_num_axes), n_cols);
end

%% Build flagged table
F = table();
F.sample_idx = (1:n_rows)';

if n_cols >= 3
    ax = acc_data(:,1);
    ay = acc_data(:,2);
    az = acc_data(:,3);
elseif n_cols == 1
    ax = acc_data(:,1);
    ay = NaN(n_rows,1);
    az = NaN(n_rows,1);
    out.warnings{end+1} = 'ACC file has 1 column; treating as scalar acceleration.';
else
    error('clean_acc:TooFewColumns', ...
        'ACC file has no usable numeric columns.');
end

F.acc_x = ax;
F.acc_y = ay;
F.acc_z = az;

F.acc_magnitude = sqrt(F.acc_x.^2 + F.acc_y.^2 + F.acc_z.^2);

%% Flags
F.is_missing_x = isnan(F.acc_x);
F.is_missing_y = isnan(F.acc_y);
F.is_missing_z = isnan(F.acc_z);

if n_cols >= 3
    F.is_missing_any_axis = F.is_missing_x | F.is_missing_y | F.is_missing_z;
else
    F.is_missing_any_axis = F.is_missing_x;
end

F.is_below_min_x = F.acc_x < cfg.acc.min_plausible_g;
F.is_above_max_x = F.acc_x > cfg.acc.max_plausible_g;

F.is_below_min_y = F.acc_y < cfg.acc.min_plausible_g;
F.is_above_max_y = F.acc_y > cfg.acc.max_plausible_g;

F.is_below_min_z = F.acc_z < cfg.acc.min_plausible_g;
F.is_above_max_z = F.acc_z > cfg.acc.max_plausible_g;

if n_cols >= 3
    F.is_threshold_flag = ...
        F.is_below_min_x | F.is_above_max_x | ...
        F.is_below_min_y | F.is_above_max_y | ...
        F.is_below_min_z | F.is_above_max_z;
else
    F.is_threshold_flag = F.is_below_min_x | F.is_above_max_x;
end

F.is_invalid = F.is_missing_any_axis | F.is_threshold_flag;

out.flagged_table = F;

%% Cleaned data
C = F;

C.acc_x_cleaned = C.acc_x;
C.acc_y_cleaned = C.acc_y;
C.acc_z_cleaned = C.acc_z;

C.acc_x_cleaned(C.is_invalid) = NaN;
C.acc_y_cleaned(C.is_invalid) = NaN;
C.acc_z_cleaned(C.is_invalid) = NaN;

C.acc_magnitude_cleaned = sqrt( ...
    C.acc_x_cleaned.^2 + ...
    C.acc_y_cleaned.^2 + ...
    C.acc_z_cleaned.^2);

out.cleaned_table = C;

%% Valid data
valid_mask = ~isnan(C.acc_magnitude_cleaned);
valid_mag = C.acc_magnitude_cleaned(valid_mask);

%% Summary
summary = local_nan_summary();

summary.acc_n_samples = n_rows;
summary.acc_n_valid = sum(valid_mask);
summary.acc_valid_fraction = mean(valid_mask);
summary.acc_invalid_ratio = mean(C.is_invalid);

if ~isempty(valid_mag)
    summary.accmag_mean = mean(valid_mag, 'omitnan');
    summary.accmag_std = std(valid_mag, 'omitnan');
    summary.accmag_min = min(valid_mag, [], 'omitnan');
    summary.accmag_max = max(valid_mag, [], 'omitnan');
    summary.accmag_median = median(valid_mag, 'omitnan');

    % Simple activity proxy:
    % std of magnitude reflects variability/movement intensity.
    summary.acc_activity_proxy_stdmag = std(valid_mag, 'omitnan');

    % Dynamic component proxy:
    % subtract median magnitude to roughly remove static gravity component.
    dynamic_mag = abs(valid_mag - median(valid_mag, 'omitnan'));
    summary.acc_activity_proxy_mad_from_median = mean(dynamic_mag, 'omitnan');
end

% Axis-level summaries
summary.acc_x_mean = mean(C.acc_x_cleaned, 'omitnan');
summary.acc_y_mean = mean(C.acc_y_cleaned, 'omitnan');
summary.acc_z_mean = mean(C.acc_z_cleaned, 'omitnan');

summary.acc_x_std = std(C.acc_x_cleaned, 'omitnan');
summary.acc_y_std = std(C.acc_y_cleaned, 'omitnan');
summary.acc_z_std = std(C.acc_z_cleaned, 'omitnan');

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = acc_info.preferred_source;
qc.motion_role = out.meta.motion_role;

qc.total_rows = n_rows;
qc.num_columns = n_cols;

qc.missing_any_axis_count = sum(F.is_missing_any_axis);
qc.threshold_flag_count = sum(F.is_threshold_flag);
qc.invalid_count_total = sum(F.is_invalid);

qc.final_valid_count = sum(valid_mask);
qc.final_nan_count = sum(~valid_mask);
qc.valid_fraction_final = mean(valid_mask);

qc.threshold_min_g = cfg.acc.min_plausible_g;
qc.threshold_max_g = cfg.acc.max_plausible_g;

qc.warning_unexpected_column_count = ~ismember(n_cols, cfg.acc.expect_num_axes);
qc.warning_all_nan_output = all(~valid_mask);

if numel(valid_mag) <= 1
    qc.warning_zero_variance = false;
else
    qc.warning_zero_variance = std(valid_mag, 'omitnan') <= cfg.qc.zero_variance_tolerance;
end

qc.warning_mass_flagging = mean(F.is_invalid) >= cfg.qc.mass_flagging_fraction_warning;

% Flatline detection
qc.warning_flatline = false;
if ~isempty(valid_mag) && numel(valid_mag) > 1
    qc.warning_flatline = std(valid_mag, 'omitnan') <= cfg.acc.flatline_std_threshold;
end

if qc.warning_unexpected_column_count
    out.warnings{end+1} = sprintf( ...
        'Unexpected ACC column count: found %d.', n_cols);
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of ACC samples invalid.', ...
        100 * mean(F.is_invalid));
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned ACC magnitude values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned ACC magnitude has near-zero variance.';
end

if qc.warning_flatline
    out.warnings{end+1} = 'ACC magnitude appears flatline-like.';
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

error('clean_acc:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();

s.acc_n_samples = 0;
s.acc_n_valid = 0;
s.acc_valid_fraction = NaN;
s.acc_invalid_ratio = NaN;

s.accmag_mean = NaN;
s.accmag_std = NaN;
s.accmag_min = NaN;
s.accmag_max = NaN;
s.accmag_median = NaN;

s.acc_activity_proxy_stdmag = NaN;
s.acc_activity_proxy_mad_from_median = NaN;

s.acc_x_mean = NaN;
s.acc_y_mean = NaN;
s.acc_z_mean = NaN;

s.acc_x_std = NaN;
s.acc_y_std = NaN;
s.acc_z_std = NaN;
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
qc.motion_role = '';

qc.total_rows = NaN;
qc.num_columns = NaN;

qc.missing_any_axis_count = NaN;
qc.threshold_flag_count = NaN;
qc.invalid_count_total = NaN;

qc.final_valid_count = NaN;
qc.final_nan_count = NaN;
qc.valid_fraction_final = NaN;

qc.threshold_min_g = cfg.acc.min_plausible_g;
qc.threshold_max_g = cfg.acc.max_plausible_g;

qc.warning_unexpected_column_count = false;
qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_flatline = false;
qc.warning_messages = '';
end