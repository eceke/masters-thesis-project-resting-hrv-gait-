function R = local_fit_binomial_glmm(data, outcomeType, successVar, denominatorVar, modelFamily, hrvPredictor, gaitPredictor, includePerturbation, restConditionLabel, skipReason)
%LOCAL_FIT_BINOMIAL_GLMM Fit one binomial GLMM safely.
%
% For HRV-Gait models, the function returns one row for the HRV effect
% and one row for the gait effect from the same fitted model.

if nargin < 10
    skipReason = "";
end

outcomeType = string(outcomeType);
successVar = string(successVar);
denominatorVar = string(denominatorVar);
modelFamily = string(modelFamily);
hrvPredictor = string(hrvPredictor);
gaitPredictor = string(gaitPredictor);
restConditionLabel = string(restConditionLabel);
skipReason = string(skipReason);
speedActuallyIncluded = true;

% Convert legacy dataset inputs to tables before accessing variable names.
% This keeps the function compatible with older MATLAB workflows.
if isa(data, 'dataset')
    data = dataset2table(data);
elseif ~istable(data)
    try
        data = table(data);
    catch
        % leave as-is; downstream height/isempty checks will catch it
    end
end

if strlength(skipReason) > 0
    R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
        "model", "model", speedActuallyIncluded, includePerturbation, 0, 0, ...
        NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
        false, skipReason, "");
    return;
end

if exist('fitglme', 'file') ~= 2
    R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
        "model", "model", speedActuallyIncluded, includePerturbation, 0, 0, ...
        NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
        false, "fitglme was not found. The Statistics and Machine Learning Toolbox is required.", "");
    return;
end

