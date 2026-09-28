function out = clean_angularrate(cfg, record)
%CLEAN_ANGULARRATE Preprocess 3-axis angular velocity data.
%
% Uses angularrate.csv from preferred Physical source.
%
% Role:
%   Hip   = primary rotational motion source
%   Heart = secondary / QC / comparison rotational motion source

%% Validate
if nargin < 2
    error('clean_angularrate:MissingInputs', 'Both cfg and record are required.');
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
out.meta.function_name = 'clean_angularrate';

if strcmpi(record.sensor, 'Hip')
    out.meta.motion_role = 'primary_rotational_motion';
elseif strcmpi(record.sensor, 'Heart')
    out.meta.motion_role = 'secondary_rotational_motion_qc_comparison';
else
    out.meta.motion_role = 'unknown_rotational_motion_role';
end

%% Resolve source
gyro_info = local_get_file_info(record, 'angularrate.csv');

out.source = gyro_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'angularrate.csv');

%% Missing physical source handling
if ~gyro_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical angularrate.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load physical angularrate
loaded = load_simple_csv_column( ...
    gyro_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', [], ...
    'VariableName', 'angularrate');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_angularrate:LoadFailed', ...
        'Angularrate file could not be parsed numerically: %s', gyro_info.preferred_path);
end

gyro_data = double(loaded.data);

if isempty(gyro_data)
    out.warnings{end+1} = 'Angularrate file loaded but contains zero rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = gyro_info.preferred_source;
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

n_rows = size(gyro_data, 1);
n_cols = size(gyro_data, 2);

if ~ismember(n_cols, cfg.angularrate.expect_num_axes)
    out.warnings{end+1} = sprintf( ...
        'Unexpected angularrate column count: expected one of [%s], found %d.', ...
        num2str(cfg.angularrate.expect_num_axes), n_cols);
end

%% Build flagged table
F = table();
F.sample_idx = (1:n_rows)';

if n_cols >= 3
    gx = gyro_data(:,1);
    gy = gyro_data(:,2);
    gz = gyro_data(:,3);
elseif n_cols == 1
    gx = gyro_data(:,1);
    gy = NaN(n_rows,1);
    gz = NaN(n_rows,1);
    out.warnings{end+1} = 'Angularrate file has 1 column; treating as scalar rotational signal.';
else
    error('clean_angularrate:TooFewColumns', ...
        'Angularrate file has no usable numeric columns.');
end

F.gyro_x = gx;
F.gyro_y = gy;
F.gyro_z = gz;

F.gyro_magnitude = sqrt(F.gyro_x.^2 + F.gyro_y.^2 + F.gyro_z.^2);

%% Flags
F.is_missing_x = isnan(F.gyro_x);
F.is_missing_y = isnan(F.gyro_y);
F.is_missing_z = isnan(F.gyro_z);

if n_cols >= 3
    F.is_missing_any_axis = F.is_missing_x | F.is_missing_y | F.is_missing_z;
else
    F.is_missing_any_axis = F.is_missing_x;
end

F.is_below_min_x = F.gyro_x < cfg.angularrate.min_plausible_dps;
F.is_above_max_x = F.gyro_x > cfg.angularrate.max_plausible_dps;

F.is_below_min_y = F.gyro_y < cfg.angularrate.min_plausible_dps;
F.is_above_max_y = F.gyro_y > cfg.angularrate.max_plausible_dps;

F.is_below_min_z = F.gyro_z < cfg.angularrate.min_plausible_dps;
F.is_above_max_z = F.gyro_z > cfg.angularrate.max_plausible_dps;

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

C.gyro_x_cleaned = C.gyro_x;
C.gyro_y_cleaned = C.gyro_y;
C.gyro_z_cleaned = C.gyro_z;

C.gyro_x_cleaned(C.is_invalid) = NaN;
C.gyro_y_cleaned(C.is_invalid) = NaN;
C.gyro_z_cleaned(C.is_invalid) = NaN;

C.gyro_magnitude_cleaned = sqrt( ...
    C.gyro_x_cleaned.^2 + ...
    C.gyro_y_cleaned.^2 + ...
    C.gyro_z_cleaned.^2);

out.cleaned_table = C;

%% Valid data
valid_mask = ~isnan(C.gyro_magnitude_cleaned);
valid_mag = C.gyro_magnitude_cleaned(valid_mask);

%% Summary
summary = local_nan_summary();

