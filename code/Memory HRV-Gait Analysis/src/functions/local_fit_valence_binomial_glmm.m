function R = local_fit_valence_binomial_glmm(data, outcomeType, successVar, denominatorVar, denominatorTypeLabel, modelFamily, hrvPredictor, gaitPredictor, includePerturbation, restConditionLabel, useSpeedInteraction, skipReason)
%LOCAL_FIT_VALENCE_BINOMIAL_GLMM Fit valence-recall binomial GLMM safely.
%
% Required model term:
%   valence
%
% Optional model terms:
%   one z-scored HRV predictor
%   one z-scored gait predictor
%   speed                                 [only when >=2 speed levels are observed]
%   HRV x speed, gait x speed interaction(s)   [only when useSpeedInteraction = true and >=2 speed levels are observed]
%   perturbation_group
%   random intercept: participant_id
%
% Response is grouped binomial:
%   successVar out of denominatorVar
% implemented as:
%   model_response = success count
%   BinomialSize = denominator vector
%
% Two analysis "axes" are threaded through every output row so the
% caller can group/split results afterwards without re-deriving them.

if nargin < 12
    skipReason = "";
end
if nargin < 11
    useSpeedInteraction = false;
end

outcomeType = string(outcomeType);
successVar = string(successVar);
denominatorVar = string(denominatorVar);
denominatorTypeLabel = string(denominatorTypeLabel);
modelFamily = string(modelFamily);
hrvPredictor = string(hrvPredictor);
gaitPredictor = string(gaitPredictor);
restConditionLabel = string(restConditionLabel);
skipReason = string(skipReason);
useSpeedInteraction = logical(useSpeedInteraction);
speedActuallyIncluded = true;

if useSpeedInteraction
    speedModelLabel = "Mode2_SpeedInteraction";
else
    speedModelLabel = "Mode1_SpeedCovariate";
end

if isa(data, 'dataset')
    data = dataset2table(data);
elseif ~istable(data)
    try
        data = table(data);
    catch
        % downstream checks will handle it
    end
end

if strlength(skipReason) > 0
    R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
        "model", "model", speedActuallyIncluded, includePerturbation, true, 0, 0, ...
        NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
        false, skipReason, "", speedModelLabel, denominatorTypeLabel);
    return;
end

if exist('fitglme', 'file') ~= 2
    R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
        "model", "model", speedActuallyIncluded, includePerturbation, true, 0, 0, ...
        NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
        false, "fitglme was not found. The Statistics and Machine Learning Toolbox is required.", "", speedModelLabel, denominatorTypeLabel);
    return;
end

