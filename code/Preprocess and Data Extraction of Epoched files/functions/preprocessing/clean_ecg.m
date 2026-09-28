function out = clean_ecg(cfg, record)
%CLEAN_ECG Preprocess ECG, detect R-peaks, clean RR intervals, compute HRV.
%
% This function computes ECG-derived time-domain HRV and frequency-domain HRV.
% Frequency-domain HRV uses the already cleaned RR series.
%
% Main methodological choices:
%   - Physical ECG source is used.
%   - sample rate is read from unisens.xml where possible.
%   - bandpass filtering uses filtfilt, so phase shift is avoided.
%   - R-peak detection tests multiple candidate thresholds and polarities.
%   - RR cleaning uses ECG-specific cfg.ecg.rr thresholds, not cfg.nn.
%   - HRV differences are computed only between adjacent RR entries.

%% ------------------------------------------------------------------------
% Validate
if nargin < 2
    error('clean_ecg:MissingInputs', ...
        'Both cfg and record are required.');
end

%% ------------------------------------------------------------------------
% Init
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
out.meta.function_name = 'clean_ecg';
out.meta.role = 'ecg_time_and_frequency_domain_hrv';

%% ------------------------------------------------------------------------
% Resolve ECG source
ecg_info = local_get_file_info(record, 'ecg.csv');

out.source = ecg_info;
out.source.requirement_level = get_file_requirement_level(cfg, record.sensor, 'ecg.csv');

if ~ecg_info.physical_exists
    out.warnings{end+1} = sprintf( ...
        'Physical ecg.csv missing for %s | %s | %s. Returning NaN summaries.', ...
        record.participant_id, record.sensor, record.segment_name);

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = false;
    out.qc.source_used = 'missing';
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

%% ------------------------------------------------------------------------
% Sample rate
[fs, fs_source, fs_warning] = local_get_ecg_sample_rate(cfg, record);

out.meta.sample_rate_hz = fs;
out.meta.sample_rate_source = fs_source;

if ~isempty(fs_warning)
    out.warnings{end+1} = fs_warning;
end

%% ------------------------------------------------------------------------
% Load physical ECG
loaded = load_simple_csv_column( ...
    ecg_info.preferred_path, ...
    'Delimiter', ';', ...
    'ExpectedCols', 1, ...
    'VariableName', 'ecg');

out.loaded.loader_output = loaded;

if ~loaded.numeric_parse_success
    error('clean_ecg:LoadFailed', ...
        'ecg.csv could not be parsed numerically: %s', ...
        ecg_info.preferred_path);
end

ecg_data = loaded.data;

if isempty(ecg_data)
    out.warnings{end+1} = 'ecg.csv loaded but contains zero rows.';

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = ecg_info.preferred_source;
    out.qc.sample_rate_hz = fs;
    out.qc.total_samples = 0;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

if size(ecg_data, 2) ~= 1
    out.warnings{end+1} = sprintf( ...
        'ecg.csv expected 1 column but found %d. Using first column only.', ...
        size(ecg_data, 2));
    ecg_data = ecg_data(:, 1);
end

ecg_raw = double(ecg_data(:));
n = numel(ecg_raw);
time_sec = (0:n-1)' ./ fs;
duration_sec = n / fs;

%% ------------------------------------------------------------------------
% Raw ECG QC
is_missing = isnan(ecg_raw);
valid_raw = ecg_raw(~is_missing);

if isempty(valid_raw)
    out.warnings{end+1} = 'All raw ECG values are NaN.';

    out.summary = local_nan_summary();
    out.qc = local_base_qc(cfg, record);
    out.qc.source_available = true;
    out.qc.source_used = ecg_info.preferred_source;
    out.qc.sample_rate_hz = fs;
    out.qc.total_samples = n;
    out.qc.warning_all_nan_output = true;
    out.qc.warning_messages = strjoin(out.warnings, ' | ');
    return;
end

raw_min = min(valid_raw, [], 'omitnan');
raw_max = max(valid_raw, [], 'omitnan');
raw_range = raw_max - raw_min;
raw_std = std(valid_raw, 'omitnan');

%% ------------------------------------------------------------------------
% Prepare signal for filtering
ecg_for_filter = ecg_raw;

if any(is_missing)
    ecg_for_filter = fillmissing(ecg_for_filter, 'linear', 'EndValues', 'nearest');
end

% Median centering removes DC offset before bandpass filtering.
ecg_centered = ecg_for_filter - median(ecg_for_filter, 'omitnan');

%% ------------------------------------------------------------------------
% Filter
[ecg_filtered, filter_info, filter_warning] = local_filter_ecg(ecg_centered, fs, cfg);

if ~isempty(filter_warning)
    out.warnings{end+1} = filter_warning;
end

%% ------------------------------------------------------------------------
% R-peak detection
[r_locs, r_pks, r_polarity, peak_diag] = local_detect_r_peaks(ecg_filtered, fs, cfg);