try
    if isempty(data) || height(data) == 0
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, includePerturbation, 0, 0, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "No rows available for this model.", "");
        return;
    end

    predictorTerms = strings(0,1);
    effectPredictors = strings(0,1);
    effectTypes = strings(0,1);

    if strlength(hrvPredictor) > 0
        zHrv = string(matlab.lang.makeValidName("z_" + hrvPredictor));
        predictorTerms(end+1,1) = zHrv; %#ok<AGROW>
        effectPredictors(end+1,1) = hrvPredictor; %#ok<AGROW>
        effectTypes(end+1,1) = "HRV"; %#ok<AGROW>
    end

    if strlength(gaitPredictor) > 0
        zGait = string(matlab.lang.makeValidName("z_" + gaitPredictor));
        predictorTerms(end+1,1) = zGait; %#ok<AGROW>
        effectPredictors(end+1,1) = gaitPredictor; %#ok<AGROW>
        effectTypes(end+1,1) = "Gait"; %#ok<AGROW>
    end

    if isempty(predictorTerms)
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, includePerturbation, 0, 0, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "No HRV or gait predictor was provided for this model.", "");
        return;
    end

    needed = [successVar, denominatorVar, predictorTerms(:).', "speed", "participant_id"];
    perturbationActuallyIncluded = false;
    if includePerturbation
        if ~ismember('perturbation_group', data.Properties.VariableNames)
            R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                "model", "model", speedActuallyIncluded, false, 0, 0, ...
                NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                false, "Perturbation/group was requested but perturbation_group is missing from the model data.", "");
            return;
        end
        needed = [needed, "perturbation_group"];
        perturbationActuallyIncluded = true;
    end

    missingVars = setdiff(needed, string(data.Properties.VariableNames), 'stable');
    if ~isempty(missingVars)
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, includePerturbation, 0, 0, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Missing required model variable(s): " + strjoin(missingVars, ', '), "");
        return;
    end

    T = data(:, cellstr(unique(needed, 'stable')));

    T.(successVar) = double(T.(successVar));
    T.(denominatorVar) = double(T.(denominatorVar));

    for i = 1:numel(predictorTerms)
        T.(predictorTerms(i)) = double(T.(predictorTerms(i)));
    end

    % Preserve numeric speed ordering so the lowest observed speed is the
    % reference level when >=2 speeds are modeled.
    T.speed = local_speed_categorical(T.speed);
    T.participant_id = categorical(string(T.participant_id));

    if perturbationActuallyIncluded
        T.perturbation_group = local_group_categorical(T.perturbation_group);
    end

    complete = true(height(T), 1);
    complete = complete & ~isnan(T.(successVar));
    complete = complete & ~isnan(T.(denominatorVar));
    complete = complete & T.(denominatorVar) > 0;
    complete = complete & T.(successVar) >= 0;
    complete = complete & T.(successVar) <= T.(denominatorVar);
    complete = complete & ~isundefined(T.speed);
    complete = complete & ~isundefined(T.participant_id);
    for i = 1:numel(predictorTerms)
        complete = complete & ~isnan(T.(predictorTerms(i)));
    end
    if perturbationActuallyIncluded
        complete = complete & ~isundefined(T.perturbation_group);
    end

    T = T(complete, :);
    nRows = height(T);
    nParticipants = numel(categories(removecats(T.participant_id)));
    nSpeedLevels = numel(categories(removecats(T.speed)));
    speedActuallyIncluded = nSpeedLevels >= 2;

    % Re-check perturbation levels after complete-case filtering. Missing
    % predictor/outcome rows can otherwise reduce a previously two-level
    % group variable to a single observed level inside this exact model.
    if perturbationActuallyIncluded
        nPertLevels = numel(categories(removecats(T.perturbation_group)));
        if nPertLevels < 2
            R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                "model", "model", speedActuallyIncluded, true, nParticipants, nRows, ...
                NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                false, "Perturbation/group variable has fewer than 2 observed levels after complete-case filtering.", "");
            return;
        end
    end

    fitFormula = local_build_fit_formula(predictorTerms, perturbationActuallyIncluded, speedActuallyIncluded);
    reportFormula = local_build_report_formula(successVar, denominatorVar, predictorTerms, perturbationActuallyIncluded, speedActuallyIncluded);

    if nRows < 8
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Fewer than 8 complete rows are available for this model.", reportFormula);
        return;
    end

    if nParticipants < 2
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Fewer than 2 participants are available for random intercept modeling.", reportFormula);
        return;
    end

    if all(T.(successVar) == 0) || all(T.(successVar) == T.(denominatorVar))
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Outcome has no binomial variation in this subset.", reportFormula);
        return;
    end

    prop = T.(successVar) ./ T.(denominatorVar);
    if numel(unique(prop)) < 2
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Outcome proportion has fewer than 2 unique values in this subset.", reportFormula);
        return;
    end

    for i = 1:numel(predictorTerms)
        sdVal = std(T.(predictorTerms(i)), 'omitnan');
        if ~isfinite(sdVal) || sdVal == 0
            R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
                NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                false, "Predictor standard deviation is zero or non-finite after filtering: " + predictorTerms(i), reportFormula);
            return;
        end
    end

    % For grouped binomial data in fitglme, use the number of successes as the response and provide the number of trials through BinomialSize.
    % Do NOT use the response proportion here; MATLAB checks that the response contains integer binomial counts.
    T.model_response = double(T.(successVar));
    binomialSizeVector = double(T.(denominatorVar));
    binomialSizeVector = binomialSizeVector(:);

    if numel(binomialSizeVector) ~= height(T) || any(~isfinite(binomialSizeVector)) || ...
            any(binomialSizeVector <= 0) || any(abs(binomialSizeVector - round(binomialSizeVector)) > sqrt(eps))
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Binomial denominator must be a positive integer vector with one value per model row.", reportFormula);
        return;
    end

    successVector = double(T.(successVar));
    if any(~isfinite(successVector)) || any(successVector < 0) || ...
            any(successVector > binomialSizeVector) || ...
            any(abs(successVector - round(successVector)) > sqrt(eps))
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Binomial success count must be an integer between 0 and the denominator for every model row.", reportFormula);
        return;
    end

    lastwarn('');
    mdl = fitglme(T, char(fitFormula), ...
        'Distribution', 'Binomial', ...
        'Link', 'logit', ...
        'BinomialSize', binomialSizeVector, ...
        'FitMethod', 'Laplace');
    warnMsg = string(lastwarn);

    coefTbl = mdl.Coefficients;
    % ROOT CAUSE FIX: fitglme's GeneralizedLinearMixedModel.Coefficients
    % property is returned as a legacy 'dataset' array (not 'table'), even in current MATLAB releases. 
    % Convert it to a table immediately so all downstream .Properties / column access works normally.
    if isa(coefTbl, 'dataset')
        coefTbl = dataset2table(coefTbl);
    end
    coefNames = string(coefTbl.Name);

    try
        ci = coefCI(mdl);
    catch
        ci = NaN(height(coefTbl), 2);
    end

    try
        AIC = mdl.ModelCriterion.AIC;
        BIC = mdl.ModelCriterion.BIC;
    catch
        AIC = NaN;
        BIC = NaN;
    end

    modelConverged = true;
    try
        if isprop(mdl, 'ConvergenceInfo')
            convInfo = mdl.ConvergenceInfo;
            if isstruct(convInfo) && isfield(convInfo, 'Converged')
                modelConverged = logical(convInfo.Converged);
            end
        end
    catch
        modelConverged = true;
    end

    R = table();
    for i = 1:numel(predictorTerms)
        term = predictorTerms(i);
        idx = find(coefNames == term, 1, 'first');
        if isempty(idx)
            oneRow = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                effectPredictors(i), effectTypes(i), speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
                NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, AIC, BIC, ...
                false, "Predictor coefficient was not found in fitted model: " + term, reportFormula);
        else
            est = coefTbl.Estimate(idx);
            se = coefTbl.SE(idx);
            statVal = local_get_stat(coefTbl, idx);
            pVal = coefTbl.pValue(idx);
            if size(ci,1) >= idx
                ciLower = exp(ci(idx,1));
                ciUpper = exp(ci(idx,2));
            else
                ciLower = exp(est - 1.96 * se);
                ciUpper = exp(est + 1.96 * se);
            end
            msg = "";
            if strlength(warnMsg) > 0
                msg = "MATLAB warning: " + warnMsg;
            end
            if ~modelConverged
                if strlength(msg) > 0
                    msg = msg + " | Model did not report convergence.";
                else
                    msg = "Model did not report convergence.";
                end
            end

            oneRow = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                effectPredictors(i), effectTypes(i), speedActuallyIncluded, perturbationActuallyIncluded, nParticipants, nRows, ...
                est, se, statVal, pVal, NaN, exp(est), ciLower, ciUpper, AIC, BIC, ...
                modelConverged, msg, reportFormula);
        end
        R = local_append_table(R, oneRow);
    end
