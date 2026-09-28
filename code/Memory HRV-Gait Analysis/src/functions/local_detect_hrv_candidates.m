function [candidates, missingCanonical, possibleOther] = local_detect_hrv_candidates(T)
%LOCAL_DETECT_HRV_CANDIDATES Detect common HRV candidate columns.
%
% General-purpose behavior:
% - Up to the caller's selection limit can be chosen (the runner uses 5).
% - If both raw and preprocessed versions of the same HRV metric exist, the
%   raw column is preferred.
% - If no raw version exists, an ln/log or already-z-standardized version
%   may still be offered instead of silently hiding that HRV metric.
% - InputScale records whether the selected source column appears raw,
%   log-transformed, z-standardized, or both. The runner uses this metadata
%   to avoid double transformation.

pool = ["meanHR", "RMSSD", "HF", "SDNN", "LF", "LF_HF_ratio", ...
        "SD1", "SD2", "pNN50", "TotalPower"];

varNames = string(T.Properties.VariableNames);
allCanonical = strings(0,1);
allColumns = strings(0,1);
allRules = strings(0,1);
allClasses = strings(0,1);
allScales = strings(0,1);
allPriority = zeros(0,1);
matchedAny = false(size(varNames));

for i = 1:numel(varNames)
    v = varNames(i);
    if ~local_is_numeric_like(T.(v))
        continue;
    end

    n = local_norm(v);
    [c, rule] = local_match_hrv(n);
    if strlength(c) == 0
        continue;
    end

    scale = local_input_scale(v);
    allCanonical(end+1,1) = c; %#ok<AGROW>
    allColumns(end+1,1) = v; %#ok<AGROW>
    allRules(end+1,1) = rule; %#ok<AGROW>
    allClasses(end+1,1) = string(class(T.(v))); %#ok<AGROW>
    allScales(end+1,1) = scale; %#ok<AGROW>
    allPriority(end+1,1) = local_scale_priority(scale); %#ok<AGROW>
    matchedAny(i) = true;
end

% Keep one source column per canonical HRV metric. Prefer raw, then logged,
% then already-z-standardized input. This prevents duplicate choices such as
% RMSSD_ecg + ln_RMSSD_ecg + z_RMSSD_ecg from appearing as three predictors.
canonical = strings(0,1);
columns = strings(0,1);
rules = strings(0,1);
classes = strings(0,1);
scales = strings(0,1);

for i = 1:numel(pool)
    idx = find(allCanonical == pool(i));
    if isempty(idx)
        continue;
    end
    [~, rel] = min(allPriority(idx));
    k = idx(rel);
    canonical(end+1,1) = allCanonical(k); %#ok<AGROW>
    columns(end+1,1) = allColumns(k); %#ok<AGROW>
    rules(end+1,1) = allRules(k); %#ok<AGROW>
    classes(end+1,1) = allClasses(k); %#ok<AGROW>
    scales(end+1,1) = allScales(k); %#ok<AGROW>
end

if isempty(columns)
    candidates = table([], strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
        'VariableNames', {'Index', 'CanonicalName', 'ColumnName', 'DetectionRule', 'ColumnClass', 'InputScale'});
else
    candidates = table((1:numel(columns))', canonical, columns, rules, classes, scales, ...
        'VariableNames', {'Index', 'CanonicalName', 'ColumnName', 'DetectionRule', 'ColumnClass', 'InputScale'});
end

foundCanonical = unique(candidates.CanonicalName, 'stable');
missingCanonical = setdiff(pool, foundCanonical, 'stable');

% Numeric HRV-like columns that did not match one of the predefined/common
% metrics are shown only as information, not silently auto-selected.
otherCols = strings(0,1);
for i = 1:numel(varNames)
    if matchedAny(i)
        continue;
    end
    v = varNames(i);
    n = local_norm(v);
    if local_is_numeric_like(T.(v)) && local_looks_hrv_like(n)
        otherCols(end+1,1) = v; %#ok<AGROW>
    end
end
possibleOther = table(otherCols, 'VariableNames', {'ColumnName'});
end

