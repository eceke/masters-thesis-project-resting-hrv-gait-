%% RUN_GAIT_VARIABLE_SCREENING
% Purpose:
%   Screen gait variables to decide which gait outcomes should go into the
%   final HRV-gait prediction table/model.
%
% Primary model per gait variable (FW and Baseline/BW screened together):
%   gait_variable_z ~ SpeedCat * Perturbation + TaskLabel + (1 | ParticipantID)
%
% Output:
%   Excel workbook with descriptives, missingness, row-count/design checks,
%   LMM results, candidate ranking, final recommendation, and notes.
%
% Expected input file:
%   PERTUBA WORDS IN MOTION_CLEAN DATABASE_(N = 30).xlsx
%
% Important:
%   This script uses the CLEAN gait database, not the later HRV/gait
%   analysis table. The clean file already contains Condition, Task, and Speed.
%
% Source task labels are "Baseline" (BW) and "FW"; both denote walking tasks.

clear; clc;

%% ====================== USER SETTINGS ======================
inputFile = 'PERTUBA WORDS IN MOTION_CLEAN DATABASE_(N = 30).xlsx';
inputSheet = 'Report Results';

% Primary screening target. The clean database has exactly two walking
% tasks: "FW" and "Baseline" (Baseline = Baseline Walking / BW -- there is
% no separate "BW" literal in the data). Screen both together by default.
TASK_FILTER = ["FW" "Baseline"];   % options: "FW", "Baseline", or both together

% Condition coding assumption:
%   N = non-perturbation / normal walking
%   P = perturbation
NONPERT_CODE = "N";
PERT_CODE    = "P";

ALPHA = 0.05;
MISSING_WARN_PCT = 25;   % flag variables with >25% missingness

% Candidate gait variables exclude acquisition and administrative fields. 
% USE_BROAD_23 selects the 23-variable set; otherwise the 19-variable set is used.
USE_BROAD_23 = true;

core19GaitVars = {
    'Average stride length (cm)'
    'Stride length variability (%)'
    'Cadence (steps/min)'
    'Average swing time (s)'
    'Average stance time (s)'
    'Average stride time (s)'
    'Average step time (s)'
    'Average single support'
    'Average double support'
    'Swing time variability (%)'
    'Stance time variability (%)'
    'Stride time variability (%)'
    'Step time variability (%)'
    'Single support variability (%)'
    'Double support variability (%)'
    'Stride time asymmetry (%)'
    'Stance time asymmetry  (%)'
    'Swing time asymmetry (%)'
    'Step time asymmetry (%)'
};

% Broader set: adds velocity-related metrics and stride length asymmetry.
% These can be useful for the screening table, but interpret speed effects
% carefully because some are mechanically tied to treadmill speed.
broadGaitVars = [
    {'Average stride velocity (cm/s)'}
    {'Stride velocity variability (%)'}
    core19GaitVars
    {'Stride velocity asymmetry (%)'}
    {'Stride length asymmetry (%)'}
];

if USE_BROAD_23
    gaitVarsOriginal = broadGaitVars;
else
    gaitVarsOriginal = core19GaitVars;
end

% Theory-relevant backup variables: these are useful even if screening is
% not significant, because they map cleanly onto the thesis gait story.
theoryRelevantVars = {
    'Average stride length (cm)'
    'Cadence (steps/min)'
    'Average stride time (s)'
    'Average stance time (s)'
    'Average swing time (s)'
    'Average double support'
    'Stride time variability (%)'
    'Stance time variability (%)'
    'Swing time variability (%)'
    'Double support variability (%)'
    'Stride time asymmetry (%)'
    'Stance time asymmetry  (%)'
    'Swing time asymmetry (%)'
};

%% ====================== LOAD DATA ======================
if ~isfile(inputFile)
    [fn, fp] = uigetfile({'*.xlsx;*.xls','Excel files'}, 'Select CLEAN gait database');
    if isequal(fn,0)
        error('No input file selected.');
    end
    inputFile = fullfile(fp, fn);
end

fprintf('Reading: %s\n', inputFile);
Traw = readtable(inputFile, 'Sheet', inputSheet, 'VariableNamingRule', 'preserve');

