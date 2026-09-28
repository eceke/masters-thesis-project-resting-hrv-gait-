function cfg = get_preprocessing_config()
%GET_PREPROCESSING_CONFIG Central configuration for the Pertuba pipeline.
%
% OUTPUT
%   cfg : struct containing all configuration parameters used throughout
%         preprocessing, QC, feature extraction, merging, and dataset build.

%% ------------------------------------------------------------------------
%  PROJECT PATHS
%  ------------------------------------------------------------------------
cfg = struct();

preprocessRoot = fileparts(fileparts(mfilename('fullpath')));
codeRoot = fileparts(preprocessRoot);

cfg.paths = struct();
cfg.paths.epochs_root = fullfile(codeRoot, ...
    'Epoching of Experiment Data', 'Epochs');
cfg.paths.output_root = fullfile(preprocessRoot, 'Output');
cfg.paths.logs_root = fullfile(cfg.paths.output_root, 'Logs');
cfg.paths.features_root = fullfile(cfg.paths.output_root, 'Feature Tables');
cfg.paths.qc_root = fullfile(cfg.paths.output_root, 'QC');
cfg.paths.kinesis_file = fullfile(preprocessRoot, 'Kinesis', ...
    'PERTUBA WORDS IN MOTION_CLEAN DATABASE_(N = 30).xlsx');

%% ------------------------------------------------------------------------
%  PARTICIPANT / SENSOR / SEGMENT DISCOVERY
%  ------------------------------------------------------------------------
cfg.discovery = struct();

% Participant folders expected to look like VP1, VP2, ..., VP30
cfg.discovery.participant_prefix = 'VP';
cfg.discovery.participant_regex  = '^VP\d+$';

% Sensors to look for under each participant
cfg.sensors = {'Heart', 'Hip'};

% Segment folders to include
cfg.segments = struct();
cfg.segments.include = { ...
    'BW_1KMH', ...
    'BW_4KMH', ...
    'FWW_1KMH', ...
    'FWW_4KMH', ...
    'RS_EC', ...
    'RS_EO1', ...
    'RS_EO2'};

% Segment folders to exclude even if present
cfg.segments.exclude = {'TABLE'};

% Segment category labels for later modeling / merges
cfg.segments.rest_segments    = {'RS_EO1', 'RS_EC', 'RS_EO2'};
cfg.segments.walk_segments    = {'BW_1KMH', 'BW_4KMH', 'FWW_1KMH', 'FWW_4KMH'};
cfg.segments.baseline_walk    = {'BW_1KMH', 'BW_4KMH'};
cfg.segments.forward_walk     = {'FWW_1KMH', 'FWW_4KMH'};
cfg.segments.speed_1          = {'BW_1KMH', 'FWW_1KMH'};
cfg.segments.speed_4          = {'BW_4KMH', 'FWW_4KMH'};

%% ------------------------------------------------------------------------
%  EXPECTED FILES
%  ------------------------------------------------------------------------
cfg.files = struct();

cfg.files.expected = { ...
    'acc.csv', ...
    'angularrate.csv', ...
    'bpmbxb_live.csv', ...
    'charging.csv', ...
    'ecg.csv', ...
    'hr_live.csv', ...
    'hrvisvalid_live.csv', ...
    'hrvrmssd_live.csv', ...
    'movementacceleration_live.csv', ...
    'nn_live.csv', ...
    'press.csv', ...
    'stateofcharge.csv', ...
    'stepcount_live.csv', ...
    'temp.csv', ...
    'tempmean_live.csv', ...
    'unisens.xml'};

%% Sensor-specific expected files

cfg.files.expected_by_sensor = struct();

cfg.files.expected_by_sensor.Heart = { ...
    'acc.csv', ...
    'angularrate.csv', ...
    'bpmbxb_live.csv', ...
    'charging.csv', ...
    'ecg.csv', ...
    'hr_live.csv', ...
    'hrvisvalid_live.csv', ...
    'hrvrmssd_live.csv', ...
    'movementacceleration_live.csv', ...
    'nn_live.csv', ...
    'press.csv', ...
    'stateofcharge.csv', ...
    'stepcount_live.csv', ...
    'temp.csv', ...
    'tempmean_live.csv', ...
    'unisens.xml'};

cfg.files.expected_by_sensor.Hip = { ...
    'acc.csv', ...
    'angularrate.csv', ...
    'charging.csv', ...
    'movementacceleration_live.csv', ...
    'press.csv', ...
    'stateofcharge.csv', ...
    'stepcount_live.csv', ...
    'temp.csv', ...
    'tempmean_live.csv', ...
    'unisens.xml'};