summary.gyro_n_samples = n_rows;
summary.gyro_n_valid = sum(valid_mask);
summary.gyro_valid_fraction = mean(valid_mask);
summary.gyro_invalid_ratio = mean(C.is_invalid);

if ~isempty(valid_mag)
    summary.gyromag_mean = mean(valid_mag, 'omitnan');
    summary.gyromag_std = std(valid_mag, 'omitnan');
    summary.gyromag_min = min(valid_mag, [], 'omitnan');
    summary.gyromag_max = max(valid_mag, [], 'omitnan');
    summary.gyromag_median = median(valid_mag, 'omitnan');

    % Rotational activity proxies
    summary.gyro_activity_proxy_stdmag = std(valid_mag, 'omitnan');

    dynamic_mag = abs(valid_mag - median(valid_mag, 'omitnan'));
    summary.gyro_activity_proxy_mad_from_median = mean(dynamic_mag, 'omitnan');
end

summary.gyro_x_mean = mean(C.gyro_x_cleaned, 'omitnan');
summary.gyro_y_mean = mean(C.gyro_y_cleaned, 'omitnan');
summary.gyro_z_mean = mean(C.gyro_z_cleaned, 'omitnan');

summary.gyro_x_std = std(C.gyro_x_cleaned, 'omitnan');
summary.gyro_y_std = std(C.gyro_y_cleaned, 'omitnan');
summary.gyro_z_std = std(C.gyro_z_cleaned, 'omitnan');

summary.gyro_x_min = min(C.gyro_x_cleaned, [], 'omitnan');
summary.gyro_y_min = min(C.gyro_y_cleaned, [], 'omitnan');
summary.gyro_z_min = min(C.gyro_z_cleaned, [], 'omitnan');

summary.gyro_x_max = max(C.gyro_x_cleaned, [], 'omitnan');
summary.gyro_y_max = max(C.gyro_y_cleaned, [], 'omitnan');
summary.gyro_z_max = max(C.gyro_z_cleaned, [], 'omitnan');

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = gyro_info.preferred_source;
qc.motion_role = out.meta.motion_role;

qc.total_rows = n_rows;
qc.num_columns = n_cols;

qc.missing_any_axis_count = sum(F.is_missing_any_axis);
qc.threshold_flag_count = sum(F.is_threshold_flag);
qc.invalid_count_total = sum(F.is_invalid);

qc.final_valid_count = sum(valid_mask);
qc.final_nan_count = sum(~valid_mask);
qc.valid_fraction_final = mean(valid_mask);

qc.threshold_min_dps = cfg.angularrate.min_plausible_dps;
qc.threshold_max_dps = cfg.angularrate.max_plausible_dps;

qc.warning_unexpected_column_count = ~ismember(n_cols, cfg.angularrate.expect_num_axes);
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
    qc.warning_flatline = std(valid_mag, 'omitnan') <= cfg.angularrate.flatline_std_threshold;
end

if qc.warning_unexpected_column_count
    out.warnings{end+1} = sprintf( ...
        'Unexpected angularrate column count: found %d.', n_cols);
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of angularrate samples invalid.', ...
        100 * mean(F.is_invalid));
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned angularrate magnitude values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned angularrate magnitude has near-zero variance.';
end

if qc.warning_flatline
    out.warnings{end+1} = 'Angularrate magnitude appears flatline-like.';
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

error('clean_angularrate:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();

s.gyro_n_samples = 0;
s.gyro_n_valid = 0;
s.gyro_valid_fraction = NaN;
s.gyro_invalid_ratio = NaN;

s.gyromag_mean = NaN;
s.gyromag_std = NaN;
s.gyromag_min = NaN;
s.gyromag_max = NaN;
s.gyromag_median = NaN;

s.gyro_activity_proxy_stdmag = NaN;
s.gyro_activity_proxy_mad_from_median = NaN;

s.gyro_x_mean = NaN;
s.gyro_y_mean = NaN;
s.gyro_z_mean = NaN;

s.gyro_x_std = NaN;
s.gyro_y_std = NaN;
s.gyro_z_std = NaN;

s.gyro_x_min = NaN;
s.gyro_y_min = NaN;
s.gyro_z_min = NaN;

s.gyro_x_max = NaN;
s.gyro_y_max = NaN;
s.gyro_z_max = NaN;
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

qc.threshold_min_dps = cfg.angularrate.min_plausible_dps;
qc.threshold_max_dps = cfg.angularrate.max_plausible_dps;

qc.warning_unexpected_column_count = false;
qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_flatline = false;
qc.warning_messages = '';
end