catch ME
    R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
        "model", "model", speedActuallyIncluded, includePerturbation, 0, 0, ...
        NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
        false, string(ME.message), "");
end
end

function T = local_append_table(T, newRows)
    if isempty(T) || width(T) == 0
        T = newRows;
    else
        T = [T; newRows];
    end
end

function formula = local_build_fit_formula(predictorTerms, includePerturbation, includeSpeed)
    fixedTerms = predictorTerms(:).';
    if includeSpeed
        fixedTerms = [fixedTerms, "speed"];
    end
    if includePerturbation
        fixedTerms = [fixedTerms, "perturbation_group"];
    end
    rhs = strjoin(fixedTerms, ' + ');
    formula = "model_response ~ " + rhs + " + (1|participant_id)";
end

function formula = local_build_report_formula(successVar, denominatorVar, predictorTerms, includePerturbation, includeSpeed)
    fixedTerms = predictorTerms(:).';
    if includeSpeed
        fixedTerms = [fixedTerms, "speed"];
    end
    if includePerturbation
        fixedTerms = [fixedTerms, "perturbation_group"];
    end
    rhs = strjoin(fixedTerms, ' + ');
    formula = successVar + " out of " + denominatorVar + " ~ " + rhs + ...
        " + (1|participant_id); fit as grouped binomial counts with BinomialSize=" + denominatorVar;