%% File requirement levels (CRITICAL FOR PIPELINE BEHAVIOR)

% -------- HEART --------
cfg.files.hard_required.Heart = { ...
    'ecg.csv', ...
    'hr_live.csv', ...
    'hrvrmssd_live.csv', ...
    'hrvisvalid_live.csv', ...
    'temp.csv', ...
    'nn_live.csv', ...
    'bpmbxb_live.csv'};

cfg.files.soft_required.Heart = { ...
    'acc.csv', ...
    'angularrate.csv', ...
    'movementacceleration_live.csv', ...
    'stepcount_live.csv', ...
    'press.csv', ...
    'tempmean_live.csv'};

% -------- HIP --------
cfg.files.hard_required.Hip = { ...
    'acc.csv', ...
    'angularrate.csv', ...
    'movementacceleration_live.csv', ...
    'stepcount_live.csv'};

cfg.files.soft_required.Hip = { ...
    'press.csv', ...
    'tempmean_live.csv'};

% -------- LOG ONLY --------
cfg.files.log_only = { ...
    'charging.csv', ...
    'stateofcharge.csv'};

% -------- XML --------
cfg.files.xml_required = {'unisens.xml'};

% Continuous / regularly sampled files
cfg.files.continuous = { ...
    'ecg.csv', ...
    'acc.csv', ...
    'angularrate.csv', ...
    'temp.csv', ...
    'press.csv', ...
    'movementacceleration_live.csv', ...
    'hr_live.csv', ...
    'hrvrmssd_live.csv', ...
    'stepcount_live.csv', ...
    'tempmean_live.csv'};

% Event-based files
cfg.files.event_based = { ...
    'nn_live.csv', ...
    'bpmbxb_live.csv'};

% Metadata / device-state files
cfg.files.metadata = { ...
    'charging.csv', ...
    'stateofcharge.csv', ...
    'unisens.xml'};

%% ------------------------------------------------------------------------
%  CONCEPTUAL SENSOR GROUPS
%  ------------------------------------------------------------------------
cfg.groups = struct();

cfg.groups.heart_primary_physiology = { ...
    'ecg.csv', ...
    'hr_live.csv', ...
    'hrvisvalid_live.csv', ...
    'hrvrmssd_live.csv', ...
    'nn_live.csv', ...
    'bpmbxb_live.csv', ...
    'temp.csv', ...
    'tempmean_live.csv', ...
    'press.csv', ...
    'charging.csv', ...
    'stateofcharge.csv', ...
    'unisens.xml'};

cfg.groups.heart_motion_qc = { ...
    'acc.csv', ...
    'angularrate.csv', ...
    'movementacceleration_live.csv', ...
    'stepcount_live.csv'};

cfg.groups.hip_primary_motion = { ...
    'acc.csv', ...
    'angularrate.csv', ...
    'movementacceleration_live.csv', ...
    'stepcount_live.csv'};

cfg.groups.hip_context_qc = { ...
    'temp.csv', ...
    'tempmean_live.csv', ...
    'press.csv', ...
    'charging.csv', ...
    'stateofcharge.csv', ...
    'unisens.xml'};

cfg.groups.hip_additional_cardiac_like = { ...
    'ecg.csv', ...
    'hr_live.csv', ...
    'hrvisvalid_live.csv', ...
    'hrvrmssd_live.csv', ...
    'nn_live.csv', ...
    'bpmbxb_live.csv'};

%% ------------------------------------------------------------------------
%  GENERAL FLAGS
%  ------------------------------------------------------------------------
cfg.flags = struct();

cfg.flags.enable_interpolation           = false;
cfg.flags.enable_smoothing               = true;
cfg.flags.save_flagged_versions          = true;
cfg.flags.save_cleaned_versions          = true;
cfg.flags.save_qc_tables                 = true;
cfg.flags.keep_full_master_dataset       = true;
cfg.flags.continue_on_missing_file       = true;
cfg.flags.continue_on_processing_error   = true;
cfg.flags.warn_on_mass_flagging          = true;
cfg.flags.warn_on_all_nan_output         = true;
cfg.flags.warn_on_zero_variance          = true;
cfg.flags.verbose_console                = true;

%% ------------------------------------------------------------------------
%  OUTPUT NAMING
%  ------------------------------------------------------------------------
cfg.output = struct();

