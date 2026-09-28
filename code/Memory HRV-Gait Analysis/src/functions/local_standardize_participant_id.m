function participantID = local_standardize_participant_id(x)
%LOCAL_STANDARDIZE_PARTICIPANT_ID Standardize participant identifiers safely.
%
% Safe normalization rules:
%   001, 1, 1.0              -> "1"
%   VP001, P001, Participant1,
%   Subject-01, ID_01        -> "1"
%
% More complex identifiers such as "Group1_P02" are preserved rather than
% reduced to their final numeric token, because doing so could merge distinct
% participants accidentally.

s = string(x);
s = strtrim(s);
participantID = strings(size(s));

for i = 1:numel(s)
    if ismissing(s(i)) || strlength(s(i)) == 0
        participantID(i) = missing;
        continue;
    end

    current = char(s(i));

    % Pure numeric-like IDs, including values imported as strings such as 001
    % or 1.0.
    if ~isempty(regexp(current, '^\d+(\.0+)?$', 'once'))
        numericValue = str2double(current);
        participantID(i) = string(round(numericValue));
        continue;
    end

    % Normalize only simple, recognized participant-prefix formats.
    tok = regexpi(current, '^(vp|p|participant|subject|subj|id)[\s_\-]*0*(\d+)$', 'tokens', 'once');
    if ~isempty(tok)
        participantID(i) = string(str2double(tok{2}));
        continue;
    end

    % Preserve complex/nonstandard IDs exactly apart from trim + uppercase.
    participantID(i) = upper(string(current));
end

participantID = reshape(participantID, size(s));
end