try
    if isempty(data) || height(data) == 0
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, includePerturbation, true, 0, 0, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "No rows available for this model.", "", speedModelLabel, denominatorTypeLabel);
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

    if useSpeedInteraction && isempty(predictorTerms)
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, includePerturbation, true, 0, 0, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Speed-interaction model requested but no HRV/gait predictor was provided to interact with speed.", "", speedModelLabel, denominatorTypeLabel);
        return;
    end

    needed = [successVar, denominatorVar, "valence", predictorTerms(:).', "speed", "participant_id"];
    perturbationActuallyIncluded = false;
    if includePerturbation && ismember('perturbation_group', data.Properties.VariableNames)
        needed = [needed, "perturbation_group"];
        perturbationActuallyIncluded = true;
    end

    missingVars = setdiff(needed, string(data.Properties.VariableNames), 'stable');
    if ~isempty(missingVars)
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, includePerturbation, true, 0, 0, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Missing required model variable(s): " + strjoin(missingVars, ', '), "", speedModelLabel, denominatorTypeLabel);
        return;
    end

    T = data(:, cellstr(unique(needed, 'stable')));

    T.(successVar) = double(T.(successVar));
    T.(denominatorVar) = double(T.(denominatorVar));

    for i = 1:numel(predictorTerms)
        T.(predictorTerms(i)) = double(T.(predictorTerms(i)));
    end

    % Keep Neutral as the reference category where MATLAB respects category order.
    T.valence = categorical(string(T.valence), ["Neutral", "Positive", "Negative"]);
    % Numeric speeds are ordered numerically so the lowest observed speed is
    % the reference level. Non-numeric labels keep stable source order.
    T.speed = local_speed_categorical(T.speed);
    T.participant_id = categorical(string(T.participant_id));

    if perturbationActuallyIncluded
        % If conventional N/P labels are present, N is the explicit reference.
        T.perturbation_group = local_group_categorical(T.perturbation_group);
    end

    complete = true(height(T), 1);
    complete = complete & ~isnan(T.(successVar));
    complete = complete & ~isnan(T.(denominatorVar));
    complete = complete & T.(denominatorVar) > 0;
    complete = complete & T.(successVar) >= 0;
    complete = complete & T.(successVar) <= T.(denominatorVar);
    complete = complete & ~isundefined(T.valence);
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

    % Re-check group levels after complete-case filtering. Predictor
    % missingness can otherwise leave a single estimable group.
    if perturbationActuallyIncluded
        nPertLevels = numel(categories(removecats(T.perturbation_group)));
        if nPertLevels < 2
            R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
                NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                false, "Perturbation/group variable has fewer than 2 levels after complete-case filtering.", "", speedModelLabel, denominatorTypeLabel);
            return;
        end
    end

    fitFormula = local_build_fit_formula(predictorTerms, perturbationActuallyIncluded, useSpeedInteraction, speedActuallyIncluded);
    reportFormula = local_build_report_formula(successVar, denominatorVar, predictorTerms, perturbationActuallyIncluded, useSpeedInteraction, speedActuallyIncluded);

    if nRows < 12
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Fewer than 12 complete rows are available for this valence model.", reportFormula, speedModelLabel, denominatorTypeLabel);
        return;
    end

    if nParticipants < 2
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Fewer than 2 participants are available for random intercept modeling.", reportFormula, speedModelLabel, denominatorTypeLabel);
        return;
    end

    if numel(categories(removecats(T.valence))) < 2
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Valence has fewer than 2 observed levels in this subset.", reportFormula, speedModelLabel, denominatorTypeLabel);
        return;
    end

    if useSpeedInteraction && numel(categories(removecats(T.speed))) < 2
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Speed has fewer than 2 observed levels in this subset; an interaction with speed cannot be estimated.", reportFormula, speedModelLabel, denominatorTypeLabel);
        return;
    end

    if all(T.(successVar) == 0) || all(T.(successVar) == T.(denominatorVar))
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Outcome has no binomial variation in this subset.", reportFormula, speedModelLabel, denominatorTypeLabel);
        return;
    end

    for i = 1:numel(predictorTerms)
        sdVal = std(T.(predictorTerms(i)), 'omitnan');
        if ~isfinite(sdVal) || sdVal == 0
            R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
                NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                false, "Predictor standard deviation is zero or non-finite after filtering: " + predictorTerms(i), reportFormula, speedModelLabel, denominatorTypeLabel);
            return;
        end
    end

    T.model_response = double(T.(successVar));
    binomialSizeVector = double(T.(denominatorVar));
    binomialSizeVector = binomialSizeVector(:);

    if numel(binomialSizeVector) ~= height(T) || any(~isfinite(binomialSizeVector)) || ...
            any(binomialSizeVector <= 0) || any(abs(binomialSizeVector - round(binomialSizeVector)) > sqrt(eps))
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Binomial denominator must be a positive integer vector with one value per model row.", reportFormula, speedModelLabel, denominatorTypeLabel);
        return;
    end

    successVector = double(T.(successVar));
    if any(~isfinite(successVector)) || any(successVector < 0) || ...
            any(successVector > binomialSizeVector) || ...
            any(abs(successVector - round(successVector)) > sqrt(eps))
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            false, "Binomial success count must be an integer between 0 and the denominator for every model row.", reportFormula, speedModelLabel, denominatorTypeLabel);
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

    R = table();

    % Return valence contrast coefficients.
    valenceIdx = find(startsWith(coefNames, "valence") | contains(coefNames, "valence_"));
    for i = 1:numel(valenceIdx)
        idx = valenceIdx(i);
        oneRow = local_make_effect_row(coefTbl, ci, idx, outcomeType, modelFamily, restConditionLabel, ...
            hrvPredictor, gaitPredictor, string(coefNames(idx)), "Valence", speedActuallyIncluded, perturbationActuallyIncluded, ...
            nParticipants, nRows, AIC, BIC, modelConverged, msg, reportFormula, speedModelLabel, denominatorTypeLabel);
        R = local_append_table(R, oneRow);
    end

    % Return HRV/gait main-effect predictor coefficients when present.
    for i = 1:numel(predictorTerms)
        term = predictorTerms(i);
        idx = find(coefNames == term, 1, 'first');
        if isempty(idx)
            oneRow = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                effectPredictors(i), effectTypes(i), speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
                NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, AIC, BIC, ...
                false, "Predictor coefficient was not found in fitted model: " + term, reportFormula, speedModelLabel, denominatorTypeLabel);
        else
            oneRow = local_make_effect_row(coefTbl, ci, idx, outcomeType, modelFamily, restConditionLabel, ...
                hrvPredictor, gaitPredictor, effectPredictors(i), effectTypes(i), speedActuallyIncluded, perturbationActuallyIncluded, ...
                nParticipants, nRows, AIC, BIC, modelConverged, msg, reportFormula, speedModelLabel, denominatorTypeLabel);
        end
        R = local_append_table(R, oneRow);
    end

    % Return HRV x speed / gait x speed interaction coefficients
    % (Mode 2 only).
    if useSpeedInteraction
        for i = 1:numel(predictorTerms)
            term = predictorTerms(i);
            intIdx = find(contains(coefNames, ":") & contains(coefNames, term) & contains(coefNames, "speed"));
            if isempty(intIdx)
                oneRow = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
                    effectPredictors(i), effectTypes(i) + "_x_Speed", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
                    NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, AIC, BIC, ...
                    false, "Speed interaction coefficient was not found in fitted model for: " + term, reportFormula, speedModelLabel, denominatorTypeLabel);
                R = local_append_table(R, oneRow);
            else
                for k = 1:numel(intIdx)
                    oneRow = local_make_effect_row(coefTbl, ci, intIdx(k), outcomeType, modelFamily, restConditionLabel, ...
                        hrvPredictor, gaitPredictor, effectPredictors(i), effectTypes(i) + "_x_Speed", speedActuallyIncluded, perturbationActuallyIncluded, ...
                        nParticipants, nRows, AIC, BIC, modelConverged, msg, reportFormula, speedModelLabel, denominatorTypeLabel);
                    R = local_append_table(R, oneRow);
                end
            end
        end
    end

    if isempty(R) || height(R) == 0
        R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
            "model", "model", speedActuallyIncluded, perturbationActuallyIncluded, true, nParticipants, nRows, ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, AIC, BIC, ...
            false, "No valence or predictor coefficients were returned from the fitted model.", reportFormula, speedModelLabel, denominatorTypeLabel);
    end