cfg.output.flagged_suffix = '_flagged.csv';
cfg.output.cleaned_suffix = '_cleaned.csv';
cfg.output.summary_suffix = '_summary.csv';
cfg.output.qc_suffix      = '_qc.csv';
cfg.output.features_suffix = '_features.csv';

%% ------------------------------------------------------------------------
%  GENERIC QC RULES
%  ------------------------------------------------------------------------
cfg.qc = struct();

cfg.qc.mass_flagging_fraction_warning = 0.80;  % warn if >= 80% flagged
cfg.qc.high_nan_fraction_warning      = 0.50;  % warn if >= 50% NaN
cfg.qc.zero_variance_tolerance        = 1e-12;
cfg.qc.duplicate_row_check            = true;
cfg.qc.flatline_min_run_length        = 20;    % generic placeholder
cfg.qc.max_interpolation_fraction     = 0.20;  % generic warning threshold

%% ------------------------------------------------------------------------
%  TEMPERATURE THRESHOLDS
%  ------------------------------------------------------------------------
cfg.temp = struct();
cfg.temp.min = 20;
cfg.temp.max = 45;
cfg.temp.enable_smoothing = false;
cfg.temp.smoothing_method = 'movmean';
cfg.temp.smoothing_window = 5;

cfg.tempmean = struct();
cfg.tempmean.min = 20;
cfg.tempmean.max = 45;
cfg.tempmean.enable_smoothing = false;
cfg.tempmean.smoothing_method = 'movmean';
cfg.tempmean.smoothing_window = 5;

%  ------------------------------------------------------------------------
%% Pressure signal thresholds
%  ------------------------------------------------------------------------
cfg.press.min = 30000;   % Pa
cfg.press.max = 120000;  % Pa

%% ------------------------------------------------------------------------
%  HR THRESHOLDS
%  ------------------------------------------------------------------------
cfg.hr = struct();
cfg.hr.min = 30;
cfg.hr.max = 220;
cfg.hr.enable_local_outlier_rule = true;
cfg.hr.local_outlier_method = 'movmedian';
cfg.hr.local_outlier_window = 5;
cfg.hr.local_outlier_thresh = 4;  % robust deviation multiplier
cfg.hr.enable_interpolation = true;
cfg.hr.max_interp_gap = 3;        % in samples/windows, to be interpreted by cleaner
cfg.hr.enable_smoothing = false;
cfg.hr.smoothing_method = 'movmean';
cfg.hr.smoothing_window = 3;

%% ------------------------------------------------------------------------
%  HRV LIVE (DEVICE-DERIVED RMSSD) THRESHOLDS
%  ------------------------------------------------------------------------
cfg.hrvrmssd = struct();
cfg.hrvrmssd.min = 0;
cfg.hrvrmssd.max = 300;
cfg.hrvrmssd.enable_interpolation = true;
cfg.hrvrmssd.max_interp_gap = 2;
cfg.hrvrmssd.enable_smoothing = false;
cfg.hrvrmssd.smoothing_method = 'movmean';
cfg.hrvrmssd.smoothing_window = 3;

%% ------------------------------------------------------------------------
%  HRVISVALID RULES
%  ------------------------------------------------------------------------
cfg.hrvisvalid = struct();
cfg.hrvisvalid.valid_value = 1;
cfg.hrvisvalid.invalid_value = 0;

%% ------------------------------------------------------------------------
%  NN INTERVAL RULES
%  ------------------------------------------------------------------------
cfg.nn = struct();
cfg.nn.sample_rate_hz = 1024;  % from known XML for nn_live timing conversion
cfg.nn.min_ms = 300;
cfg.nn.max_ms = 2000;
cfg.nn.enable_jump_detection = true;
cfg.nn.jump_abs_diff_ms = 250;          % initial conservative threshold
cfg.nn.jump_relative_fraction = 0.20;   % relative jump threshold
cfg.nn.enable_short_gap_interpolation = true;
cfg.nn.max_interp_gap_beats = 2;
cfg.nn.usable_max_invalid_ratio = 0.20;

% Time-domain HRV feature flags
cfg.nn.features = struct();
cfg.nn.features.compute_rmssd = true;
cfg.nn.features.compute_sdnn  = true;
cfg.nn.features.compute_pnn50 = true;
cfg.nn.features.compute_meanhr = true;
cfg.nn.features.compute_meannn = true;