% Preserve original variable names but make MATLAB-safe internal names.
origNames = Traw.Properties.VariableNames;
validNames = matlab.lang.makeValidName(origNames);
validNames = matlab.lang.makeUniqueStrings(validNames);
nameMap = table(origNames(:), validNames(:), 'VariableNames', {'original','valid'});
T = Traw;
T.Properties.VariableNames = validNames;

% Required columns.
pidCol       = local_varname(nameMap, 'Patient ID');
conditionCol = local_varname(nameMap, 'Condition');
taskCol      = local_varname(nameMap, 'Task');
speedCol     = local_varname(nameMap, 'Speed');

pid       = local_to_double(T.(pidCol));
speedNum  = local_to_double(T.(speedCol));
condition = string(T.(conditionCol));
task      = string(T.(taskCol));

% Diagnostic print of raw Task labels BEFORE filtering. The clean database
% only ever contains "FW" and "Baseline" (Baseline = Baseline Walking/BW);
% this printout is a quick guard in case a future data export changes that.
fprintf('\nRaw Task label counts (pre-filter, all rows in sheet):\n');
rawTaskCats = unique(task(~ismissing(task)));
for i = 1:numel(rawTaskCats)
    fprintf('  %-12s : %d rows\n', rawTaskCats(i), sum(task == rawTaskCats(i)));
end
fprintf('\n');

% Exclude rows with invalid participant ID, speed, condition, or task.
validRows = ~isnan(pid) & ismember(speedNum, [1 4]) & ...
            ismember(condition, [NONPERT_CODE PERT_CODE]) & ...
            ismember(task, ["FW" "Baseline"]) & ...
            ismember(task, TASK_FILTER);

D = T(validRows, :);
D.ParticipantID = categorical(pid(validRows));
D.SpeedNum = speedNum(validRows);
D.SpeedCat = categorical(speedNum(validRows), [1 4], {'S1','S4'});
D.Perturbation = categorical(condition(validRows), [NONPERT_CODE PERT_CODE], {'N','P'});

% Fix Baseline (= Baseline Walking / BW) as the explicit reference category
% for Task, rather than leaving the category order to MATLAB's default
% (alphabetical) behavior. This guarantees estimate_task always represents
% FW vs Baseline/BW, matching the reference coding used in the Methods.
D.TaskLabel = categorical( ...
    task(validRows), ...
    ["Baseline" "FW"], ...
    {'Baseline','FW'});

fprintf('Rows after cleaning/filtering: %d\n', height(D));
fprintf('Participants after cleaning/filtering: %d\n', numel(categories(D.ParticipantID))); 
fprintf('Task filter: %s\n', strjoin(TASK_FILTER, ', '));
fprintf('Tasks present after filtering: %s\n\n', strjoin(string(categories(removecats(D.TaskLabel))), ', '));

% Convert requested gait variable names to MATLAB-safe names and verify.
gaitVarsValid = strings(numel(gaitVarsOriginal),1);
keepVar = true(numel(gaitVarsOriginal),1);
for i = 1:numel(gaitVarsOriginal)
    try
        gaitVarsValid(i) = string(local_varname(nameMap, gaitVarsOriginal{i}));
    catch ME
        warning('Gait variable not found and will be skipped: %s', gaitVarsOriginal{i});
        keepVar(i) = false;
    end
end

gaitVarsOriginal = gaitVarsOriginal(keepVar);
gaitVarsValid = gaitVarsValid(keepVar);

%% ====================== DESIGN / ROW-COUNT SANITY CHECK ======================
% Independent of any specific gait variable's missingness: how many rows
% and how many unique participants fall into each Task, Speed, and
% Task x Speed x Perturbation cell after filtering. Use this to confirm
% Baseline (BW) rows are really present alongside FW, and to check the
% 28 x 2 x 2 = 112 expectation for the fully-crossed design.
taskCats  = categories(removecats(D.TaskLabel));
spCatsAll = categories(D.SpeedCat);
pertCatsAll = categories(D.Perturbation);

designRows = {};

% By Task alone.
for t = 1:numel(taskCats)
    mask = D.TaskLabel == taskCats{t};
    designRows(end+1,:) = {'Task', taskCats{t}, '-', '-', ...
        sum(mask), numel(unique(D.ParticipantID(mask)))}; %#ok<SAGROW>
end

% By Speed alone.
for s = 1:numel(spCatsAll)
    mask = D.SpeedCat == spCatsAll{s};
    designRows(end+1,:) = {'Speed', spCatsAll{s}, '-', '-', ...
        sum(mask), numel(unique(D.ParticipantID(mask)))}; %#ok<SAGROW>
