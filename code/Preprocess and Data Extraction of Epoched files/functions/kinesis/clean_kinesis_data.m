function out = clean_kinesis_data(cfg, kinesis_loaded)
%CLEAN_KINESIS_DATA Validate and reshape Kinesis gait data.
%
% This function does not aggressively clean because Kinesis data is already
% aggregated. It mainly:
%   - maps PatientID to participant_id
%   - preserves Condition as N/P
%   - maps Task + Speed to segment_name
%   - checks duplicates
%   - checks participant-level condition consistency
%   - selects gait features for later merging

if nargin < 2
    error('clean_kinesis_data:MissingInputs', ...
        'Both cfg and kinesis_loaded are required.');
end

T = kinesis_loaded.raw_table;

out = struct();
out.cleaned_table = table();
out.participant_condition_table = table();
out.qc = struct();
out.warnings = {};

%% Required columns
required_cols = {'PatientID','Condition','Task','Speed'};

for i = 1:numel(required_cols)
    if ~ismember(required_cols{i}, T.Properties.VariableNames)
        error('clean_kinesis_data:MissingColumn', ...
            'Required Kinesis column missing: %s', required_cols{i});
    end
end

%% Participant ID
patient_id_num = T.PatientID;

if ~isnumeric(patient_id_num)
    patient_id_num = str2double(string(patient_id_num));
end

participant_id = strcat("VP", string(patient_id_num));

%% Condition
condition = upper(strtrim(string(T.Condition)));

invalid_condition = ~(condition == "N" | condition == "P");

if any(invalid_condition)
    out.warnings{end+1} = sprintf( ...
        'Invalid Condition values found in %d rows.', ...
        sum(invalid_condition));
end

%% Task and speed
task = strtrim(string(T.Task));
speed = T.Speed;

if ~isnumeric(speed)
    speed = str2double(string(speed));
end

segment_name = strings(height(T), 1);
segment_name(task == "FW" & speed == 1) = "FWW_1KMH";
segment_name(task == "FW" & speed == 4) = "FWW_4KMH";
segment_name(task == "Baseline" & speed == 1) = "BW_1KMH";
segment_name(task == "Baseline" & speed == 4) = "BW_4KMH";

unmapped_segment = segment_name == "";

if any(unmapped_segment)
    out.warnings{end+1} = sprintf( ...
        'Could not map Task+Speed to segment_name in %d rows.', ...
        sum(unmapped_segment));
end

%% Build cleaned table with metadata
C = table();
C.participant_id = cellstr(participant_id);
C.kinesis_condition = cellstr(condition);
C.segment_name = cellstr(segment_name);
C.kinesis_task = cellstr(task);
C.kinesis_speed = speed;

%% Select available gait feature columns
feature_cols = { ...
    'Cadence_steps_min_', ...
    'AverageStrideLength_cm_', ...
    'AverageStrideVelocity_cm_s_', ...
    'AverageStrideTime_s_', ...
    'AverageStepTime_s_', ...
    'AverageStanceTime_s_', ...
    'AverageSwingTime_s_', ...
    'AverageSingleSupport', ...
    'AverageDoubleSupport', ...
    'WalkTime_s_', ...
    'DistanceTravelled_m_', ...
    'StrideVelocityVariability___', ...
    'StrideLengthVariability___', ...
    'StrideTimeVariability___', ...
    'StepTimeVariability___', ...
    'StanceTimeVariability___', ...
    'SwingTimeVariability___', ...
    'SingleSupportVariability___', ...
    'DoubleSupportVariability___', ...
    'StrideTimeAsymmetry___', ...
    'StepTimeAsymmetry___', ...
    'StanceTimeAsymmetry___', ...
    'SwingTimeAsymmetry___', ...
    'StrideLengthAsymmetry___', ...
    'StrideVelocityAsymmetry___', ...
    'SpeedScore___', ...
    'VariabilityScore___', ...
    'SymmetryScore___', ...
    'NumberOfGaitCycles', ...
    'NumberOfSteps'};

available_features = feature_cols(ismember(feature_cols, T.Properties.VariableNames));
missing_features = feature_cols(~ismember(feature_cols, T.Properties.VariableNames));

if ~isempty(missing_features)
    out.warnings{end+1} = sprintf( ...
        'Some expected Kinesis feature columns are missing: %s', ...
        strjoin(missing_features, ', '));
end

for i = 1:numel(available_features)
    original_name = available_features{i};
    new_name = ['kinesis_' original_name];

    C.(new_name) = T.(original_name);
end

%% Remove unmapped rows from cleaned analysis table
% We do not delete them silently; warnings above preserve the issue.
C_clean = C(~unmapped_segment & ~invalid_condition, :);

%% Participant-level condition table
[G, pid] = findgroups(C_clean.participant_id);
condition_per_participant = splitapply(@(x) {unique(x)}, C_clean.kinesis_condition, G);

condition_warning = false(numel(pid), 1);
condition_value = cell(numel(pid), 1);

for i = 1:numel(pid)
    vals = condition_per_participant{i};

    if numel(vals) ~= 1
        condition_warning(i) = true;
        condition_value{i} = strjoin(vals, '|');
    else
        condition_value{i} = vals{1};
    end
end

PCT = table();
PCT.participant_id = pid;
PCT.kinesis_condition = condition_value;
PCT.has_multiple_conditions = condition_warning;

if any(condition_warning)
    out.warnings{end+1} = sprintf( ...
        'Some participants have multiple Condition values: %s', ...
        strjoin(pid(condition_warning), ', '));
end

out.participant_condition_table = PCT;

%% Duplicate check
key_table = C_clean(:, {'participant_id','kinesis_condition','segment_name'});
[~, unique_idx] = unique(key_table, 'rows', 'stable');

duplicate_mask = true(height(C_clean), 1);
duplicate_mask(unique_idx) = false;

C_clean.is_duplicate_kinesis_key = duplicate_mask;

if any(duplicate_mask)
    out.warnings{end+1} = sprintf( ...
        'Duplicate Kinesis participant-condition-segment rows found: %d rows.', ...
        sum(duplicate_mask));
end

%% Missingness summary
feature_missing_fraction = struct();

for i = 1:numel(available_features)
    col = ['kinesis_' available_features{i}];

    if isnumeric(C_clean.(col))
        feature_missing_fraction.(col) = mean(isnan(C_clean.(col)));
    else
        feature_missing_fraction.(col) = mean(ismissing(C_clean.(col)));
    end
end

%% QC
out.qc = struct();
out.qc.n_raw_rows = height(T);
out.qc.n_clean_rows = height(C_clean);
out.qc.n_participants = numel(unique(C_clean.participant_id));
out.qc.n_conditions_N = sum(strcmp(C_clean.kinesis_condition, 'N'));
out.qc.n_conditions_P = sum(strcmp(C_clean.kinesis_condition, 'P'));
out.qc.n_unmapped_rows = sum(unmapped_segment);
out.qc.n_invalid_condition_rows = sum(invalid_condition);
out.qc.n_duplicate_rows = sum(duplicate_mask);
out.qc.available_feature_count = numel(available_features);
out.qc.missing_feature_count = numel(missing_features);
out.qc.feature_missing_fraction = feature_missing_fraction;
out.qc.warning_messages = strjoin(out.warnings, ' | ');

out.cleaned_table = C_clean;

end