%% ------------------------------------------------------------------------
% Sample-level ECG table
S = table();
S.sample_idx = (1:n)';
S.time_sec = time_sec;
S.ecg_raw = ecg_raw;
S.ecg_filtered = ecg_filtered;
S.is_missing_original = is_missing;
S.is_r_peak = false(n,1);

if ~isempty(r_locs)
    valid_locs = r_locs(r_locs >= 1 & r_locs <= n);
    S.is_r_peak(valid_locs) = true;
end

out.flagged_table = S;

%% ------------------------------------------------------------------------
% RR extraction
R = local_build_rr_table(r_locs, fs, cfg);

%% Clean RR intervals
if height(R) > 0
    rr_cleaned_original = R.rr_ms;
    rr_cleaned_original(R.is_invalid) = NaN;

    max_gap = cfg.ecg.rr.max_interp_gap_beats;

    if max_gap > 0
        [rr_cleaned, interpolated_mask] = local_interpolate_short_gaps_no_propagation( ...
            rr_cleaned_original, max_gap);
    else
        rr_cleaned = rr_cleaned_original;
        interpolated_mask = false(height(R), 1);
    end

    R.rr_cleaned_ms = rr_cleaned;
    R.was_interpolated = interpolated_mask;
else
    R.rr_cleaned_ms = zeros(0,1);
    R.was_interpolated = false(0,1);
end

out.cleaned_table = R;

%% ------------------------------------------------------------------------
% HRV summary
summary = local_nan_summary();

summary.ecg_total_samples = n;
summary.ecg_duration_sec = duration_sec;
summary.ecg_sample_rate_hz = fs;

summary.ecg_raw_min = raw_min;
summary.ecg_raw_max = raw_max;
summary.ecg_raw_range = raw_range;
summary.ecg_raw_std = raw_std;

summary.ecg_filter_low_cutoff_hz = filter_info.low_cutoff_hz;
summary.ecg_filter_high_cutoff_hz = filter_info.high_cutoff_hz;

summary.ecg_rpeak_count = numel(r_locs);
summary.ecg_rr_count_total = height(R);
summary.ecg_rpeak_polarity = string(r_polarity);
if ~isempty(r_pks)
    summary.ecg_rpeak_abs_amp_mean = mean(abs(r_pks), 'omitnan');
    summary.ecg_rpeak_abs_amp_std = std(abs(r_pks), 'omitnan');
    summary.ecg_rpeak_abs_amp_median = median(abs(r_pks), 'omitnan');
else
    summary.ecg_rpeak_abs_amp_mean = NaN;
    summary.ecg_rpeak_abs_amp_std = NaN;
    summary.ecg_rpeak_abs_amp_median = NaN;
end

if height(R) > 0
    valid_rr_mask = ~isnan(R.rr_cleaned_ms);
    valid_rr = R.rr_cleaned_ms(valid_rr_mask);

    summary.ecg_rr_count_valid = numel(valid_rr);
    summary.ecg_rr_valid_fraction = mean(valid_rr_mask);

    if ~isempty(valid_rr)
        summary.meanNN_ecg = mean(valid_rr, 'omitnan');
        summary.meanHR_ecg = 60000 ./ summary.meanNN_ecg;
        summary.SDNN_ecg = std(valid_rr, 'omitnan');
        summary.rr_min_ecg = min(valid_rr, [], 'omitnan');
        summary.rr_max_ecg = max(valid_rr, [], 'omitnan');
        summary.rr_median_ecg = median(valid_rr, 'omitnan');
    end

    % HRV differences should use only truly adjacent, non-interpolated RR
    % intervals. If either endpoint is interpolated, the difference is partly
    % synthetic and should not contribute to RMSSD/pNN50.
    adjacent_diff_mask = ...
        ~isnan(R.rr_cleaned_ms(1:end-1)) & ...
        ~isnan(R.rr_cleaned_ms(2:end)) & ...
        ~R.was_interpolated(1:end-1) & ...
        ~R.was_interpolated(2:end);

    adjacent_diffs = diff(R.rr_cleaned_ms);
    adjacent_diffs = adjacent_diffs(adjacent_diff_mask);

    summary.ecg_adjacent_diff_count = numel(adjacent_diffs);

    if ~isempty(adjacent_diffs)
        summary.RMSSD_ecg = sqrt(mean(adjacent_diffs.^2, 'omitnan'));
        summary.pNN50_ecg = mean(abs(adjacent_diffs) > 50) * 100;
    end

    % Frequency-domain HRV from the cleaned ECG-derived RR tachogram.
    % This does not change R-peak detection or RR cleaning.
    [freq_hrv, freq_warning] = local_compute_frequency_hrv(R, cfg);

    summary.LF_ecg = freq_hrv.LF_ecg;
    summary.HF_ecg = freq_hrv.HF_ecg;
    summary.LFHF_ecg = freq_hrv.LFHF_ecg;
    summary.LFnu_ecg = freq_hrv.LFnu_ecg;
    summary.HFnu_ecg = freq_hrv.HFnu_ecg;
    summary.totalPower_ecg = freq_hrv.totalPower_ecg;

    if ~isempty(freq_warning)
        out.warnings{end+1} = freq_warning;
    end