end

% By Task x Speed.
for t = 1:numel(taskCats)
    for s = 1:numel(spCatsAll)
        mask = D.TaskLabel == taskCats{t} & D.SpeedCat == spCatsAll{s};
        designRows(end+1,:) = {'Task x Speed', taskCats{t}, spCatsAll{s}, '-', ...
            sum(mask), numel(unique(D.ParticipantID(mask)))}; %#ok<SAGROW>
    end
end

% By Task x Speed x Perturbation (the actual LMM design cells).
for t = 1:numel(taskCats)
    for s = 1:numel(spCatsAll)
        for p = 1:numel(pertCatsAll)
            mask = D.TaskLabel == taskCats{t} & D.SpeedCat == spCatsAll{s} & D.Perturbation == pertCatsAll{p};
            designRows(end+1,:) = {'Task x Speed x Perturbation', taskCats{t}, spCatsAll{s}, pertCatsAll{p}, ...
                sum(mask), numel(unique(D.ParticipantID(mask)))}; %#ok<SAGROW>
        end
    end
end

designTbl = cell2table(designRows, 'VariableNames', ...
    {'breakdown','task','speed','perturbation','n_rows','n_unique_participants'});

fprintf('Design / row-count sanity check:\n');
for i = 1:height(designTbl)
    fprintf('  %-28s task=%-8s speed=%-4s pert=%-4s rows=%-4d participants=%d\n', ...
        designTbl.breakdown{i}, designTbl.task{i}, designTbl.speed{i}, designTbl.perturbation{i}, ...
        designTbl.n_rows(i), designTbl.n_unique_participants(i));
end
fprintf('\n');

%% ====================== DESCRIPTIVES + MISSINGNESS ======================
descRows = {};
missRows = {};

for i = 1:numel(gaitVarsOriginal)
    origName = gaitVarsOriginal{i};
    validName = gaitVarsValid(i);
    y = local_to_double(D.(validName));

    nTotal = numel(y);
    nMissing = sum(isnan(y));
    missPct = 100 * nMissing / nTotal;
    missRows(end+1,:) = {origName, local_gait_type(origName), nTotal, nMissing, missPct}; %#ok<SAGROW>

    taskCatsDesc = categories(removecats(D.TaskLabel));
    spCats = categories(D.SpeedCat);
    pertCats = categories(D.Perturbation);
    for tt = 1:numel(taskCatsDesc)
        for s = 1:numel(spCats)
            for p = 1:numel(pertCats)
                mask = D.TaskLabel == taskCatsDesc{tt} & D.SpeedCat == spCats{s} & D.Perturbation == pertCats{p};
                yy = y(mask);
                nRows = numel(yy);
                nAvail = sum(~isnan(yy));
                nMiss = sum(isnan(yy));
                descRows(end+1,:) = {origName, local_gait_type(origName), char(taskCatsDesc{tt}), char(spCats{s}), char(pertCats{p}), ...
                    nRows, nAvail, nMiss, mean(yy,'omitnan'), std(yy,0,'omitnan'), ...
                    median(yy,'omitnan'), min(yy,[],'omitnan'), max(yy,[],'omitnan')}; %#ok<SAGROW>
            end
        end
    end
end

descTbl = cell2table(descRows, 'VariableNames', {
    'gait_variable','variable_type','task','speed','perturbation','n_rows','n_available','n_missing', ...
    'mean','sd','median','min','max'});

missingTbl = cell2table(missRows, 'VariableNames', {
    'gait_variable','variable_type','n_total','n_missing','missing_pct'});

%% ====================== LMM SCREENING ======================
resultRows = {};

