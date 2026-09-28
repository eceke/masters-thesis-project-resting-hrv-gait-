function out = clean_movementacceleration(cfg, record)
%CLEAN_MOVEMENTACCELERATION Preprocess movementacceleration_live.csv.
%
% Uses movementacceleration_live.csv from preferred Physical source.
%
% Role:
%   Hip   = primary movement-intensity summary source
%   Heart = secondary / QC / comparison movement-intensity source
%
% This is a low-dimensional movement summary signal, so cleaning is minimal:
%   - load
%   - threshold/range check
%   - invalid -> NaN
%   - no interpolation by default
%   - no smoothing by default unless explicitly enabled in config

%% Validate
if nargin < 2
    error('clean_movementacceleration:MissingInputs', ...
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
out.meta.function_name = 'clean_movementacceleration';

if strcmpi(record.sensor, 'Hip')
    out.meta.motion_role = 'primary_movement_summary';
elseif strcmpi(record.sensor, 'Heart')
    out.meta.motion_role = 'secondary_movement_summary_qc_comparison';
else
    out.meta.motion_role = 'unknown_movement_summary_role';
end

%% Resolve source
mov_info = local_get_file_info(record, 'movementacceleration_live.csv');

out.source = mov_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'movementacceleration_live.csv');

%% Missing physical source handling
if ~mov_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical movementacceleration_live.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load physical movementacceleration
loaded = load_simple_csv_column( ...
    mov_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'movementacceleration_live');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_movementacceleration:LoadFailed', ...
        'movementacceleration_live.csv could not be parsed numerically: %s', ...
        mov_info.preferred_path);
end

mov_data = loaded.data;

if isempty(mov_data)
    out.warnings{end+1} = 'movementacceleration_live.csv loaded but contains zero rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = mov_info.preferred_source;
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

if size(mov_data,2) ~= 1
    out.warnings{end+1} = sprintf( ...
        'movementacceleration_live.csv expected 1 column but found %d. Using first column only.', ...
        size(mov_data,2));
    mov_data = mov_data(:,1);
end

mov = double(mov_data(:));
n = numel(mov);

%% Flagged table
F = table();
F.sample_idx = (1:n)';
F.movementacceleration = mov;

F.is_missing_original = isnan(F.movementacceleration);

F.is_below_min = F.movementacceleration < cfg.movementacceleration.min;
F.is_above_max = F.movementacceleration > cfg.movementacceleration.max;
F.is_threshold_flag = F.is_below_min | F.is_above_max;

F.is_invalid = F.is_missing_original | F.is_threshold_flag;

out.flagged_table = F;

%% Cleaned series
cleaned = F.movementacceleration;
cleaned(F.is_invalid) = NaN;

interpolated_mask = false(n,1);
smoothed_mask = false(n,1);

%% Optional interpolation
if isfield(cfg.flags, 'enable_interpolation') && cfg.flags.enable_interpolation
    original_nan_mask = isnan(cleaned);

    if any(original_nan_mask)
        cleaned_interp = fillmissing(cleaned, 'linear', 'EndValues', 'none');
        interpolated_mask = original_nan_mask & ~isnan(cleaned_interp);
        cleaned = cleaned_interp;
    end
end

%% Optional smoothing
if isfield(cfg.flags, 'enable_smoothing') && cfg.flags.enable_smoothing && ...
        isfield(cfg.movementacceleration, 'enable_smoothing') && ...
        cfg.movementacceleration.enable_smoothing

    if strcmpi(cfg.movementacceleration.smoothing_method, 'movmean')
        before = cleaned;
        cleaned = movmean(cleaned, cfg.movementacceleration.smoothing_window, 'omitnan');

        smoothed_mask = ~isnan(before) & ~isnan(cleaned) & ...
            (abs(cleaned - before) > eps(before));
    else
        out.warnings{end+1} = sprintf( ...
            'Unknown movementacceleration smoothing method "%s". No smoothing applied.', ...
            cfg.movementacceleration.smoothing_method);
    end
end

%% Cleaned table
C = F;
C.movementacceleration_cleaned = cleaned;
C.was_interpolated = interpolated_mask;
C.was_smoothed = smoothed_mask;

out.cleaned_table = C;

%% Summary
valid_mask = ~isnan(C.movementacceleration_cleaned);
valid_values = C.movementacceleration_cleaned(valid_mask);

summary = local_nan_summary();

summary.movementacceleration_n_samples = n;
summary.movementacceleration_n_valid = sum(valid_mask);
summary.movementacceleration_valid_fraction = mean(valid_mask);
summary.movementacceleration_invalid_ratio = mean(F.is_invalid);

if ~isempty(valid_values)
    summary.movementacceleration_mean = mean(valid_values, 'omitnan');
    summary.movementacceleration_std = std(valid_values, 'omitnan');
    summary.movementacceleration_min = min(valid_values, [], 'omitnan');
    summary.movementacceleration_max = max(valid_values, [], 'omitnan');
    summary.movementacceleration_median = median(valid_values, 'omitnan');
    summary.movementacceleration_range = ...
        summary.movementacceleration_max - summary.movementacceleration_min;

    summary.movementacceleration_activity_proxy_std = std(valid_values, 'omitnan');
    summary.movementacceleration_activity_proxy_mad = ...
        mean(abs(valid_values - median(valid_values, 'omitnan')), 'omitnan');
end

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = mov_info.preferred_source;
qc.motion_role = out.meta.motion_role;

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

qc.threshold_min = cfg.movementacceleration.min;
qc.threshold_max = cfg.movementacceleration.max;

qc.warning_mass_flagging = mean(F.is_invalid) >= cfg.qc.mass_flagging_fraction_warning;
qc.warning_all_nan_output = all(~valid_mask);

if numel(valid_values) <= 1
    qc.warning_zero_variance = false;
else
    qc.warning_zero_variance = ...
        std(valid_values, 'omitnan') <= cfg.qc.zero_variance_tolerance;
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of movementacceleration rows invalid.', ...
        100 * mean(F.is_invalid));
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned movementacceleration values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = ...
        'Cleaned movementacceleration output has near-zero variance.';
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

error('clean_movementacceleration:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();

s.movementacceleration_n_samples = 0;
s.movementacceleration_n_valid = 0;
s.movementacceleration_valid_fraction = NaN;
s.movementacceleration_invalid_ratio = NaN;

s.movementacceleration_mean = NaN;
s.movementacceleration_std = NaN;
s.movementacceleration_min = NaN;
s.movementacceleration_max = NaN;
s.movementacceleration_median = NaN;
s.movementacceleration_range = NaN;

s.movementacceleration_activity_proxy_std = NaN;
s.movementacceleration_activity_proxy_mad = NaN;
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

qc.threshold_min = cfg.movementacceleration.min;
qc.threshold_max = cfg.movementacceleration.max;

qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_messages = '';
end