%% ------------------------------------------------------------------------
%  BPMBXB RULES
%  ------------------------------------------------------------------------
cfg.bpmbxb = struct();
cfg.bpmbxb.min = 30;
cfg.bpmbxb.max = 220;
cfg.bpmbxb.enable_jump_detection = true;
cfg.bpmbxb.jump_abs_diff_bpm = 30;
cfg.bpmbxb.jump_relative_fraction = 0.20;
cfg.bpmbxb.enable_short_gap_interpolation = true;
cfg.bpmbxb.max_interp_gap_beats = 2;

%% ------------------------------------------------------------------------
%  ACCELERATION RULES
%  ------------------------------------------------------------------------
cfg.acc = struct();
cfg.acc.expect_num_axes = [1 3]; % allow either scalar or multi-axis
cfg.acc.min_plausible_g = -16;
cfg.acc.max_plausible_g = 16;
cfg.acc.compute_magnitude = true;
cfg.acc.enable_filtering = true;
cfg.acc.filter_type = 'highpass_then_summary';
cfg.acc.highpass_cutoff_hz = 0.25; % placeholder, to revisit for motion methodology
cfg.acc.flatline_std_threshold = 1e-6;
cfg.acc.clipping_threshold_fraction = 0.98;

%% ------------------------------------------------------------------------
%  ANGULAR RATE RULES
%  ------------------------------------------------------------------------
cfg.angularrate = struct();
cfg.angularrate.expect_num_axes = [1 3];
cfg.angularrate.min_plausible_dps = -2000;
cfg.angularrate.max_plausible_dps = 2000;
cfg.angularrate.compute_magnitude = true;
cfg.angularrate.enable_filtering = true;
cfg.angularrate.filter_type = 'summary_friendly';
cfg.angularrate.flatline_std_threshold = 1e-6;

%% ------------------------------------------------------------------------
%  MOVEMENT ACCELERATION LIVE RULES
%  ------------------------------------------------------------------------
cfg.movementacceleration = struct();
cfg.movementacceleration.min = 0;
cfg.movementacceleration.max = 20; % placeholder conservative upper bound
cfg.movementacceleration.enable_smoothing = false;
cfg.movementacceleration.smoothing_method = 'movmean';
cfg.movementacceleration.smoothing_window = 3;

%% ------------------------------------------------------------------------
%  STEP COUNT RULES
%  ------------------------------------------------------------------------
cfg.stepcount = struct();
cfg.stepcount.min = 0;
cfg.stepcount.max = 100000;
cfg.stepcount.warn_if_rest_has_steps = true;
cfg.stepcount.warn_if_walk_has_zero_steps = true;

%% ------------------------------------------------------------------------
%  PRESSURE RULES
%  ------------------------------------------------------------------------
cfg.press = struct();
% press.csv is expected in Pa after Physical conversion.
% Atmospheric pressure is roughly around 101325 Pa.
% These are intentionally broad plausibility thresholds.
cfg.press.min = 30000;
cfg.press.max = 120000;
cfg.press.enable_smoothing = false;

%% ------------------------------------------------------------------------
%  ECG RULES
%  ------------------------------------------------------------------------
cfg.ecg = struct();
cfg.ecg.sample_rate_hz_default = 1024;
cfg.ecg.apply_scaling_from_xml = true;
cfg.ecg.remove_baseline = true;

% Bandpass settings
cfg.ecg.filter = struct();
cfg.ecg.filter.type = 'bandpass';
cfg.ecg.filter.low_cutoff_hz = 0.5;
cfg.ecg.filter.high_cutoff_hz = 40;

% R-peak detection parameters
cfg.ecg.rpeak = struct();
cfg.ecg.rpeak.min_rr_ms = 300;
cfg.ecg.rpeak.max_rr_ms = 2000;

% More conservative than 0.30 sec to reduce double-detection of T-waves/noise.
% 0.40 sec still allows up to 150 bpm, enough for these walking segments.
cfg.ecg.rpeak.min_peak_distance_sec = 0.40;

cfg.ecg.rpeak.min_peak_height = [];
cfg.ecg.rpeak.min_peak_prominence = [];

% Candidate prominence multipliers tested automatically.
cfg.ecg.rpeak.prominence_multipliers = [0.8 1.0 1.2 1.5 2.0 2.5];

% Broad expected HR range for choosing the best R-peak candidate.
cfg.ecg.rpeak.expected_hr_min_bpm = 40;
cfg.ecg.rpeak.expected_hr_max_bpm = 170;

% Ignore possible filter edge artifacts.
cfg.ecg.rpeak.ignore_edge_seconds = 0.50;

% ECG-derived RR interval cleaning
cfg.ecg.rr = struct();
cfg.ecg.rr.enable_artifact_handling = true;

