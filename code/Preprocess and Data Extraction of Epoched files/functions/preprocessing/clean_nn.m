function out = clean_nn(cfg, record)
%CLEAN_NN Clean event-based NN intervals and compute NN-derived HRV metrics.
%
% Uses nn_live.csv:
%   col 1 = sample_idx
%   col 2 = nn_ms
%
% Main rules:
%   - NN < cfg.nn.min_ms or NN > cfg.nn.max_ms -> invalid
%   - abrupt beat-to-beat jumps -> suspicious/artifact
%   - short gaps may be interpolated if cfg.nn.enable_short_gap_interpolation = true
%   - longer invalid sections remain NaN
%
% Output:
%   out.flagged_table
%   out.cleaned_table
%   out.summary
%   out.qc

%% Validate
if nargin < 2
    error('clean_nn:MissingInputs', 'Both cfg and record are required.');
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
out.meta.function_name = 'clean_nn';

%% Resolve source
nn_info = local_get_file_info(record, 'nn_live.csv');

out.source = nn_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'nn_live.csv');

%% Missing source handling
if ~nn_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical nn_live.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load event-based NN file
loaded = load_event_csv( ...
    nn_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 2, ...
    'SampleRateHz', cfg.nn.sample_rate_hz, ...
    'Col1Name', 'sample_idx', ...
    'Col2Name', 'nn_ms');

out.loaded.loader_output = loaded;

if isempty(loaded.table) || height(loaded.table) == 0
    out.warnings{end+1} = 'NN file loaded but contains zero rows.';

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = nn_info.preferred_source;
    out.qc.total_beats = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

T = loaded.table;
n = height(T);

%% Base columns
sample_idx = T.sample_idx;
nn_ms = double(T.nn_ms);
time_sec = T.time_sec;

F = table();
F.beat_idx = (1:n)';
F.sample_idx = sample_idx;
F.time_sec = time_sec;
F.nn_ms = nn_ms;

%% Basic flags
F.is_missing_original = isnan(F.nn_ms);

F.is_below_min = F.nn_ms < cfg.nn.min_ms;
F.is_above_max = F.nn_ms > cfg.nn.max_ms;
F.is_threshold_flag = F.is_below_min | F.is_above_max;

%% Beat-to-beat jump detection
F.nn_diff_from_previous_ms = [NaN; abs(diff(F.nn_ms))];

F.is_jump_artifact = false(n,1);

if isfield(cfg.nn, 'enable_jump_detection') && cfg.nn.enable_jump_detection
    abs_jump_mask = F.nn_diff_from_previous_ms > cfg.nn.jump_abs_diff_ms;

    rel_jump_mask = false(n,1);
    prev_nn = [NaN; F.nn_ms(1:end-1)];
    rel_change = abs(F.nn_ms - prev_nn) ./ prev_nn;
    rel_jump_mask = rel_change > cfg.nn.jump_relative_fraction;
    rel_jump_mask(isnan(rel_jump_mask)) = false;

    F.is_jump_artifact = abs_jump_mask | rel_jump_mask;

    % Do not classify first beat as jump artifact
    F.is_jump_artifact(1) = false;

    % If either current or previous value is already impossible/missing,
    % jump flag is less interpretable; keep threshold flag as primary.
    previous_invalid = [false; F.is_missing_original(1:end-1) | F.is_threshold_flag(1:end-1)];
    current_invalid = F.is_missing_original | F.is_threshold_flag;
    F.is_jump_artifact(previous_invalid | current_invalid) = false;
end

%% Combined invalid flag
F.is_invalid = F.is_missing_original | F.is_threshold_flag | F.is_jump_artifact;

out.flagged_table = F;

%% Clean NN series
cleaned_nn = F.nn_ms;
cleaned_nn(F.is_invalid) = NaN;

%% Short-gap interpolation
interpolated_mask = false(n,1);

if isfield(cfg.nn, 'enable_short_gap_interpolation') && cfg.nn.enable_short_gap_interpolation
    [cleaned_nn, interpolated_mask] = local_interpolate_short_gaps( ...
        cleaned_nn, cfg.nn.max_interp_gap_beats);
end

%% Cleaned table
C = F;
C.nn_cleaned_ms = cleaned_nn;
C.was_interpolated = interpolated_mask;

out.cleaned_table = C;

%% Segment summaries and HRV metrics
valid_mask = ~isnan(C.nn_cleaned_ms);
valid_nn = C.nn_cleaned_ms(valid_mask);

summary = local_nan_summary();

summary.nn_count_total = n;
summary.nn_count_valid = sum(valid_mask);
summary.nn_invalid_ratio = mean(F.is_invalid);
summary.nn_valid_fraction = mean(valid_mask);

if ~isempty(valid_nn)
    summary.nn_mean = mean(valid_nn, 'omitnan');
    summary.nn_median = median(valid_nn, 'omitnan');
    summary.nn_std = std(valid_nn, 'omitnan');
    summary.meanNN_nn = mean(valid_nn, 'omitnan');
    summary.meanHR_nn = 60000 ./ summary.meanNN_nn;
end