for i = 1:numel(gaitVarsOriginal)
    origName = gaitVarsOriginal{i};
    validName = gaitVarsValid(i);
    y = local_to_double(D.(validName));

    nTotal = numel(y);
    nMissing = sum(isnan(y));
    missPct = 100 * nMissing / nTotal;

    % z-score outcome so estimates are comparable across gait variables.
    yMean = mean(y,'omitnan');
    ySD = std(y,0,'omitnan');

    estimate_speed = NaN; p_speed = NaN;
    estimate_pert = NaN; p_pert = NaN;
    estimate_int = NaN; p_int = NaN;
    estimate_task = NaN; p_task = NaN;
    model_converged = false;
    warning_flag = "";
    aic = NaN; bic = NaN;
    formula_used = "";

    if ySD == 0 || isnan(ySD)
        warning_flag = "zero_or_invalid_sd";
    else
        D.Y_z = (y - yMean) ./ ySD;
        M = D(~isnan(D.Y_z), {'Y_z','SpeedCat','Perturbation','TaskLabel','ParticipantID'});

        formula_used = "Y_z ~ SpeedCat*Perturbation + TaskLabel + (1|ParticipantID)";

        try
            lastwarn('');    % clear so we can attribute any warning to this fit
            lme = fitlme(M, char(formula_used), 'FitMethod', 'REML');
            [lastWarnMsg, ~] = lastwarn();

            coefTbl = lme.Coefficients;
            coefNames = string(coefTbl.Name);

            speedIdx = find(contains(coefNames, 'SpeedCat') & ~contains(coefNames, ':') & ~contains(coefNames, 'Perturbation'), 1);
            pertIdx  = find(contains(coefNames, 'Perturbation') & ~contains(coefNames, ':') & ~contains(coefNames, 'SpeedCat'), 1);
            intIdx   = find(contains(coefNames, ':'), 1);
            taskIdx  = find(contains(coefNames, 'TaskLabel'), 1);

            if ~isempty(speedIdx)
                estimate_speed = coefTbl.Estimate(speedIdx);
                p_speed = coefTbl.pValue(speedIdx);
            end
            if ~isempty(pertIdx)
                estimate_pert = coefTbl.Estimate(pertIdx);
                p_pert = coefTbl.pValue(pertIdx);
            end
            if ~isempty(intIdx)
                estimate_int = coefTbl.Estimate(intIdx);
                p_int = coefTbl.pValue(intIdx);
            end
            if ~isempty(taskIdx)
                estimate_task = coefTbl.Estimate(taskIdx);
                p_task = coefTbl.pValue(taskIdx);
            end

            % Real convergence check: fitlme can return a model object
            % without throwing an error even when REML/Hessian estimation
            % struggled. Scan the warning raised during THIS fit (captured
            % via lastwarn) for known convergence-related keywords, rather
            % than treating "no error thrown" as "converged".
            convergenceFlags = ["converg","hessian","iteration limit","not positive definite","gradient","singular"];
            hadConvergenceWarning = strlength(lastWarnMsg) > 0 && ...
                any(contains(lower(string(lastWarnMsg)), convergenceFlags));

            if hadConvergenceWarning
                model_converged = false;
                warning_flag = "convergence_warning: " + extractBefore(string(lastWarnMsg), min(strlength(string(lastWarnMsg))+1, 120));
            else
                model_converged = true;
            end
            aic = lme.ModelCriterion.AIC;
            bic = lme.ModelCriterion.BIC;
        catch ME
            warning_flag = string(ME.identifier);
            if strlength(warning_flag) == 0
                warning_flag = extractBefore(string(ME.message), min(strlength(string(ME.message))+1, 80));
            end
        end
    end

    resultRows(end+1,:) = {origName, local_gait_type(origName), nTotal, nMissing, missPct, ...
        char(formula_used), estimate_speed, p_speed, estimate_pert, p_pert, estimate_int, p_int, ...
        estimate_task, p_task, model_converged, char(warning_flag), aic, bic}; %#ok<SAGROW>
end

resultsTbl = cell2table(resultRows, 'VariableNames', {
    'gait_variable','variable_type','n_total','n_missing','missing_pct', ...
    'model_formula', ...
    'estimate_speed_S4_vs_S1','p_speed', ...
    'estimate_perturbation_P_vs_N','p_perturbation', ...
    'estimate_speed_x_perturbation','p_interaction', ...
    'estimate_task','p_task', ...
    'model_converged','warning_flag','AIC','BIC'});

% FDR correction separately for each question family (speed, perturbation,
% interaction, task). Note: with the current default (TASK_FILTER = both
% FW and Baseline), TaskLabel always varies so p_task is always estimated.
% If TASK_FILTER is ever narrowed to a single task, TaskLabel becomes
% constant and MATLAB will drop it automatically (p_task/p_task_FDR = NaN).
resultsTbl.p_speed_FDR = local_bh_fdr(resultsTbl.p_speed);
resultsTbl.p_perturbation_FDR = local_bh_fdr(resultsTbl.p_perturbation);
resultsTbl.p_interaction_FDR = local_bh_fdr(resultsTbl.p_interaction);
resultsTbl.p_task_FDR = local_bh_fdr(resultsTbl.p_task);

