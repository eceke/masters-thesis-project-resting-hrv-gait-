function out = clean_stepcount(cfg, record)
%CLEAN_STEPCOUNT Preprocess stepcount_live.csv.
%
% Stepcount is low-resolution and may not behave as a simple cumulative
% signal in every segment/sensor.
%
% Main outputs:
%   - first value
%   - last value
%   - last-minus-first change
%   - total positive increment
%   - negative increment warning
%   - rest/walk context QC flags

%% Validate
if nargin < 2
    error('clean_stepcount:MissingInputs', ...
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
out.meta.function_name = 'clean_stepcount';

if strcmpi(record.sensor, 'Hip')
    out.meta.motion_role = 'primary_step_context';
elseif strcmpi(record.sensor, 'Heart')
    out.meta.motion_role = 'secondary_step_context_qc_comparison';
else
    out.meta.motion_role = 'unknown_step_context_role';
end

%% Resolve source
step_info = local_get_file_info(record, 'stepcount_live.csv');

out.source = step_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'stepcount_live.csv');

%% Missing physical source handling
if ~step_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical stepcount_live.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load physical stepcount
loaded = load_simple_csv_column( ...
    step_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'stepcount_live');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_stepcount:LoadFailed', ...
        'stepcount_live.csv could not be parsed numerically: %s', ...
        step_info.preferred_path);
end

step_data = loaded.data;

if isempty(step_data)
    out.warnings{end+1} = 'stepcount_live.csv loaded but contains zero rows.';
    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = step_info.preferred_source;
    out.qc.total_rows = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

if size(step_data,2) ~= 1
    out.warnings{end+1} = sprintf( ...
        'stepcount_live.csv expected 1 column but found %d. Using first column only.', ...
        size(step_data,2));
    step_data = step_data(:,1);
end

steps = double(step_data(:));
n = numel(steps);

%% Flagged table
F = table();
F.sample_idx = (1:n)';
F.stepcount = steps;

F.is_missing_original = isnan(F.stepcount);

F.is_below_min = F.stepcount < cfg.stepcount.min;
F.is_above_max = F.stepcount > cfg.stepcount.max;
F.is_threshold_flag = F.is_below_min | F.is_above_max;

% Stepcount may decrease if the device resets or if this is not a strictly
% cumulative series. We flag this but do not invalidate it by default.
F.step_diff_from_previous = [NaN; diff(F.stepcount)];
F.is_negative_step_diff = F.step_diff_from_previous < 0;

if isfield(cfg.stepcount, 'treat_negative_diff_as_invalid') && ...
        cfg.stepcount.treat_negative_diff_as_invalid
    F.is_invalid = F.is_missing_original | F.is_threshold_flag | F.is_negative_step_diff;
else
    F.is_invalid = F.is_missing_original | F.is_threshold_flag;
end

out.flagged_table = F;

%% Cleaned series
cleaned = F.stepcount;
cleaned(F.is_invalid) = NaN;

C = F;
C.stepcount_cleaned = cleaned;

out.cleaned_table = C;

%% Summary
valid_mask = ~isnan(C.stepcount_cleaned);
valid_steps = C.stepcount_cleaned(valid_mask);

summary = local_nan_summary();

summary.stepcount_n_samples = n;
summary.stepcount_n_valid = sum(valid_mask);
summary.stepcount_valid_fraction = mean(valid_mask);
summary.stepcount_invalid_ratio = mean(F.is_invalid);
summary.stepcount_expected_activity = record.segment_type;

if ~isempty(valid_steps)
    summary.stepcount_first = valid_steps(1);
    summary.stepcount_last = valid_steps(end);
    summary.stepcount_min = min(valid_steps, [], 'omitnan');
    summary.stepcount_max = max(valid_steps, [], 'omitnan');

    diffs = diff(valid_steps);
    positive_diffs = diffs;
    positive_diffs(positive_diffs < 0) = 0;

    summary.stepcount_total_increase_last_minus_first = ...
        summary.stepcount_last - summary.stepcount_first;

    summary.stepcount_total_positive_increment = sum(positive_diffs, 'omitnan');

    summary.stepcount_num_positive_increments = sum(positive_diffs > 0);
    summary.stepcount_num_negative_increments = sum(diffs < 0);

    summary.stepcount_mean_value = mean(valid_steps, 'omitnan');
    summary.stepcount_median_value = median(valid_steps, 'omitnan');

    if strcmpi(record.segment_type, 'rest')
        summary.stepcount_unexpected_steps_in_rest = ...
            summary.stepcount_total_positive_increment > 0;
    elseif strcmpi(record.segment_type, 'walk')
        summary.stepcount_suspiciously_low_steps_in_walk = ...
            summary.stepcount_total_positive_increment == 0;
    end
