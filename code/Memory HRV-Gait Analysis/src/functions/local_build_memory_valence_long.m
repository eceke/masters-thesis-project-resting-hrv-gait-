function [valenceLong, qcValence] = local_build_memory_valence_long(mergedData, memoryData, positivePresented, negativePresented, neutralPresented, includePerturbation, selectedHRV, selectedGait)
%LOCAL_BUILD_MEMORY_VALENCE_LONG Build long-format valence recall table.
% The output has one row per mergedData row per valence category:
%   Positive, Negative, Neutral.
%
% Two denominators are provided for downstream modeling/reporting:
%   - valence_presented / valence_recall_rate
%       "Of the words presented in this valence category, how many were
%       recalled?" (the original, presented-word-based analysis).
%   - valence_total_correct / valence_share_of_correct
%       "Of everything this participant correctly recalled in this
%       administration, what share fell in this valence category?"
%       valence_total_correct is simply the row's Correct value
%       (Positive+Negative+Neutral), repeated across the 3 valence rows
%       of that administration. Where Correct == 0 for an administration,
%       valence_share_of_correct is NaN by construction (0/0).

selectedHRV = string(selectedHRV);
selectedGait = string(selectedGait);
selectedPredictors = unique([selectedHRV(:); selectedGait(:)], 'stable');

positivePresented = double(positivePresented);
negativePresented = double(negativePresented);
neutralPresented = double(neutralPresented);

qcMetric = strings(0,1);
qcValue = strings(0,1);
qcSeverity = strings(0,1);
qcDetails = strings(0,1);

    function addQC(metric, value, severity, details)
        qcMetric(end+1,1) = string(metric); %#ok<AGROW>
        qcValue(end+1,1) = string(value); %#ok<AGROW>
        qcSeverity(end+1,1) = string(severity); %#ok<AGROW>
        qcDetails(end+1,1) = string(details); %#ok<AGROW>
    end

%% Validate presented counts
if ~isfinite(positivePresented) || positivePresented <= 0 || abs(positivePresented - round(positivePresented)) > sqrt(eps)
    error('Positive presented count must be a positive integer.');
end
if ~isfinite(negativePresented) || negativePresented <= 0 || abs(negativePresented - round(negativePresented)) > sqrt(eps)
    error('Negative presented count must be a positive integer.');
end
if ~isfinite(neutralPresented) || neutralPresented <= 0 || abs(neutralPresented - round(neutralPresented)) > sqrt(eps)
    error('Neutral presented count must be a positive integer.');
end

positivePresented = round(positivePresented);
negativePresented = round(negativePresented);
neutralPresented = round(neutralPresented);

addQC('valence_positive_presented', positivePresented, 'INFO', 'Number of positive words presented, provided by user.');
addQC('valence_negative_presented', negativePresented, 'INFO', 'Number of negative words presented, provided by user.');
addQC('valence_neutral_presented', neutralPresented, 'INFO', 'Number of neutral words presented, provided by user.');
addQC('valence_total_presented', positivePresented + negativePresented + neutralPresented, 'INFO', 'Sum of valence-specific presented counts.');

%% Validate required columns
requiredMerged = ["participant_id", "speed", "memory_speed_label", "walk_segment", "rest_condition"];
missingMerged = setdiff(requiredMerged, string(mergedData.Properties.VariableNames), 'stable');
if ~isempty(missingMerged)
    error('mergedData is missing required column(s): %s', strjoin(missingMerged, ', '));
end

M = memoryData;
requiredMemory = ["participant_id", "memory_speed_label", "walk_segment", "Positive", "Negative", "Neutral", "Correct"];
missingMemory = setdiff(requiredMemory, string(M.Properties.VariableNames), 'stable');
if ~isempty(missingMemory)
    error('Memory tables are missing required valence column(s): %s', strjoin(missingMemory, ', '));
end

M.participant_id = string(M.participant_id);
M.memory_speed_label = string(M.memory_speed_label);
M.walk_segment = upper(string(M.walk_segment));
M.Positive = double(M.Positive);
M.Negative = double(M.Negative);
M.Neutral = double(M.Neutral);
M.Correct = double(M.Correct);