catch ME
    R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
        "model", "model", speedActuallyIncluded, includePerturbation, true, 0, 0, ...
        NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
        false, string(ME.message), "", speedModelLabel, denominatorTypeLabel);
end
end

function oneRow = local_make_effect_row(coefTbl, ci, idx, outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, effectPredictor, effectType, speedIncluded, perturbationIncluded, nParticipants, nRows, AIC, BIC, modelConverged, msg, formula, speedModel, denominatorType)
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
    oneRow = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, ...
        effectPredictor, effectType, speedIncluded, perturbationIncluded, true, nParticipants, nRows, ...
        est, se, statVal, pVal, NaN, exp(est), ciLower, ciUpper, AIC, BIC, ...
        modelConverged, msg, formula, speedModel, denominatorType);
end

function formula = local_build_fit_formula(predictorTerms, includePerturbation, useSpeedInteraction, includeSpeed)
    fixedTerms = ["valence", predictorTerms(:).'];
    if includeSpeed
        fixedTerms = [fixedTerms, "speed"];
    end
    if useSpeedInteraction && includeSpeed
        for i = 1:numel(predictorTerms)
            fixedTerms = [fixedTerms, predictorTerms(i) + ":speed"]; %#ok<AGROW>
        end
    end
    if includePerturbation
        fixedTerms = [fixedTerms, "perturbation_group"];
    end
    rhs = strjoin(fixedTerms, ' + ');
    formula = "model_response ~ " + rhs + " + (1|participant_id)";
end

function formula = local_build_report_formula(successVar, denominatorVar, predictorTerms, includePerturbation, useSpeedInteraction, includeSpeed)
    fixedTerms = ["valence", predictorTerms(:).'];
    if includeSpeed
        fixedTerms = [fixedTerms, "speed"];
    end
    if useSpeedInteraction && includeSpeed
        for i = 1:numel(predictorTerms)
            fixedTerms = [fixedTerms, predictorTerms(i) + ":speed"]; %#ok<AGROW>
        end
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

function R = local_result_row(outcomeType, modelFamily, restConditionLabel, hrvPredictor, gaitPredictor, effectPredictor, effectType, speedIncluded, perturbationIncluded, valenceIncluded, nParticipants, nRows, estimate, SE, tOrZ, p, pFDR, oddsRatio, ciLower, ciUpper, AIC, BIC, modelConverged, errorMessage, formula, speedModel, denominatorType)
    R = table( ...
        string(outcomeType), ...
        string(modelFamily), ...
        string(restConditionLabel), ...
        string(speedModel), ...
        string(denominatorType), ...
        string(hrvPredictor), ...
        string(gaitPredictor), ...
        string(effectPredictor), ...
        string(effectType), ...
        local_to_logical(speedIncluded), ...
        local_to_logical(perturbationIncluded), ...
        local_to_logical(valenceIncluded), ...
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
        'speed_model', 'denominator_type', ...
        'hrv_predictor', 'gait_predictor', 'effect_predictor', 'effect_type', ...
        'speed_included', 'perturbation_included', 'valence_included', ...
        'n_participants', 'n_rows', 'estimate', 'SE', 't_or_z', 'p', 'p_FDR', ...
        'odds_ratio', 'CI_lower', 'CI_upper', 'AIC', 'BIC', 'model_converged', ...
        'error_message', 'formula'});
end

function T = local_append_table(T, newRows)
    if isempty(T) || width(T) == 0
        T = newRows;
    else
        T = [T; newRows];
    end
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