else
    valid_rr_mask = false(0,1);
    valid_rr = [];
    adjacent_diffs = [];
end

out.summary = summary;

%% ------------------------------------------------------------------------
% QC
qc = local_base_qc(cfg, record);

qc.source_available = true;
qc.source_used = ecg_info.preferred_source;

qc.sample_rate_hz = fs;
qc.sample_rate_source = string(fs_source);
qc.total_samples = n;
qc.duration_sec = duration_sec;

qc.missing_sample_count = sum(is_missing);
qc.missing_sample_fraction = mean(is_missing);

qc.raw_min = raw_min;
qc.raw_max = raw_max;
qc.raw_range = raw_range;
qc.raw_std = raw_std;

qc.filter_low_cutoff_hz = filter_info.low_cutoff_hz;
qc.filter_high_cutoff_hz = filter_info.high_cutoff_hz;
qc.filter_order = filter_info.order;
qc.filter_effective_order_zero_phase = filter_info.effective_order_zero_phase;

qc.rpeak_count = numel(r_locs);
qc.rpeak_polarity = string(r_polarity);
qc.rpeak_prominence_used = peak_diag.prominence_used;
qc.rpeak_min_distance_samples = peak_diag.min_distance_samples;
qc.rpeak_selected_score = peak_diag.selected_score;
qc.rpeak_selected_median_rr_ms = peak_diag.selected_median_rr_ms;
qc.rpeak_selected_median_hr_bpm = peak_diag.selected_median_hr_bpm;
qc.rpeak_selected_artifact_ratio = peak_diag.selected_artifact_ratio;
qc.rpeak_selected_rr_cv = peak_diag.selected_rr_cv;

if ~isempty(r_pks)
    qc.rpeak_abs_amp_mean = mean(abs(r_pks), 'omitnan');
    qc.rpeak_abs_amp_std = std(abs(r_pks), 'omitnan');
    qc.rpeak_abs_amp_median = median(abs(r_pks), 'omitnan');
else
    qc.rpeak_abs_amp_mean = NaN;
    qc.rpeak_abs_amp_std = NaN;
    qc.rpeak_abs_amp_median = NaN;
end

qc.rr_count_total = height(R);

if height(R) > 0
    qc.rr_threshold_flag_count = sum(R.is_threshold_flag);
    qc.rr_jump_artifact_count = sum(R.is_jump_artifact);
    qc.rr_invalid_count_total = sum(R.is_invalid);
    qc.rr_interpolated_count = sum(R.was_interpolated);

    qc.rr_final_valid_count = sum(valid_rr_mask);
    qc.rr_final_nan_count = sum(~valid_rr_mask);
    qc.rr_valid_fraction_final = mean(valid_rr_mask);

    qc.rr_rejected_ratio_before_interpolation = mean(R.is_invalid);
else
    qc.rr_threshold_flag_count = 0;
    qc.rr_jump_artifact_count = 0;
    qc.rr_invalid_count_total = 0;
    qc.rr_interpolated_count = 0;

    qc.rr_final_valid_count = 0;
    qc.rr_final_nan_count = 0;
    qc.rr_valid_fraction_final = NaN;
    qc.rr_rejected_ratio_before_interpolation = NaN;
end

qc.usable_data_available = qc.rr_count_total > 0 && qc.rr_final_valid_count > 0;

if qc.usable_data_available
    qc.usable_suggestion = ...
        qc.rr_final_valid_count >= 30 && ...
        qc.rr_rejected_ratio_before_interpolation <= cfg.ecg.rr.usable_max_artifact_ratio;
else
    qc.usable_suggestion = false;
end

qc.warning_all_nan_output = isempty(valid_rr);
qc.warning_too_few_beats = qc.rr_final_valid_count < 30;
qc.warning_high_artifact_ratio = ...
    qc.rr_rejected_ratio_before_interpolation > cfg.ecg.rr.usable_max_artifact_ratio;

qc.warning_flatline = raw_std <= cfg.qc.zero_variance_tolerance;

if qc.warning_flatline
    out.warnings{end+1} = 'ECG raw signal appears flatline-like.';
end

if qc.warning_too_few_beats
    out.warnings{end+1} = sprintf( ...
        'Too few valid ECG RR intervals for reliable HRV: %d valid intervals.', ...
        qc.rr_final_valid_count);
end

if qc.warning_high_artifact_ratio
    out.warnings{end+1} = sprintf( ...
        'High ECG RR artifact ratio: %.2f.', ...
        qc.rr_rejected_ratio_before_interpolation);
end

if qc.warning_all_nan_output
    out.warnings{end+1} = 'No valid ECG RR intervals after cleaning.';
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