%% ====================== CANDIDATE RANKING ======================
rankingTbl = resultsTbl;
rankingTbl.theory_relevant = ismember(string(rankingTbl.gait_variable), string(theoryRelevantVars));

rankScore = zeros(height(rankingTbl),1);
recommendation = strings(height(rankingTbl),1);
rationale = strings(height(rankingTbl),1);

for i = 1:height(rankingTbl)
    problem = rankingTbl.missing_pct(i) > MISSING_WARN_PCT || ~rankingTbl.model_converged(i);
    pertStrong = rankingTbl.p_perturbation_FDR(i) < ALPHA;
    intStrong  = rankingTbl.p_interaction_FDR(i) < ALPHA;
    speedStrong = rankingTbl.p_speed_FDR(i) < ALPHA;
    pertRaw = rankingTbl.p_perturbation(i) < ALPHA;
    intRaw  = rankingTbl.p_interaction(i) < ALPHA;
    speedRaw = rankingTbl.p_speed(i) < ALPHA;
    theory = rankingTbl.theory_relevant(i);

    score = 0;
    if pertStrong, score = score + 4; end
    if intStrong, score = score + 4; end
    if speedStrong, score = score + 1; end
    if pertRaw || intRaw, score = score + 2; end
    if speedRaw, score = score + 0.5; end
    if theory, score = score + 1; end
    if problem, score = score - 4; end
    rankScore(i) = score;

    if problem
        recommendation(i) = "Check / probably exclude";
        rationale(i) = "High missingness or model failed; do not use unless theoretically essential.";
    elseif pertStrong || intStrong
        recommendation(i) = "Strong include candidate";
        rationale(i) = "FDR-significant perturbation and/or speed-by-perturbation sensitivity.";
    elseif pertRaw || intRaw
        recommendation(i) = "Possible include candidate";
        rationale(i) = "Uncorrected perturbation/interaction pattern; discuss with supervisor before final inclusion.";
    elseif speedStrong && theory
        recommendation(i) = "Include with caution";
        rationale(i) = "Strong speed sensitivity and theory-relevant, but speed effects can be mechanically expected.";
    elseif theory
        recommendation(i) = "Theory-based backup";
        rationale(i) = "Not statistically prominent in screening, but maps well onto the thesis gait construct.";
    elseif speedStrong
        recommendation(i) = "Low priority / speed-bound";
        rationale(i) = "Mostly speed-sensitive; not enough alone for perturbation-sensitive outcome selection.";
    else
        recommendation(i) = "Low priority";
        rationale(i) = "No clear screening effect and not part of the theory-prioritized shortlist.";
    end
end

rankingTbl.rank_score = rankScore;
rankingTbl.recommendation = recommendation;
rankingTbl.rationale = rationale;
rankingTbl = sortrows(rankingTbl, 'rank_score', 'descend');

finalRecommendationTbl = rankingTbl(:, {
    'gait_variable','variable_type','rank_score','recommendation','rationale', ...
    'missing_pct','model_formula', ...
    'estimate_speed_S4_vs_S1','p_speed','p_speed_FDR', ...
    'estimate_perturbation_P_vs_N','p_perturbation','p_perturbation_FDR', ...
    'estimate_speed_x_perturbation','p_interaction','p_interaction_FDR', ...
    'estimate_task','p_task','p_task_FDR'});

%% ====================== WRITE OUTPUT ======================
[inputDir, inputBase, ~] = fileparts(inputFile);
if inputDir == ""
    inputDir = pwd;
end
outputDir = fullfile(inputDir, 'Gait_Selection_Output');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

stamp = string(datetime('now','Format','yyyyMMdd_HHmm'));
taskTag = strjoin(TASK_FILTER, '-');
outputExcel = fullfile(outputDir, sprintf('Gait_Variable_Screening_%s_%s.xlsx', taskTag, stamp));

if isfile(outputExcel)
    delete(outputExcel);
end