valenceSumMismatch = sum((M.Positive + M.Negative + M.Neutral) ~= M.Correct);
if valenceSumMismatch > 0
    addQC('valence_positive_negative_neutral_not_equal_correct_rows', valenceSumMismatch, 'WARNING', 'Positive + Negative + Neutral does not equal Correct for some memory rows. These rows can make valence_share_of_correct exceed 1 for the affected administration; such rows are dropped automatically by the GLMM fit (success > denominator is treated as incomplete data), but are kept as-is in the long-format CSV for transparency.');
else
    addQC('valence_positive_negative_neutral_not_equal_correct_rows', 0, 'OK', 'Positive + Negative + Neutral equals Correct for all memory rows.');
end

badPositive = sum(M.Positive > positivePresented | M.Positive < 0 | isnan(M.Positive));
badNegative = sum(M.Negative > negativePresented | M.Negative < 0 | isnan(M.Negative));
badNeutral = sum(M.Neutral > neutralPresented | M.Neutral < 0 | isnan(M.Neutral));
addQC('valence_positive_count_invalid_rows', badPositive, local_ok_or_error(badPositive), 'Rows where Positive is negative, missing, or greater than Positive_Presented.');
addQC('valence_negative_count_invalid_rows', badNegative, local_ok_or_error(badNegative), 'Rows where Negative is negative, missing, or greater than Negative_Presented.');
addQC('valence_neutral_count_invalid_rows', badNeutral, local_ok_or_error(badNeutral), 'Rows where Neutral is negative, missing, or greater than Neutral_Presented.');

%% Add valence counts to merged data
keys = {'participant_id', 'memory_speed_label', 'walk_segment'};
Mvals = M(:, [keys, {'Positive', 'Negative', 'Neutral', 'Correct'}]);
% Rename the memory-count columns before joining. mergedData may already
% contain a variable named Correct from the base memory-HRV-gait table;
% if we join another Correct column without renaming, MATLAB disambiguates
% the duplicate names and mergedPlus.Correct no longer exists.
Mvals.Properties.VariableNames(end-3:end) = { ...
    'memory_positive_correct', ...
    'memory_negative_correct', ...
    'memory_neutral_correct', ...
    'memory_total_correct'};
Mvals = unique(Mvals, 'rows', 'stable');
mergedPlus = innerjoin(mergedData, Mvals, 'Keys', keys);

requiredJoined = ["memory_positive_correct", "memory_negative_correct", "memory_neutral_correct", "memory_total_correct"];
missingJoined = setdiff(requiredJoined, string(mergedPlus.Properties.VariableNames), 'stable');
if ~isempty(missingJoined)
    error('Joined table is missing required memory count column(s): %s', strjoin(missingJoined, ', '));
end

if height(mergedPlus) ~= height(mergedData)
    addQC('valence_join_row_mismatch', height(mergedData) - height(mergedPlus), 'WARNING', 'Some merged rows could not be joined with valence memory counts.');
else
    addQC('valence_join_row_mismatch', 0, 'OK', 'All merged rows were joined with valence memory counts.');
end

zeroTotalCorrectAdmins = sum(mergedPlus.memory_total_correct == 0);
addQC('valence_zero_total_correct_administrations', zeroTotalCorrectAdmins, 'INFO', 'Administrations where Correct == 0 (participant recalled nothing). valence_share_of_correct is NaN (0/0) for these rows and they are excluded from any share-of-correct GLMM by construction.');

%% Build long table
baseCols = ["participant_id", "speed", "memory_speed_label", "walk_segment", "rest_condition"];
if includePerturbation && ismember('perturbation_group', mergedPlus.Properties.VariableNames)
    baseCols = [baseCols, "perturbation_group"];
end

zNames = strings(0,1);
for i = 1:numel(selectedPredictors)
    zNames(end+1,1) = string(matlab.lang.makeValidName("z_" + selectedPredictors(i))); %#ok<AGROW>
end
predictorCols = unique([selectedPredictors(:); zNames(:)], 'stable');
predictorCols = predictorCols(ismember(predictorCols, string(mergedPlus.Properties.VariableNames)));