if numel(valid_nn) >= 2
    successive_diff = diff(valid_nn);

    summary.RMSSD_nn = sqrt(mean(successive_diff.^2, 'omitnan'));
    summary.SDNN_nn = std(valid_nn, 'omitnan');
    summary.pNN50_nn = mean(abs(successive_diff) > 50) * 100;
else
    summary.RMSSD_nn = NaN;
    summary.SDNN_nn = NaN;
    summary.pNN50_nn = NaN;
end

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = nn_info.preferred_source;

qc.total_beats = n;
qc.missing_count_original = sum(F.is_missing_original);
qc.threshold_flag_count = sum(F.is_threshold_flag);
qc.below_min_count = sum(F.is_below_min);
qc.above_max_count = sum(F.is_above_max);
qc.jump_artifact_count = sum(F.is_jump_artifact);
qc.invalid_count_total = sum(F.is_invalid);
qc.interpolated_count = sum(interpolated_mask);

qc.final_valid_count = sum(valid_mask);
qc.final_nan_count = sum(~valid_mask);
qc.valid_fraction_final = mean(valid_mask);
qc.rejected_ratio_before_interpolation = mean(F.is_invalid);

qc.threshold_min_ms = cfg.nn.min_ms;
qc.threshold_max_ms = cfg.nn.max_ms;
qc.jump_abs_diff_ms = cfg.nn.jump_abs_diff_ms;
qc.jump_relative_fraction = cfg.nn.jump_relative_fraction;
qc.max_interp_gap_beats = cfg.nn.max_interp_gap_beats;

qc.usable_suggestion = qc.rejected_ratio_before_interpolation <= cfg.nn.usable_max_invalid_ratio;

qc.warning_mass_flagging = ...
    qc.rejected_ratio_before_interpolation >= cfg.qc.mass_flagging_fraction_warning;

qc.warning_all_nan_output = all(~valid_mask);

if numel(valid_nn) <= 1
    qc.warning_zero_variance = false;
else
    qc.warning_zero_variance = std(valid_nn, 'omitnan') <= cfg.qc.zero_variance_tolerance;
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of NN beats invalid before interpolation.', ...
        100 * qc.rejected_ratio_before_interpolation);
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned NN values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned NN output has near-zero variance.';
end

if ~qc.usable_suggestion
    out.warnings{end+1} = sprintf( ...
        'NN segment usability warning: invalid ratio %.2f exceeds configured limit %.2f.', ...
        qc.rejected_ratio_before_interpolation, cfg.nn.usable_max_invalid_ratio);
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

error('clean_nn:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function [x_out, interpolated_mask] = local_interpolate_short_gaps(x, max_gap_len)
% Interpolate only internal NaN gaps with length <= max_gap_len.
% Long gaps remain NaN.

x_out = x;
interpolated_mask = false(size(x));

is_nan = isnan(x);

if ~any(is_nan)
    return;
end

n = numel(x);
d = diff([false; is_nan; false]);
gap_starts = find(d == 1);
gap_ends = find(d == -1) - 1;

for g = 1:numel(gap_starts)
    a = gap_starts(g);
    b = gap_ends(g);
    gap_len = b - a + 1;

    % Only internal gaps are interpolated
    has_left = a > 1 && ~isnan(x_out(a-1));
    has_right = b < n && ~isnan(x_out(b+1));

    if gap_len <= max_gap_len && has_left && has_right
        left_val = x_out(a-1);
        right_val = x_out(b+1);

        interp_vals = linspace(left_val, right_val, gap_len + 2);
        interp_vals = interp_vals(2:end-1);

        x_out(a:b) = interp_vals(:);
        interpolated_mask(a:b) = true;
    end
end

end

%% ------------------------------------------------------------------------
function s = local_nan_summary()

s = struct();

s.nn_count_total = 0;
s.nn_count_valid = 0;
s.nn_invalid_ratio = NaN;
s.nn_valid_fraction = NaN;

s.nn_mean = NaN;
s.nn_median = NaN;
s.nn_std = NaN;

s.meanNN_nn = NaN;
s.meanHR_nn = NaN;
s.RMSSD_nn = NaN;
s.SDNN_nn = NaN;
s.pNN50_nn = NaN;
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

qc.total_beats = NaN;
qc.missing_count_original = NaN;
qc.threshold_flag_count = NaN;
qc.below_min_count = NaN;
qc.above_max_count = NaN;
qc.jump_artifact_count = NaN;
qc.invalid_count_total = NaN;
qc.interpolated_count = NaN;

qc.final_valid_count = NaN;
qc.final_nan_count = NaN;
qc.valid_fraction_final = NaN;
qc.rejected_ratio_before_interpolation = NaN;

qc.threshold_min_ms = cfg.nn.min_ms;
qc.threshold_max_ms = cfg.nn.max_ms;
qc.jump_abs_diff_ms = cfg.nn.jump_abs_diff_ms;
qc.jump_relative_fraction = cfg.nn.jump_relative_fraction;
qc.max_interp_gap_beats = cfg.nn.max_interp_gap_beats;

qc.usable_suggestion = false;
qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_messages = '';
end