error('clean_ecg:FileInfoNotFound', ...
    'Could not find file info for %s in record.files.', expected_name);

end

%% ========================================================================
function [fs, fs_source, warning_msg] = local_get_ecg_sample_rate(cfg, record)

fs = cfg.ecg.sample_rate_hz_default;
fs_source = 'config_default';
warning_msg = '';

try
    xml_info = local_get_file_info(record, 'unisens.xml');

    if isfield(xml_info, 'raw_exists') && xml_info.raw_exists
        meta = parse_unisens_xml(xml_info.raw_path);

        if isfield(meta, 'entries')
            for i = 1:numel(meta.entries)
                entry = meta.entries(i);

                if isfield(entry, 'id') && strcmp(entry.id, 'ecg.csv')
                    if isfield(entry, 'sampleRate') && ~isempty(entry.sampleRate)
                        candidate_fs = double(entry.sampleRate);

                        if ~isnan(candidate_fs) && candidate_fs >= 100 && candidate_fs <= 5000
                            fs = candidate_fs;
                            fs_source = 'unisens_xml';
                            return;
                        else
                            warning_msg = sprintf( ...
                                'Unreasonable ECG sample rate from XML: %.4f. Using config default.', ...
                                candidate_fs);
                            return;
                        end
                    end
                end
            end
        end

        warning_msg = 'ECG sample rate not found in XML; using config default.';
    else
        warning_msg = 'unisens.xml missing; using ECG sample rate from config default.';
    end

catch ME
    warning_msg = sprintf( ...
        'Could not parse ECG sample rate from XML (%s). Using config default.', ...
        ME.message);
end

end

%% ========================================================================
function [ecg_filtered, info, warning_msg] = local_filter_ecg(ecg_centered, fs, cfg)

warning_msg = '';

info = struct();
info.low_cutoff_hz = cfg.ecg.filter.low_cutoff_hz;
info.high_cutoff_hz = cfg.ecg.filter.high_cutoff_hz;
info.order = 3;
info.effective_order_zero_phase = info.order * 2;
info.type = cfg.ecg.filter.type;

low = cfg.ecg.filter.low_cutoff_hz;
high = cfg.ecg.filter.high_cutoff_hz;
nyq = fs / 2;

if fs < 100
    error('clean_ecg:BadSampleRate', ...
        'ECG sample rate is unreasonably low: %.4f Hz.', fs);
end

if high >= nyq
    high = nyq * 0.95;
    info.high_cutoff_hz = high;

    warning_msg = sprintf( ...
        'ECG high cutoff adjusted to %.2f Hz because Nyquist is %.2f Hz.', ...
        high, nyq);
end

if low <= 0 || high <= low || high >= nyq
    error('clean_ecg:BadFilterSettings', ...
        'Invalid ECG filter settings: low=%.3f, high=%.3f, fs=%.3f', ...
        low, high, fs);
end

[b, a] = butter(info.order, [low high] ./ nyq, 'bandpass');

min_required_n = 3 * max(numel(a), numel(b));

if numel(ecg_centered) <= min_required_n
    error('clean_ecg:SegmentTooShortForFiltfilt', ...
        ['ECG segment too short for filtfilt. Samples=%d, minimum required>%d. ', ...
         'Zero-phase filtering doubles the effective filter order.'], ...
        numel(ecg_centered), min_required_n);
end

ecg_filtered = filtfilt(b, a, ecg_centered);

end

%% ========================================================================
function [r_locs, r_pks, polarity, diag] = local_detect_r_peaks(ecg_filtered, fs, cfg)

min_distance_samples = max(1, round(cfg.ecg.rpeak.min_peak_distance_sec * fs));

signal_std = std(ecg_filtered, 'omitnan');

if signal_std <= 0 || isnan(signal_std)
    signal_std = eps;
end

if ~isempty(cfg.ecg.rpeak.min_peak_prominence)
    prominence_values = cfg.ecg.rpeak.min_peak_prominence;
else
    multipliers = cfg.ecg.rpeak.prominence_multipliers;
    prominence_values = signal_std .* multipliers;
end

edge_samples = 0;
if isfield(cfg.ecg.rpeak, 'ignore_edge_seconds')
    edge_samples = round(cfg.ecg.rpeak.ignore_edge_seconds * fs);
end

% Use cell array to avoid MATLAB struct-field mismatch errors.
candidates = {};
candidate_idx = 0;