notes = {
    'Purpose', 'Screen gait variables before deciding which gait outcomes enter the final HRV-gait analysis table/model.'
    'Input file', inputFile
    'Input sheet', inputSheet
    'Task filter', char(strjoin(TASK_FILTER, ', '))
    'Tasks actually present after filtering', char(strjoin(string(taskCats), ', '))
    'Task naming', 'Baseline = Baseline Walking (BW). There is no separate "BW" literal in the raw Task column; only "FW" and "Baseline" exist, fully crossed with Speed and Condition (56 rows each, 112 combined).'
    'Task reference coding', 'TaskLabel is explicitly coded with Baseline (BW) as the reference category, so estimate_task always represents FW minus Baseline/BW (not left to alphabetical default).'
    'Primary model', 'gait_variable_z ~ SpeedCat * Perturbation + TaskLabel + (1 | ParticipantID)'
    'Convergence check', 'model_converged reflects both whether fitlme threw an error AND whether it raised a convergence/Hessian/gradient/singularity warning during fitting; a clean run without such warnings is required to be flagged converged.'
    'Speed coding', 'S1 = 1 km/h; S4 = 4 km/h'
    'Perturbation coding', 'N = non-perturbation / normal; P = perturbation'
    'Outcome scaling', 'Each gait variable is z-scored before LMM so estimates are comparable across variables.'
    'FDR correction', 'Benjamini-Hochberg correction applied separately to speed, perturbation, interaction, and task p-value families.'
    'Candidate logic', 'Prioritize perturbation or interaction sensitivity; speed-only effects are interpreted cautiously because speed is mechanically expected to affect gait.'
    'Invalid rows removed', 'Rows with missing Condition/Task, nonnumeric participant ID, or Speed not equal to 1/4 are removed automatically.'
    'Broad variable mode', sprintf('%d variables screened. USE_BROAD_23 = %d.', numel(gaitVarsOriginal), USE_BROAD_23)
    };

writecell(notes, outputExcel, 'Sheet', 'Notes');
writetable(descTbl, outputExcel, 'Sheet', 'Gait_Descriptives');
writetable(missingTbl, outputExcel, 'Sheet', 'Missingness_Check');
writetable(designTbl, outputExcel, 'Sheet', 'Design_RowCounts');
writetable(resultsTbl, outputExcel, 'Sheet', 'LMM_Gait_Screening_All');
writetable(rankingTbl, outputExcel, 'Sheet', 'Candidate_Ranking');
writetable(finalRecommendationTbl, outputExcel, 'Sheet', 'Final_Recommendation');
writetable(nameMap, outputExcel, 'Sheet', 'Column_Name_Map');

fprintf('\nDone. Output written to:\n%s\n', outputExcel);

%% ====================== LOCAL FUNCTIONS ======================
function validName = local_varname(nameMap, originalName)
    idx = strcmp(nameMap.original, originalName);
    if ~any(idx)
        error('Column not found: %s', originalName);
    end
    validName = nameMap.valid{find(idx,1)};
end

function x = local_to_double(v)
    if isnumeric(v)
        x = double(v);
    elseif iscell(v)
        x = str2double(string(v));
    elseif isstring(v) || ischar(v)
        x = str2double(string(v));
    elseif iscategorical(v)
        x = str2double(string(v));
    else
        x = str2double(string(v));
    end
end

function q = local_bh_fdr(p)
    p = double(p);
    q = NaN(size(p));
    valid = ~isnan(p);
    pv = p(valid);
    if isempty(pv)
        return;
    end
    [ps, order] = sort(pv(:), 'ascend');
    m = numel(ps);
    qs = ps .* m ./ (1:m)';
    for k = m-1:-1:1
        qs(k) = min(qs(k), qs(k+1));
    end
    qs(qs > 1) = 1;
    idx = find(valid);
    q(idx(order)) = qs;
end

function typ = local_gait_type(name)
    s = lower(string(name));
    if contains(s, 'asymmetry')
        typ = 'asymmetry';
    elseif contains(s, 'variability')
        typ = 'variability';
    elseif contains(s, 'velocity') || contains(s, 'cadence')
        typ = 'pace_speed_related';
    elseif contains(s, 'length')
        typ = 'spatial';
    elseif contains(s, 'support')
        typ = 'support_stability';
    elseif contains(s, 'swing') || contains(s, 'stance') || contains(s, 'stride time') || contains(s, 'step time')
        typ = 'temporal';
    else
        typ = 'other';
    end
end