% ECG RR artifact thresholds, separate from cfg.nn.
cfg.ecg.rr.jump_abs_diff_ms = 250;
cfg.ecg.rr.jump_relative_fraction = 0.20;

cfg.ecg.rr.max_interp_gap_beats = 2;
cfg.ecg.rr.usable_max_artifact_ratio = 0.20;

% Frequency-domain HRV settings
% Uses the already cleaned ECG-derived RR series from clean_ecg.m.
cfg.ecg.freq = struct();
cfg.ecg.freq.compute = true;
cfg.ecg.freq.method = 'rr_tachogram_4hz_linear_detrend_welch';
cfg.ecg.freq.interp_fs_hz = 4;
cfg.ecg.freq.lf_band_hz = [0.04 0.15];
cfg.ecg.freq.hf_band_hz = [0.15 0.40];
cfg.ecg.freq.total_power_band_hz = [0.04 0.40];
cfg.ecg.freq.min_valid_rr_count = 120;

%% ------------------------------------------------------------------------
%  DEVICE STATE FILES
%  ------------------------------------------------------------------------
cfg.device_state = struct();
cfg.device_state.expected_binary_like_columns = 1;
cfg.device_state.summarize_only = true;

%% ------------------------------------------------------------------------
%  KINESIS SETTINGS
%  ------------------------------------------------------------------------
cfg.kinesis = struct();
cfg.kinesis.sheet = 1;
cfg.kinesis.participant_column_candidates = {'Participant', 'ParticipantID', 'VP', 'ID'};
cfg.kinesis.condition_column = 'Condition';
cfg.kinesis.task_column_candidates = {'Task', 'TaskType'};
cfg.kinesis.speed_column_candidates = {'Speed', 'WalkingSpeed'};

cfg.kinesis.segment_map = struct();
cfg.kinesis.segment_map.FW_Speed_1       = 'FWW_1KMH';
cfg.kinesis.segment_map.FW_Speed_4       = 'FWW_4KMH';
cfg.kinesis.segment_map.Baseline_Speed_1 = 'BW_1KMH';
cfg.kinesis.segment_map.Baseline_Speed_4 = 'BW_4KMH';

cfg.kinesis.condition_labels = struct();
cfg.kinesis.condition_labels.N = 'normal';
cfg.kinesis.condition_labels.P = 'perturbation';

%% ------------------------------------------------------------------------
%  FEATURE-CONTROL / OVERFITTING SAFETY
%  ------------------------------------------------------------------------
cfg.feature_control = struct();
cfg.feature_control.warn_feature_to_sample_ratio = true;
cfg.feature_control.max_features_per_sample_ratio = 0.50;
cfg.feature_control.detect_zero_variance = true;
cfg.feature_control.detect_high_correlation = true;
cfg.feature_control.high_correlation_threshold = 0.95;
cfg.feature_control.detect_near_duplicates = true;

%% ------------------------------------------------------------------------
%  LOGGING
%  ------------------------------------------------------------------------
cfg.logging = struct();
cfg.logging.main_qc_log_file      = fullfile(cfg.paths.logs_root, 'qc_log_master.csv');
cfg.logging.warning_log_file      = fullfile(cfg.paths.logs_root, 'warning_log.csv');
cfg.logging.discovery_log_file    = fullfile(cfg.paths.logs_root, 'discovery_log.csv');
cfg.logging.missing_files_log     = fullfile(cfg.paths.logs_root, 'missing_files_log.csv');
cfg.logging.processing_error_log  = fullfile(cfg.paths.logs_root, 'processing_error_log.csv');

%% ------------------------------------------------------------------------
%  RUN ORDER (for run_preprocessing_stage1)
%  ------------------------------------------------------------------------
cfg.run_order = { ...
    'temp', ...
    'hr_live', ...
    'hrvrmssd_live', ...
    'nn_live', ...
    'bpmbxb_live', ...
    'acc', ...
    'angularrate', ...
    'movementacceleration_live', ...
    'stepcount_live', ...
    'press', ...
    'tempmean_live', ...
    'ecg', ...
    'metadata'};

%% ------------------------------------------------------------------------
%  CREATE ROOT OUTPUT FOLDERS IF MISSING
%  ------------------------------------------------------------------------
root_dirs = { ...
    cfg.paths.output_root, ...
    cfg.paths.logs_root, ...
    cfg.paths.features_root, ...
    cfg.paths.qc_root};

for i = 1:numel(root_dirs)
    if ~exist(root_dirs{i}, 'dir')
        mkdir(root_dirs{i});
    end
end

end