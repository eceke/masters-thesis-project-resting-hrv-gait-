function [candidates, missingCanonical, possibleOther] = local_detect_gait_candidates(T)
%LOCAL_DETECT_GAIT_CANDIDATES Detect predefined raw gait candidate columns.
%
% Derived/transformed columns are excluded from automatic candidate
% detection. Unsupported gait metrics remain visible in possibleOther rather
% than being forced into the wrong canonical variable.

pool = ["Cadence", "AverageStrideLength", "AverageStanceTime", "AverageSwingTime", ...
        "AverageDoubleSupport", "AverageStrideTime", "AverageStepTime", ...
        "AverageSingleSupport", "StrideTimeVariability", "StepTimeVariability", ...
        "StanceTimeVariability", "SwingTimeVariability", "DoubleSupportVariability", ...
        "SymmetryScore", "VariabilityScore", "StepTimeAsymmetry", ...
        "StanceTimeAsymmetry", "SwingTimeAsymmetry"];

varNames = string(T.Properties.VariableNames);
canonical = strings(0, 1);
columns = strings(0, 1);
rules = strings(0, 1);
classes = strings(0, 1);
matchedCols = false(size(varNames));
ignoredDerived = false(size(varNames));

for i = 1:numel(varNames)
    v = varNames(i);
    n = local_norm(v);
    cls = string(class(T.(v)));

    if ~local_is_numeric_like(T.(v))
        continue;
    end

    if local_is_derived_name(v)
        ignoredDerived(i) = true;
        continue;
    end

    [c, rule] = local_match_gait(n);
    if strlength(c) > 0
        canonical(end+1, 1) = c; %#ok<AGROW>
        columns(end+1, 1) = v; %#ok<AGROW>
        rules(end+1, 1) = rule; %#ok<AGROW>
        classes(end+1, 1) = cls; %#ok<AGROW>
        matchedCols(i) = true;
    end
end

if isempty(columns)
    candidates = table([], strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
        'VariableNames', {'Index', 'CanonicalName', 'ColumnName', 'DetectionRule', 'ColumnClass'});
else
    candidates = table((1:numel(columns))', canonical, columns, rules, classes, ...
        'VariableNames', {'Index', 'CanonicalName', 'ColumnName', 'DetectionRule', 'ColumnClass'});
end

foundCanonical = unique(candidates.CanonicalName, 'stable');
missingCanonical = setdiff(pool, foundCanonical, 'stable');

otherCols = strings(0, 1);
for i = 1:numel(varNames)
    if matchedCols(i) || ignoredDerived(i)
        continue;
    end
    v = varNames(i);
    n = local_norm(v);
    if local_is_numeric_like(T.(v)) && local_looks_gait_like(n)
        otherCols(end+1, 1) = v; %#ok<AGROW>
    end
end
possibleOther = table(otherCols, 'VariableNames', {'ColumnName'});
end

function [canonical, rule] = local_match_gait(n)
    canonical = "";
    rule = "";

    if strcmp(n, "cadence") || endsWith(n, "cadence")
        canonical = "Cadence";
        rule = "cadence alias";
        return;
    end

    if contains(n, "stridelength") && ~contains(n, "variability") && ~contains(n, "asymmetry")
        canonical = "AverageStrideLength";
        rule = "stride length alias";
        return;
    end

    if contains(n, "stancetime") && contains(n, "variability")
        canonical = "StanceTimeVariability";
        rule = "stance time variability alias";
        return;
    end

    if contains(n, "swingtime") && contains(n, "variability")
        canonical = "SwingTimeVariability";
        rule = "swing time variability alias";
        return;
    end

    if contains(n, "stridetime") && contains(n, "variability")
        canonical = "StrideTimeVariability";
        rule = "stride time variability alias";
        return;
    end

    if contains(n, "steptime") && contains(n, "variability")
        canonical = "StepTimeVariability";
        rule = "step time variability alias";
        return;
    end

    if contains(n, "doublesupport") && contains(n, "variability")
        canonical = "DoubleSupportVariability";
        rule = "double support variability alias";
        return;
    end

    if contains(n, "stancetime") && contains(n, "asymmetry")
        canonical = "StanceTimeAsymmetry";
        rule = "stance time asymmetry alias";
        return;
    end

    if contains(n, "swingtime") && contains(n, "asymmetry")
        canonical = "SwingTimeAsymmetry";
        rule = "swing time asymmetry alias";
        return;
    end

    if contains(n, "steptime") && contains(n, "asymmetry")
        canonical = "StepTimeAsymmetry";
        rule = "step time asymmetry alias";
        return;
    end

    % Average-type variables explicitly exclude variability and asymmetry so
    % unsupported metrics such as StrideTimeAsymmetry cannot be misclassified.
    if contains(n, "stancetime") && ~contains(n, "variability") && ~contains(n, "asymmetry")
        canonical = "AverageStanceTime";
        rule = "stance time alias";
        return;
    end

    if contains(n, "swingtime") && ~contains(n, "variability") && ~contains(n, "asymmetry")
        canonical = "AverageSwingTime";
        rule = "swing time alias";
        return;
    end

    if contains(n, "doublesupport") && ~contains(n, "variability") && ~contains(n, "asymmetry")
        canonical = "AverageDoubleSupport";
        rule = "double support alias";
        return;
    end

    if contains(n, "stridetime") && ~contains(n, "variability") && ~contains(n, "asymmetry")
        canonical = "AverageStrideTime";
        rule = "stride time alias";
        return;
    end

    if contains(n, "steptime") && ~contains(n, "variability") && ~contains(n, "asymmetry")
        canonical = "AverageStepTime";
        rule = "step time alias";
        return;
    end

    if contains(n, "singlesupport") && ~contains(n, "variability") && ~contains(n, "asymmetry")
        canonical = "AverageSingleSupport";
        rule = "single support alias";
        return;
    end

    if contains(n, "symmetryindex") || contains(n, "symmetryscore")
        canonical = "SymmetryScore";
        rule = "symmetry alias";
        return;
    end

    if contains(n, "variabilityscore")
        canonical = "VariabilityScore";
        rule = "variability score alias";
        return;
    end
end

function tf = local_is_derived_name(v)
    s = lower(strtrim(string(v)));
    prefixes = ["z_", "zscore_", "standardized_", "standardised_", "std_", ...
                "ln_", "log_", "log10_", "sqrt_"];
    suffixes = ["_z", "_zscore", "_standardized", "_standardised", "_std", ...
                "_ln", "_log", "_log10", "_sqrt"];
    n = lower(regexprep(char(s), '[^a-zA-Z0-9]', ''));
    n = string(n);
    compactPrefixes = ["zscore", "standardized", "standardised", "std", "ln", "log10", "log", "sqrt"];
    compactSuffixes = ["zscore", "standardized", "standardised", "ln", "log10", "log", "sqrt"];
    tf = any(startsWith(s, prefixes)) || any(endsWith(s, suffixes)) || ...
         any(startsWith(n, compactPrefixes)) || any(endsWith(n, compactSuffixes));
end

function tf = local_looks_gait_like(n)
    keywords = ["gait", "stride", "stance", "swing", "step", "support", "symmetry", "asymmetry", "cadence", "kinesis"];
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