end

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = step_info.preferred_source;
qc.motion_role = out.meta.motion_role;

qc.total_rows = n;
qc.missing_count_original = sum(F.is_missing_original);
qc.threshold_flag_count = sum(F.is_threshold_flag);
qc.below_min_count = sum(F.is_below_min);
qc.above_max_count = sum(F.is_above_max);
qc.negative_step_diff_count = sum(F.is_negative_step_diff, 'omitnan');
qc.invalid_count_total = sum(F.is_invalid);

qc.final_valid_count = sum(valid_mask);
qc.final_nan_count = sum(~valid_mask);
qc.valid_fraction_final = mean(valid_mask);

qc.threshold_min = cfg.stepcount.min;
qc.threshold_max = cfg.stepcount.max;

qc.warning_mass_flagging = mean(F.is_invalid) >= cfg.qc.mass_flagging_fraction_warning;
qc.warning_all_nan_output = all(~valid_mask);
qc.warning_negative_step_diff = qc.negative_step_diff_count > 0;

qc.warning_unexpected_steps_in_rest = false;
qc.warning_suspiciously_low_steps_in_walk = false;

if ~isempty(valid_steps)
    if strcmpi(record.segment_type, 'rest') && cfg.stepcount.warn_if_rest_has_steps
        qc.warning_unexpected_steps_in_rest = ...
            summary.stepcount_total_positive_increment > 0;
    elseif strcmpi(record.segment_type, 'walk') && cfg.stepcount.warn_if_walk_has_zero_steps
        qc.warning_suspiciously_low_steps_in_walk = ...
            summary.stepcount_total_positive_increment == 0;
    end
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of stepcount rows invalid.', ...
        100 * mean(F.is_invalid));
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned stepcount values are NaN.';
end

if qc.warning_negative_step_diff
    out.warnings{end+1} = ...
        'Stepcount contains negative increments; check whether stepcount resets or is non-cumulative.';
end

if qc.warning_unexpected_steps_in_rest
    out.warnings{end+1} = ...
        'Unexpected step increase detected during rest segment.';
end

if qc.warning_suspiciously_low_steps_in_walk
    out.warnings{end+1} = ...
        'Suspiciously low step increase detected during walking segment.';
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

error('clean_stepcount:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();

s.stepcount_n_samples = 0;
s.stepcount_n_valid = 0;
s.stepcount_valid_fraction = NaN;
s.stepcount_invalid_ratio = NaN;

s.stepcount_first = NaN;
s.stepcount_last = NaN;
s.stepcount_min = NaN;
s.stepcount_max = NaN;

s.stepcount_total_increase_last_minus_first = NaN;
s.stepcount_total_positive_increment = NaN;

s.stepcount_num_positive_increments = NaN;
s.stepcount_num_negative_increments = NaN;

s.stepcount_mean_value = NaN;
s.stepcount_median_value = NaN;

s.stepcount_expected_activity = '';
s.stepcount_unexpected_steps_in_rest = false;
s.stepcount_suspiciously_low_steps_in_walk = false;
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
qc.negative_step_diff_count = NaN;
qc.invalid_count_total = NaN;

qc.final_valid_count = NaN;
qc.final_nan_count = NaN;
qc.valid_fraction_final = NaN;

qc.threshold_min = cfg.stepcount.min;
qc.threshold_max = cfg.stepcount.max;

qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_negative_step_diff = false;
qc.warning_unexpected_steps_in_rest = false;
qc.warning_suspiciously_low_steps_in_walk = false;
qc.warning_messages = '';
end