for p = 1:numel(prominence_values)

    prominence = prominence_values(p);

    % Positive peaks
    [pks_pos, locs_pos] = findpeaks( ...
        ecg_filtered, ...
        'MinPeakDistance', min_distance_samples, ...
        'MinPeakProminence', prominence);

    [locs_pos, pks_pos] = local_remove_edge_peaks( ...
        locs_pos, pks_pos, numel(ecg_filtered), edge_samples);

    candidate_idx = candidate_idx + 1;
    candidates{candidate_idx} = local_score_peak_candidate( ...
        locs_pos, pks_pos, 'positive', prominence, fs, cfg);

    % Negative peaks
    [pks_neg_abs, locs_neg] = findpeaks( ...
        -ecg_filtered, ...
        'MinPeakDistance', min_distance_samples, ...
        'MinPeakProminence', prominence);

    pks_neg_actual = -pks_neg_abs;

    [locs_neg, pks_neg_actual] = local_remove_edge_peaks( ...
        locs_neg, pks_neg_actual, numel(ecg_filtered), edge_samples);

    candidate_idx = candidate_idx + 1;
    candidates{candidate_idx} = local_score_peak_candidate( ...
        locs_neg, pks_neg_actual, 'negative', prominence, fs, cfg);
end

scores = NaN(numel(candidates), 1);

for i = 1:numel(candidates)
    scores(i) = candidates{i}.score;
end

[~, best_idx] = max(scores);
best = candidates{best_idx};

r_locs = best.locs(:);
r_pks = best.pks(:);
polarity = best.polarity;

diag = struct();
diag.prominence_used = best.prominence;
diag.min_distance_samples = min_distance_samples;
diag.selected_score = best.score;
diag.selected_median_rr_ms = best.median_rr_ms;
diag.selected_median_hr_bpm = best.median_hr_bpm;
diag.selected_artifact_ratio = best.artifact_ratio;
diag.selected_rr_cv = best.rr_cv;
diag.selected_peak_count = numel(best.locs);
diag.selected_polarity = string(best.polarity);

end

%% ========================================================================
function [locs_out, pks_out] = local_remove_edge_peaks(locs, pks, n_samples, edge_samples)

if edge_samples <= 0 || isempty(locs)
    locs_out = locs;
    pks_out = pks;
    return;
end

% Keep peaks at the boundary of the usable region.
keep = locs >= edge_samples & locs <= (n_samples - edge_samples);

locs_out = locs(keep);
pks_out = pks(keep);

end

%% ========================================================================
function c = local_score_peak_candidate(locs, pks, polarity, prominence, fs, cfg)

c = struct();
c.locs = locs(:);
c.pks = pks(:);
c.polarity = polarity;
c.prominence = prominence;

c.score = -Inf;
c.median_rr_ms = NaN;
c.median_hr_bpm = NaN;
c.artifact_ratio = 1;
c.rr_cv = Inf;
c.amp_cv = Inf;

if numel(c.locs) < 3
    return;
end

rr_ms = diff(c.locs) ./ fs .* 1000;
rr_ms = rr_ms(:);

[~, ~, threshold_bad, ~, jump_bad, invalid_bad] = ...
    local_compute_rr_artifact_flags(rr_ms, cfg);

valid_rr_for_stats = rr_ms(~threshold_bad);

if numel(valid_rr_for_stats) < 3
    return;
end

median_rr = median(valid_rr_for_stats, 'omitnan');
median_hr = 60000 ./ median_rr;

plausible_ratio = mean(~threshold_bad);
artifact_ratio = mean(invalid_bad);

rr_cv = std(valid_rr_for_stats, 'omitnan') ./ median_rr;

amp_abs = abs(c.pks);
amp_mean = mean(amp_abs, 'omitnan');

if amp_mean > 0
    amp_cv = std(amp_abs, 'omitnan') ./ amp_mean;
else
    amp_cv = Inf;
end

hr_min = cfg.ecg.rpeak.expected_hr_min_bpm;
hr_max = cfg.ecg.rpeak.expected_hr_max_bpm;

if median_hr >= hr_min && median_hr <= hr_max
    hr_penalty = 0;
elseif median_hr < hr_min
    hr_penalty = (hr_min - median_hr) / hr_min;
else
    hr_penalty = (median_hr - hr_max) / hr_max;
end

% Do not reward peak count alone. Prefer plausible, regular, low-artifact RR.
c.score = ...
    100 * plausible_ratio ...
    - 120 * artifact_ratio ...
    - 40 * hr_penalty ...
    - 25 * rr_cv ...
    - 10 * amp_cv;

c.median_rr_ms = median_rr;
c.median_hr_bpm = median_hr;
c.artifact_ratio = artifact_ratio;
c.rr_cv = rr_cv;
c.amp_cv = amp_cv;

end

%% ========================================================================
function R = local_build_rr_table(r_locs, fs, cfg)

if numel(r_locs) < 2
    R = table( ...
        zeros(0,1), ...
        zeros(0,1), ...
        zeros(0,1), ...
        false(0,1), ...
        false(0,1), ...
        false(0,1), ...
        zeros(0,1), ...
        false(0,1), ...
        false(0,1), ...
        'VariableNames', { ...
            'rr_idx', ...
            'time_sec', ...
            'rr_ms', ...
            'is_below_min', ...
            'is_above_max', ...
            'is_threshold_flag', ...
            'rr_diff_from_previous_ms', ...
            'is_jump_artifact', ...
            'is_invalid'});
    return;
