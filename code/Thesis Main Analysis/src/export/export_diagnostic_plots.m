function export_diagnostic_plots(output_dir, sources)
%EXPORT_DIAGNOSTIC_PLOTS Limited diagnostic-plot folder: for every model
%   row flagged by ANY of residual_normality_flag, homoscedasticity_flag,
%   or influential_points_flag, and whose fitted model object is still
%   available, saves one PNG with two panels (Pearson residual histogram
%   with a normal overlay; residuals vs. fitted scatter) under
%   output_dir/diagnostic_plots/. Deliberately scoped to flagged models
%   only, not every fitted model, so this stays an inspection aid rather
%   than a full model dump.
%
%   sources is a cell array of structs, each with fields:
%     .label   -- short name used in output filenames (e.g. 'primary')
%     .results -- the corresponding results table
%     .models  -- cell array of fitted model objects (or [] where
%                 unavailable), same length and row order as .results
%
%   Never errors out of the caller: a single model's plot failing to
%   render is caught and skipped, and this function itself is expected to
%   be called from within a try/catch by its caller (export_all_outputs.m)
%   so that a headless/no-graphics environment never blocks the rest of
%   the export.

plot_dir = fullfile(output_dir, 'diagnostic_plots');
if ~isfolder(plot_dir)
    mkdir(plot_dir);
end

n_saved = 0;
for si = 1:numel(sources)
    src = sources{si};
    Tr = src.results;
    mdls = src.models;
    if ~istable(Tr) || height(Tr) == 0 || isempty(mdls)
        continue;
    end

    for r = 1:height(Tr)
        if r > numel(mdls) || isempty(mdls{r})
            continue;
        end
        flagged = local_is_true(Tr.residual_normality_flag(r)) || ...
                  local_is_true(Tr.homoscedasticity_flag(r)) || ...
                  local_is_true(Tr.influential_points_flag(r));
        if ~flagged
            continue;
        end

        fig = [];
        try
            m = mdls{r};
            res = residuals(m, 'ResidualType', 'Pearson');
            fit_vals = fitted(m);
            ok = ~isnan(res) & ~isnan(fit_vals);
            if sum(ok) < 2
                continue;
            end

            fig = figure('Visible', 'off');

            subplot(1, 2, 1);
            histogram(res(ok), 'Normalization', 'pdf');
            hold on;
            xr = linspace(min(res(ok)), max(res(ok)), 100);
            mu_r = mean(res(ok));
            sd_r = std(res(ok));
            if sd_r > 0
                plot(xr, normpdf(xr, mu_r, sd_r), 'LineWidth', 1.5);
            end
            hold off;
            title('Pearson residuals');
            xlabel('residual'); ylabel('density');

            subplot(1, 2, 2);
            scatter(fit_vals(ok), res(ok), 12, 'filled');
            yline(0);
            title('Residuals vs. fitted');
            xlabel('fitted value'); ylabel('Pearson residual');

            fname = sprintf('%s_id%d_%s_%s_%s_%s.png', src.label, Tr.model_id(r), ...
                local_safe(Tr.gait_outcome{r}), local_safe(Tr.hrv_predictor{r}), ...
                local_safe(Tr.rest_condition{r}), local_safe(Tr.model_variant{r}));
            print(fig, fullfile(plot_dir, fname), '-dpng', '-r120');
            close(fig);
            n_saved = n_saved + 1;
        catch
            if ~isempty(fig) && isvalid(fig)
                close(fig);
            end
        end
    end
end

fprintf('  Diagnostic plots (flagged models only): %d saved to %s\n', n_saved, plot_dir);

end

function tf = local_is_true(v)
    if islogical(v)
        tf = v;
    elseif isnumeric(v)
        tf = v == 1;
    else
        tf = false;
    end
end

function s = local_safe(s)
    s = regexprep(s, '[^a-zA-Z0-9]+', '_');
end