end

function statVal = local_get_stat(coefTbl, idx)
    statVal = NaN;
    names = string(coefTbl.Properties.VariableNames);
    if any(names == "tStat")
        statVal = coefTbl.tStat(idx);
    elseif any(names == "zStat")
        statVal = coefTbl.zStat(idx);
    elseif any(names == "Stat")
        statVal = coefTbl.Stat(idx);
    end
end

function R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, effectPredictor, effectType, speedIncluded, perturbationIncluded, nParticipants, nRows, estimate, SE, tOrZ, p, pFDR, oddsRatio, ciLower, ciUpper, AIC, BIC, modelConverged, errorMessage, formula)
    R = table( ...
        string(outcomeType), ...
        string(modelFamily), ...
        string(restConditionLabel), ...
        string(hrvPredictor), ...
        string(gaitPredictor), ...
        string(effectPredictor), ...
        string(effectType), ...
        local_to_logical(speedIncluded), ...
        local_to_logical(perturbationIncluded), ...
        double(nParticipants), ...
        double(nRows), ...
        double(estimate), ...
        double(SE), ...
        double(tOrZ), ...
        double(p), ...
        double(pFDR), ...
        double(oddsRatio), ...
        double(ciLower), ...
        double(ciUpper), ...
        double(AIC), ...
        double(BIC), ...
        local_to_logical(modelConverged), ...
        string(errorMessage), ...
        string(formula), ...
        'VariableNames', {'outcome_type', 'model_family', 'rest_condition', ...
        'hrv_predictor', 'gait_predictor', 'effect_predictor', 'effect_type', ...
        'speed_included', 'perturbation_included', 'n_participants', 'n_rows', ...
        'estimate', 'SE', 't_or_z', 'p', 'p_FDR', 'odds_ratio', 'CI_lower', ...
        'CI_upper', 'AIC', 'BIC', 'model_converged', 'error_message', 'formula'});
end

function c = local_speed_categorical(x)
    raw = string(x);
    numericSpeed = str2double(raw);
    validText = ~ismissing(raw) & strlength(strtrim(raw)) > 0;

    if all(~validText | isfinite(numericSpeed))
        observed = unique(numericSpeed(isfinite(numericSpeed)));
        observed = sort(observed(:));
        levelText = string(observed);
        c = categorical(raw, levelText, 'Ordinal', false);
    else
        levelText = unique(raw(validText), 'stable');
        c = categorical(raw, levelText, 'Ordinal', false);
    end
end

function c = local_group_categorical(x)
    raw = strtrim(string(x));
    valid = ~ismissing(raw) & strlength(raw) > 0;
    levels = unique(raw(valid), 'stable');

    % If conventional N/P labels are present, make N the explicit reference.
    nIdx = find(strcmpi(levels, "N"), 1, 'first');
    pIdx = find(strcmpi(levels, "P"), 1, 'first');
    if ~isempty(nIdx) && ~isempty(pIdx)
        remaining = levels;
        remaining([nIdx pIdx]) = [];
        levels = [levels(nIdx); levels(pIdx); remaining(:)];
    end

    c = categorical(raw, levels, 'Ordinal', false);
end

function tf = local_to_logical(x)
    if islogical(x)
        tf = x;
    elseif isnumeric(x)
        tf = x ~= 0;
    elseif isstring(x) || ischar(x)
        sx = lower(strtrim(string(x)));
        tf = ismember(sx, ["true", "yes", "y", "1"]);
    else
        tf = false;
    end
end