end

rr_ms = diff(r_locs) ./ fs .* 1000;
rr_ms = rr_ms(:);

rr_time_sec = r_locs(2:end) ./ fs;
rr_time_sec = rr_time_sec(:);

n_rr = numel(rr_ms);

R = table();
R.rr_idx = (1:n_rr)';
R.time_sec = rr_time_sec;
R.rr_ms = rr_ms;

[R.is_below_min, ...
 R.is_above_max, ...
 R.is_threshold_flag, ...
 R.rr_diff_from_previous_ms, ...
 R.is_jump_artifact, ...
 R.is_invalid] = local_compute_rr_artifact_flags(rr_ms, cfg);

end

function [is_below_min, is_above_max, is_threshold_flag, rr_diff_from_previous_ms, is_jump_artifact, is_invalid] = ...
    local_compute_rr_artifact_flags(rr_ms, cfg)

rr_ms = rr_ms(:);

is_below_min = rr_ms < cfg.ecg.rpeak.min_rr_ms;
is_above_max = rr_ms > cfg.ecg.rpeak.max_rr_ms;
is_threshold_flag = is_below_min | is_above_max;

rr_diff_from_previous_ms = [NaN; abs(diff(rr_ms))];

is_jump_artifact = false(numel(rr_ms), 1);

enable_artifact_handling = false;

if isfield(cfg.ecg, 'rr') && isfield(cfg.ecg.rr, 'enable_artifact_handling')
    enable_artifact_handling = cfg.ecg.rr.enable_artifact_handling;
end

if enable_artifact_handling

    if isfield(cfg.ecg.rr, 'jump_abs_diff_ms')
        jump_abs_diff_ms = cfg.ecg.rr.jump_abs_diff_ms;
    else
        jump_abs_diff_ms = Inf;
    end

    if isfield(cfg.ecg.rr, 'jump_relative_fraction')
        jump_relative_fraction = cfg.ecg.rr.jump_relative_fraction;
    else
        jump_relative_fraction = Inf;
    end

    abs_jump_mask = rr_diff_from_previous_ms > jump_abs_diff_ms;

    prev_rr = [NaN; rr_ms(1:end-1)];
    rel_change = abs(rr_ms - prev_rr) ./ prev_rr;
    rel_jump_mask = rel_change > jump_relative_fraction;
    rel_jump_mask(isnan(rel_jump_mask)) = false;

    is_jump_artifact = abs_jump_mask | rel_jump_mask;
    is_jump_artifact(1) = false;

    previous_threshold_bad = [false; is_threshold_flag(1:end-1)];
    current_threshold_bad = is_threshold_flag;

    is_jump_artifact(previous_threshold_bad | current_threshold_bad) = false;
end

is_invalid = is_threshold_flag | is_jump_artifact;

end


%% ========================================================================
function [x_out, interpolated_mask] = local_interpolate_short_gaps_no_propagation(x_original, max_gap_len)

x_out = x_original;
interpolated_mask = false(size(x_original));

if max_gap_len <= 0
    return;
end

is_nan = isnan(x_original);

if ~any(is_nan)
    return;
end

n = numel(x_original);
d = diff([false; is_nan; false]);
gap_starts = find(d == 1);
gap_ends = find(d == -1) - 1;

for g = 1:numel(gap_starts)
    a = gap_starts(g);
    b = gap_ends(g);
    gap_len = b - a + 1;

    has_left_original = a > 1 && ~isnan(x_original(a-1));
    has_right_original = b < n && ~isnan(x_original(b+1));

    if gap_len <= max_gap_len && has_left_original && has_right_original
        left_val = x_original(a-1);
        right_val = x_original(b+1);

        interp_vals = linspace(left_val, right_val, gap_len + 2);
        interp_vals = interp_vals(2:end-1);

        x_out(a:b) = interp_vals(:);
        interpolated_mask(a:b) = true;
    end
end

end


%% ========================================================================
function [freq_hrv, warning_msg] = local_compute_frequency_hrv(R, cfg)

freq_hrv = local_nan_frequency_hrv();
warning_msg = '';

if ~isfield(cfg, 'ecg') || ~isfield(cfg.ecg, 'freq')
    warning_msg = 'ECG frequency-domain HRV configuration missing. Frequency-domain HRV returned as NaN.';
    return;
end

if isfield(cfg.ecg.freq, 'compute') && ~cfg.ecg.freq.compute
    return;
end

min_valid_rr_count = cfg.ecg.freq.min_valid_rr_count;
interp_fs_hz = cfg.ecg.freq.interp_fs_hz;
lf_band_hz = cfg.ecg.freq.lf_band_hz;
hf_band_hz = cfg.ecg.freq.hf_band_hz;
total_power_band_hz = cfg.ecg.freq.total_power_band_hz;

