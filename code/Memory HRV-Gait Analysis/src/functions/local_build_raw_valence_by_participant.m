function rawByParticipant = local_build_raw_valence_by_participant(memoryData, positivePresented, negativePresented, neutralPresented)
%LOCAL_BUILD_RAW_VALENCE_BY_PARTICIPANT Simple per-participant raw valence recall rates.
%
% This is a descriptive (non-modeled) summary, independent of the
% HRV-gait merge: for each participant it sums Positive / Negative /
% Neutral / Correct recall counts across all available memory
% administrations and reports two kinds of ratio:
%
%   1) *_Rate  = valence-specific correct / valence-specific presented
%   2) *_Share = valence-specific correct / total correct

positivePresented = double(positivePresented);
negativePresented = double(negativePresented);
neutralPresented = double(neutralPresented);
totalPresentedPerAdmin = positivePresented + negativePresented + neutralPresented;

M = memoryData;
M.participant_id = string(M.participant_id);
M.Positive = double(M.Positive);
M.Negative = double(M.Negative);
M.Neutral = double(M.Neutral);
M.Correct = double(M.Correct);

G = groupsummary(M, 'participant_id', 'sum', {'Positive', 'Negative', 'Neutral', 'Correct'});

% Sort participants numerically when participant_id is numeric-like, falling back to plain string sort otherwise.
pid = string(G.participant_id);
numericIDs = str2double(pid);
if all(~isnan(numericIDs))
    [~, sortIdx] = sort(numericIDs);
else
    [~, sortIdx] = sort(pid);
end
G = G(sortIdx, :);

nAdmins = G.GroupCount;

Positive_Presented = nAdmins * positivePresented;
Negative_Presented = nAdmins * negativePresented;
Neutral_Presented = nAdmins * neutralPresented;
Total_Presented = nAdmins * totalPresentedPerAdmin;

Positive_Correct = G.sum_Positive;
Negative_Correct = G.sum_Negative;
Neutral_Correct = G.sum_Neutral;
Total_Correct = G.sum_Correct;

Positive_Rate = Positive_Correct ./ Positive_Presented;
Negative_Rate = Negative_Correct ./ Negative_Presented;
Neutral_Rate = Neutral_Correct ./ Neutral_Presented;
Correct_Rate = Total_Correct ./ Total_Presented;

% Share-of-correct: composition of what was actually recalled. NaN
% (0/0) for participants with Total_Correct == 0; MATLAB returns NaN
% here without raising an error, so no special-casing is required.
Positive_Share = Positive_Correct ./ Total_Correct;
Negative_Share = Negative_Correct ./ Total_Correct;
Neutral_Share = Neutral_Correct ./ Total_Correct;

rawByParticipant = table(string(G.participant_id), nAdmins, ...
    Positive_Correct, Positive_Presented, Positive_Rate, Positive_Share, ...
    Negative_Correct, Negative_Presented, Negative_Rate, Negative_Share, ...
    Neutral_Correct, Neutral_Presented, Neutral_Rate, Neutral_Share, ...
    Total_Correct, Total_Presented, Correct_Rate, ...
    'VariableNames', {'participant_id', 'n_administrations', ...
    'Positive_Correct', 'Positive_Presented', 'Positive_Rate', 'Positive_Share', ...
    'Negative_Correct', 'Negative_Presented', 'Negative_Rate', 'Negative_Share', ...
    'Neutral_Correct', 'Neutral_Presented', 'Neutral_Rate', 'Neutral_Share', ...
    'Total_Correct', 'Total_Presented', 'Correct_Rate'});

% Most participants are expected to have one administration per selected memory speed. Flag anyone who doesn't, since their rates are still computed correctly but are based on partial data.
expectedAdmins = numel(unique(string(M.walk_segment)));
if any(nAdmins ~= expectedAdmins)
    oddOnes = rawByParticipant.participant_id(nAdmins ~= expectedAdmins);
    warning('local_build_raw_valence_by_participant:partialData', ...
        'These participants do not have exactly %d memory administration(s): %s', ...
        expectedAdmins, strjoin(oddOnes, ', '));
end
end