baseCols = unique([baseCols(:); predictorCols(:)], 'stable');
baseCols = baseCols(ismember(baseCols, string(mergedPlus.Properties.VariableNames)));
base = mergedPlus(:, cellstr(baseCols));

% Total correct (Correct) is identical across the 3 valence rows of a
% given administration; carry it through once here so it is available
% to all three before the split.
totalCorrectCol = double(mergedPlus.memory_total_correct);

Tpos = base;
Tpos.valence = repmat("Positive", height(base), 1);
Tpos.valence_correct = double(mergedPlus.memory_positive_correct);
Tpos.valence_presented = repmat(positivePresented, height(base), 1);
Tpos.valence_total_correct = totalCorrectCol;

Tneg = base;
Tneg.valence = repmat("Negative", height(base), 1);
Tneg.valence_correct = double(mergedPlus.memory_negative_correct);
Tneg.valence_presented = repmat(negativePresented, height(base), 1);
Tneg.valence_total_correct = totalCorrectCol;

Tneu = base;
Tneu.valence = repmat("Neutral", height(base), 1);
Tneu.valence_correct = double(mergedPlus.memory_neutral_correct);
Tneu.valence_presented = repmat(neutralPresented, height(base), 1);
Tneu.valence_total_correct = totalCorrectCol;

valenceLong = [Tpos; Tneg; Tneu];
valenceLong.valence = categorical(string(valenceLong.valence), ["Neutral", "Positive", "Negative"]);

% Presented-word-based recall rate.
valenceLong.valence_recall_rate = double(valenceLong.valence_correct) ./ double(valenceLong.valence_presented);

% Share-of-correct: of what was correctly recalled, what share was
% this valence category. 0/0 -> NaN automatically in MATLAB (no error).
valenceLong.valence_share_of_correct = double(valenceLong.valence_correct) ./ double(valenceLong.valence_total_correct);

% Put key columns first in a stable order.
frontCols = ["participant_id", "speed", "memory_speed_label", "walk_segment", "rest_condition"];
if includePerturbation && ismember('perturbation_group', valenceLong.Properties.VariableNames)
    frontCols = [frontCols, "perturbation_group"];
end
frontCols = [frontCols, "valence", "valence_correct", ...
    "valence_presented", "valence_recall_rate", ...
    "valence_total_correct", "valence_share_of_correct"];
allCols = string(valenceLong.Properties.VariableNames);
remainingCols = setdiff(allCols, frontCols, 'stable');
finalCols = [frontCols(ismember(frontCols, allCols)), remainingCols];
valenceLong = valenceLong(:, cellstr(finalCols));

addQC('valence_long_rows_total', height(valenceLong), 'INFO', 'Rows in valence-long table. Expected merged rows x 3.');
addQC('valence_long_participants_total', numel(unique(string(valenceLong.participant_id))), 'INFO', 'Unique participants in valence-long table.');
addQC('valence_long_categories', strjoin(string(categories(valenceLong.valence)), ', '), 'INFO', 'Valence categories in long table.');

invalidLong = sum(valenceLong.valence_correct < 0 | valenceLong.valence_correct > valenceLong.valence_presented | isnan(valenceLong.valence_correct));
addQC('valence_long_invalid_success_rows', invalidLong, local_ok_or_error(invalidLong), 'Rows where valence_correct is invalid relative to valence_presented.');

invalidShare = sum(valenceLong.valence_correct > valenceLong.valence_total_correct);
addQC('valence_share_of_correct_invalid_rows', invalidShare, local_ok_or_warning(invalidShare), 'Rows where valence_correct exceeds valence_total_correct (would make valence_share_of_correct > 1); these come from Positive+Negative+Neutral ~= Correct mismatches and are excluded automatically from share-of-correct GLMMs.');

qcValence = table(qcMetric, qcValue, qcSeverity, qcDetails, ...
    'VariableNames', {'metric', 'value', 'severity', 'details'});
end

function severity = local_ok_or_error(n)
    if n == 0
        severity = 'OK';
    else
        severity = 'ERROR';
    end
end

function severity = local_ok_or_warning(n)
    if n == 0
        severity = 'OK';
    else
        severity = 'WARNING';
    end
end
