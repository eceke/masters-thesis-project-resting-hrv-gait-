function out = clean_bpmbxb(cfg, record)
%CLEAN_BPMBXB Clean event-based beat-to-beat HR series.
%
% Uses bpmbxb_live.csv:
%   col 1 = sample_idx
%   col 2 = bpmbxb bpm
%
% Role:
%   - secondary beat-level HR source
%   - QC / sanity-check against NN-derived HR
%   - not automatically primary predictor

%% Validate
if nargin < 2
    error('clean_bpmbxb:MissingInputs', 'Both cfg and record are required.');
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
out.meta.function_name = 'clean_bpmbxb';

%% Resolve source
bpm_info = local_get_file_info(record, 'bpmbxb_live.csv');

out.source = bpm_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'bpmbxb_live.csv');

%% Missing source
if ~bpm_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical bpmbxb_live.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% Load event-based file
loaded = load_event_csv( ...
    bpm_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 2, ...
    'SampleRateHz', cfg.nn.sample_rate_hz, ...
    'Col1Name', 'sample_idx', ...
    'Col2Name', 'bpmbxb_bpm');

out.loaded.loader_output = loaded;

if isempty(loaded.table) || height(loaded.table) == 0
    out.warnings{end+1} = 'BPMBXB file loaded but contains zero rows.';

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = bpm_info.preferred_source;
    out.qc.total_beats = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

T = loaded.table;
n = height(T);

sample_idx = T.sample_idx;
bpm = double(T.bpmbxb_bpm);
time_sec = T.time_sec;

%% Flagged table
F = table();
F.beat_idx = (1:n)';
F.sample_idx = sample_idx;
F.time_sec = time_sec;
F.bpmbxb_bpm = bpm;

F.is_missing_original = isnan(F.bpmbxb_bpm);

F.is_below_min = F.bpmbxb_bpm < cfg.bpmbxb.min;
F.is_above_max = F.bpmbxb_bpm > cfg.bpmbxb.max;
F.is_threshold_flag = F.is_below_min | F.is_above_max;

%% Jump detection
F.bpm_diff_from_previous = [NaN; abs(diff(F.bpmbxb_bpm))];
F.is_jump_artifact = false(n,1);

if isfield(cfg.bpmbxb, 'enable_jump_detection') && cfg.bpmbxb.enable_jump_detection
    abs_jump_mask = F.bpm_diff_from_previous > cfg.bpmbxb.jump_abs_diff_bpm;

    prev_bpm = [NaN; F.bpmbxb_bpm(1:end-1)];
    rel_change = abs(F.bpmbxb_bpm - prev_bpm) ./ prev_bpm;
    rel_jump_mask = rel_change > cfg.bpmbxb.jump_relative_fraction;
    rel_jump_mask(isnan(rel_jump_mask)) = false;

    F.is_jump_artifact = abs_jump_mask | rel_jump_mask;
    F.is_jump_artifact(1) = false;

    previous_invalid = [false; F.is_missing_original(1:end-1) | F.is_threshold_flag(1:end-1)];
    current_invalid = F.is_missing_original | F.is_threshold_flag;
    F.is_jump_artifact(previous_invalid | current_invalid) = false;
end

F.is_invalid = F.is_missing_original | F.is_threshold_flag | F.is_jump_artifact;

out.flagged_table = F;

%% Cleaned series
cleaned_bpm = F.bpmbxb_bpm;
cleaned_bpm(F.is_invalid) = NaN;

interpolated_mask = false(n,1);

if isfield(cfg.bpmbxb, 'enable_short_gap_interpolation') && cfg.bpmbxb.enable_short_gap_interpolation
    [cleaned_bpm, interpolated_mask] = local_interpolate_short_gaps( ...
        cleaned_bpm, cfg.bpmbxb.max_interp_gap_beats);
end

C = F;
C.bpmbxb_cleaned_bpm = cleaned_bpm;
C.was_interpolated = interpolated_mask;

out.cleaned_table = C;

%% Summary
valid_mask = ~isnan(C.bpmbxb_cleaned_bpm);
valid_bpm = C.bpmbxb_cleaned_bpm(valid_mask);

summary = local_nan_summary();
summary.bpmbxb_count_total = n;
summary.bpmbxb_count_valid = sum(valid_mask);
summary.bpmbxb_invalid_ratio = mean(F.is_invalid);
summary.bpmbxb_valid_fraction = mean(valid_mask);

if ~isempty(valid_bpm)
    summary.bpmbxb_mean = mean(valid_bpm, 'omitnan');
    summary.bpmbxb_median = median(valid_bpm, 'omitnan');
    summary.bpmbxb_std = std(valid_bpm, 'omitnan');
    summary.bpmbxb_min = min(valid_bpm, [], 'omitnan');
    summary.bpmbxb_max = max(valid_bpm, [], 'omitnan');
end

out.summary = summary;

%% QC
qc = local_base_qc(cfg, record);
qc.source_available = true;
qc.source_used = bpm_info.preferred_source;

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

qc.threshold_min_bpm = cfg.bpmbxb.min;
qc.threshold_max_bpm = cfg.bpmbxb.max;
qc.jump_abs_diff_bpm = cfg.bpmbxb.jump_abs_diff_bpm;
qc.jump_relative_fraction = cfg.bpmbxb.jump_relative_fraction;
qc.max_interp_gap_beats = cfg.bpmbxb.max_interp_gap_beats;

qc.warning_mass_flagging = ...
    qc.rejected_ratio_before_interpolation >= cfg.qc.mass_flagging_fraction_warning;

qc.warning_all_nan_output = all(~valid_mask);

if numel(valid_bpm) <= 1
    qc.warning_zero_variance = false;
else
    qc.warning_zero_variance = std(valid_bpm, 'omitnan') <= cfg.qc.zero_variance_tolerance;
end

if qc.warning_mass_flagging
    out.warnings{end+1} = sprintf( ...
        'Mass flagging warning: %.1f%% of BPMBXB beats invalid before interpolation.', ...
        100 * qc.rejected_ratio_before_interpolation);
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'All cleaned BPMBXB values are NaN.';
end

if qc.warning_zero_variance
    out.warnings{end+1} = 'Cleaned BPMBXB output has near-zero variance.';
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

error('clean_bpmbxb:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);
end

%% ------------------------------------------------------------------------
function [x_out, interpolated_mask] = local_interpolate_short_gaps(x, max_gap_len)

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

s.bpmbxb_count_total = 0;
s.bpmbxb_count_valid = 0;
s.bpmbxb_invalid_ratio = NaN;
s.bpmbxb_valid_fraction = NaN;

s.bpmbxb_mean = NaN;
s.bpmbxb_median = NaN;
s.bpmbxb_std = NaN;
s.bpmbxb_min = NaN;
s.bpmbxb_max = NaN;
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

qc.threshold_min_bpm = cfg.bpmbxb.min;
qc.threshold_max_bpm = cfg.bpmbxb.max;
qc.jump_abs_diff_bpm = cfg.bpmbxb.jump_abs_diff_bpm;
qc.jump_relative_fraction = cfg.bpmbxb.jump_relative_fraction;
qc.max_interp_gap_beats = cfg.bpmbxb.max_interp_gap_beats;

qc.warning_mass_flagging = false;
qc.warning_all_nan_output = false;
qc.warning_zero_variance = false;
qc.warning_messages = '';
end