if height(R) == 0 || ...
        ~ismember('time_sec', R.Properties.VariableNames) || ...
        ~ismember('rr_cleaned_ms', R.Properties.VariableNames)
    warning_msg = 'No cleaned ECG RR table available for frequency-domain HRV. Frequency-domain HRV returned as NaN.';
    return;
end

rr_time_sec = double(R.time_sec(:));
rr_cleaned_ms = double(R.rr_cleaned_ms(:));

valid_mask = ...
    isfinite(rr_time_sec) & ...
    isfinite(rr_cleaned_ms) & ...
    ~isnan(rr_time_sec) & ...
    ~isnan(rr_cleaned_ms);

if sum(valid_mask) < min_valid_rr_count
    warning_msg = sprintf( ...
        'Too few valid cleaned ECG RR intervals for frequency-domain HRV: %d valid intervals; minimum required is %d. Frequency-domain HRV returned as NaN.', ...
        sum(valid_mask), min_valid_rr_count);
    return;
end

t_valid = rr_time_sec(valid_mask);
rr_valid_sec = rr_cleaned_ms(valid_mask) ./ 1000;

[t_valid, unique_idx] = unique(t_valid, 'stable');
rr_valid_sec = rr_valid_sec(unique_idx);

if numel(t_valid) < min_valid_rr_count
    warning_msg = sprintf( ...
        'Too few unique valid ECG RR time points for frequency-domain HRV: %d unique points; minimum required is %d. Frequency-domain HRV returned as NaN.', ...
        numel(t_valid), min_valid_rr_count);
    return;
end

if t_valid(end) <= t_valid(1)
    warning_msg = 'Cleaned ECG RR timestamps are not usable for frequency-domain HRV. Frequency-domain HRV returned as NaN.';
    return;
end

t_interp = (t_valid(1):(1/interp_fs_hz):t_valid(end))';

if numel(t_interp) < 4
    warning_msg = 'Interpolated ECG RR tachogram is too short for frequency-domain HRV. Frequency-domain HRV returned as NaN.';
    return;
end

try
    rr_interp_sec = interp1(t_valid, rr_valid_sec, t_interp, 'linear');
    rr_interp_sec = rr_interp_sec(:);

    valid_interp = isfinite(rr_interp_sec) & ~isnan(rr_interp_sec);
    rr_interp_sec = rr_interp_sec(valid_interp);

    if numel(rr_interp_sec) < 4
        warning_msg = 'Interpolated ECG RR tachogram contains too few valid samples for frequency-domain HRV. Frequency-domain HRV returned as NaN.';
        return;
    end

    rr_detrended_sec = detrend(rr_interp_sec, 'linear');

    [pxx, f] = pwelch(rr_detrended_sec, [], [], [], interp_fs_hz);

    pxx = double(pxx(:));
    f = double(f(:));

    lf_power_s2 = local_integrate_band_power(f, pxx, lf_band_hz);
    hf_power_s2 = local_integrate_band_power(f, pxx, hf_band_hz);
    total_power_s2 = local_integrate_band_power(f, pxx, total_power_band_hz);
    
    % RR tachogram is in seconds, so Welch band power is in s^2.
    % Convert absolute power values to ms^2 for standard HRV reporting.
    lf_power_ms2 = lf_power_s2 * 1e6;
    hf_power_ms2 = hf_power_s2 * 1e6;
    total_power_ms2 = total_power_s2 * 1e6;
    
    freq_hrv.LF_ecg = lf_power_ms2;
    freq_hrv.HF_ecg = hf_power_ms2;
    freq_hrv.totalPower_ecg = total_power_ms2;
    
    if isfinite(hf_power_ms2) && hf_power_ms2 > 0
        freq_hrv.LFHF_ecg = lf_power_ms2 ./ hf_power_ms2;
    end
    
    lf_hf_sum = lf_power_ms2 + hf_power_ms2;
    
    if isfinite(lf_hf_sum) && lf_hf_sum > 0
        freq_hrv.LFnu_ecg = (lf_power_ms2 ./ lf_hf_sum) .* 100;
        freq_hrv.HFnu_ecg = (hf_power_ms2 ./ lf_hf_sum) .* 100;
    end

catch ME
    warning_msg = sprintf( ...
        'Frequency-domain ECG HRV computation failed (%s). Frequency-domain HRV returned as NaN.', ...
        ME.message);
    freq_hrv = local_nan_frequency_hrv();
end

end

%% ========================================================================
function freq_hrv = local_nan_frequency_hrv()

freq_hrv = struct();
freq_hrv.LF_ecg = NaN;
freq_hrv.HF_ecg = NaN;
freq_hrv.LFHF_ecg = NaN;
freq_hrv.LFnu_ecg = NaN;
freq_hrv.HFnu_ecg = NaN;
freq_hrv.totalPower_ecg = NaN;

end

%% ========================================================================
function band_power = local_integrate_band_power(f, pxx, band_hz)

band_power = NaN;