function [canonical, rule] = local_match_hrv(n)
    canonical = "";
    rule = "";

    % Check ratio before LF/HF to avoid misclassification.
    if contains(n, "lfhf") || contains(n, "lfhfratio") || contains(n, "lfhfpower") || contains(n, "lfhfratioecg")
        canonical = "LF_HF_ratio";
        rule = "LF/HF ratio alias";
        return;
    end

    if contains(n, "meanhr") || contains(n, "hrmean") || contains(n, "meanheartrate") || contains(n, "heartratemean")
        canonical = "meanHR";
        rule = "mean heart rate alias";
        return;
    end

    if contains(n, "rmssd")
        canonical = "RMSSD";
        rule = "RMSSD alias";
        return;
    end

    if contains(n, "sdnn")
        canonical = "SDNN";
        rule = "SDNN alias";
        return;
    end

    if contains(n, "pnn50") || contains(n, "pn50")
        canonical = "pNN50";
        rule = "pNN50 alias";
        return;
    end

    if contains(n, "totalpower") || contains(n, "totalpowerecg") || contains(n, "totalhrvpower")
        canonical = "TotalPower";
        rule = "total power alias";
        return;
    end

    if (strcmp(n, "hf") || strcmp(n, "hfecg") || strcmp(n, "hfpower") || strcmp(n, "hfpowerecg") || endsWith(n, "hfecg") || endsWith(n, "hfpower")) ...
            && ~contains(n, "hfnu") && ~contains(n, "lfhf")
        canonical = "HF";
        rule = "HF alias";
        return;
    end

    if (strcmp(n, "lf") || strcmp(n, "lfecg") || strcmp(n, "lfpower") || strcmp(n, "lfpowerecg") || endsWith(n, "lfecg") || endsWith(n, "lfpower")) ...
            && ~contains(n, "lfnu") && ~contains(n, "lfhf")
        canonical = "LF";
        rule = "LF alias";
        return;
    end

    if (strcmp(n, "sd1") || strcmp(n, "sd1ecg") || endsWith(n, "sd1ecg")) && ~contains(n, "sd10")
        canonical = "SD1";
        rule = "SD1 alias";
        return;
    end

    if (strcmp(n, "sd2") || strcmp(n, "sd2ecg") || endsWith(n, "sd2ecg")) && ~contains(n, "sd20")
        canonical = "SD2";
        rule = "SD2 alias";
        return;
    end
end

function scale = local_input_scale(v)
    s = lower(strtrim(string(v)));

    zPrefixes = ["z_", "zscore_", "standardized_", "standardised_", "std_"];
    zSuffixes = ["_z", "_zscore", "_standardized", "_standardised", "_std"];
    logPrefixes = ["ln_", "log_", "log10_"];
    logSuffixes = ["_ln", "_log", "_log10"];

    isZ = any(startsWith(s, zPrefixes)) || any(endsWith(s, zSuffixes));
    isLog = any(startsWith(s, logPrefixes)) || any(endsWith(s, logSuffixes)) || ...
            contains(s, "_ln_") || contains(s, "_log_") || contains(s, "_log10_");

    if isZ && isLog
        scale = "ln_z";
    elseif isZ
        scale = "z";
    elseif isLog
        scale = "ln";
    else
        scale = "raw";
    end
end

function p = local_scale_priority(scale)
    switch lower(char(scale))
        case 'raw'
            p = 1;
        case 'ln'
            p = 2;
        case 'z'
            p = 3;
        case 'ln_z'
            p = 4;
        otherwise
            p = 9;
    end
end

function tf = local_looks_hrv_like(n)
    keywords = ["ecg", "hrv", "heart", "rr", "nn", "bpm", "lfnu", "hfnu", "ibi", ...
                "rmssd", "sdnn", "pnn50", "totalpower", "lfhf", "sd1", "sd2"];
    tf = false;
    for k = 1:numel(keywords)
        if contains(n, keywords(k))
            tf = true;
            return;
        end
    end
end

function n = local_norm(s)
    n = lower(regexprep(char(s), '[^a-zA-Z0-9]', ''));
    n = string(n);
end

function tf = local_is_numeric_like(x)
    tf = isnumeric(x) || islogical(x);
end