f = double(f(:));
pxx = double(pxx(:));
band_hz = double(band_hz(:))';

valid = isfinite(f) & isfinite(pxx) & ~isnan(f) & ~isnan(pxx);
f = f(valid);
pxx = pxx(valid);

if numel(band_hz) ~= 2 || band_hz(1) < 0 || band_hz(2) <= band_hz(1)
    return;
end

if numel(f) < 2 || numel(pxx) < 2
    return;
end

if band_hz(1) < min(f) || band_hz(2) > max(f)
    return;
end

band_mask = f >= band_hz(1) & f <= band_hz(2);
f_band = f(band_mask);
pxx_band = pxx(band_mask);

if isempty(f_band)
    return;
end

if f_band(1) > band_hz(1)
    p_left = interp1(f, pxx, band_hz(1), 'linear');
    f_band = [band_hz(1); f_band];
    pxx_band = [p_left; pxx_band];
end

if f_band(end) < band_hz(2)
    p_right = interp1(f, pxx, band_hz(2), 'linear');
    f_band = [f_band; band_hz(2)];
    pxx_band = [pxx_band; p_right];
end

if numel(f_band) < 2
    return;
end

band_power = trapz(f_band, pxx_band);

end

%% ========================================================================
function s = local_nan_summary()

s = struct();

s.ecg_total_samples = 0;
s.ecg_duration_sec = NaN;
s.ecg_sample_rate_hz = NaN;

s.ecg_raw_min = NaN;
s.ecg_raw_max = NaN;
s.ecg_raw_range = NaN;
s.ecg_raw_std = NaN;

s.ecg_filter_low_cutoff_hz = NaN;
s.ecg_filter_high_cutoff_hz = NaN;

s.ecg_rpeak_count = 0;
s.ecg_rr_count_total = 0;
s.ecg_rpeak_polarity = "";
s.ecg_rpeak_abs_amp_mean = NaN;
s.ecg_rpeak_abs_amp_std = NaN;
s.ecg_rpeak_abs_amp_median = NaN;

s.ecg_rr_count_valid = 0;
s.ecg_rr_valid_fraction = NaN;
s.ecg_adjacent_diff_count = 0;

s.meanNN_ecg = NaN;
s.meanHR_ecg = NaN;
s.RMSSD_ecg = NaN;
s.SDNN_ecg = NaN;
s.pNN50_ecg = NaN;

s.LF_ecg = NaN;
s.HF_ecg = NaN;
s.LFHF_ecg = NaN;
s.LFnu_ecg = NaN;
s.HFnu_ecg = NaN;
s.totalPower_ecg = NaN;

s.rr_min_ecg = NaN;
s.rr_max_ecg = NaN;
s.rr_median_ecg = NaN;

end

%% ========================================================================
function qc = local_base_qc(cfg, record)

qc = struct();

qc.participant_id = record.participant_id;
qc.sensor = record.sensor;
qc.segment_name = record.segment_name;
qc.segment_type = record.segment_type;

qc.source_available = false;
qc.source_used = '';

qc.sample_rate_hz = cfg.ecg.sample_rate_hz_default;
qc.sample_rate_source = "config_default";

qc.total_samples = NaN;
qc.duration_sec = NaN;

qc.missing_sample_count = NaN;
qc.missing_sample_fraction = NaN;

qc.raw_min = NaN;
qc.raw_max = NaN;
qc.raw_range = NaN;
qc.raw_std = NaN;

qc.filter_low_cutoff_hz = NaN;
qc.filter_high_cutoff_hz = NaN;
qc.filter_order = NaN;
qc.filter_effective_order_zero_phase = NaN;

qc.rpeak_count = NaN;
qc.rpeak_polarity = "";
qc.rpeak_prominence_used = NaN;
qc.rpeak_min_distance_samples = NaN;
qc.rpeak_selected_score = NaN;
qc.rpeak_selected_median_rr_ms = NaN;
qc.rpeak_selected_median_hr_bpm = NaN;
qc.rpeak_selected_artifact_ratio = NaN;
qc.rpeak_selected_rr_cv = NaN;
qc.rpeak_abs_amp_mean = NaN;
qc.rpeak_abs_amp_std = NaN;
qc.rpeak_abs_amp_median = NaN;


qc.rr_count_total = NaN;
qc.rr_threshold_flag_count = NaN;
qc.rr_jump_artifact_count = NaN;
qc.rr_invalid_count_total = NaN;
qc.rr_interpolated_count = NaN;

qc.rr_final_valid_count = NaN;
qc.rr_final_nan_count = NaN;
qc.rr_valid_fraction_final = NaN;
qc.rr_rejected_ratio_before_interpolation = NaN;

qc.usable_suggestion = false;
qc.usable_data_available = false;

qc.warning_all_nan_output = false;
qc.warning_too_few_beats = false;
qc.warning_high_artifact_ratio = false;
qc.warning_flatline = false;
qc.warning_messages = '';

end