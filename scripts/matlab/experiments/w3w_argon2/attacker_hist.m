% argon2_attacker_histograms_and_percentiles.m
% Reads attacker Argon2 GPU sweep CSVs (one per memory setting),
% prints percentiles/median to console, and draws histograms per RAM.
%
% Expected columns (example):
%   Run,Mem_MiB,T_cost,Lanes,HashRate_Hs,NumDevices
%
% For Argon2 attacker-side, HashRate_Hs is guesses/sec (H/s).
% We also compute time-per-guess in ms: t_ms = 1000 / HashRate_Hs.

clear; clc;

% ---- Files (edit names to match your folder) ----
files = {
    'argon2_gpu_m64MiB.csv'
    'argon2_gpu_m128MiB.csv'
    'argon2_gpu_m256MiB.csv'
    'argon2_gpu_m512MiB.csv'
    'argon2_gpu_m1024MiB.csv'
    'argon2_gpu_m2048MiB.csv'
    'argon2_gpu_m4096MiB.csv'
    'argon2_gpu_m8192MiB.csv'
};

labels = {'64 MiB','128 MiB','256 MiB','512 MiB','1024 MiB','2048 MiB','4096 MiB','8192 MiB'};

% ---- Percentiles to print ----
p_rate = [1 5 10 25 50 75 90 95 99];   % for hash rate
p_time = [50 90 95 99];               % for time/guess

% ---- Figure settings ----
fontSizeAxes = 13;
fontSizeTitle = 14;

for f = 1:numel(files)
    csvFile = files{f};
    if ~isfile(csvFile)
        warning("Missing file: %s (skipping)", csvFile);
        continue;
    end

    T = readtable(csvFile, 'TextType','string');

    % --- Robust column find for hash rate ---
    vars = T.Properties.VariableNames;

    idxRate = find(contains(vars, "HashRate", 'IgnoreCase', true), 1);
    if isempty(idxRate)
        % fallback: any column containing "Rate" and "Hs"
        idxRate = find(contains(vars, "Rate", 'IgnoreCase', true) & contains(vars, "Hs", 'IgnoreCase', true), 1);
    end
    if isempty(idxRate)
        error("Could not locate hash rate column in %s. Columns: %s", csvFile, strjoin(vars, ", "));
    end

    R = T{:, idxRate};
    if ~isnumeric(R)
        R = str2double(string(R));
    end

    % --- clean ---
    R = R(isfinite(R) & R > 0);     % H/s
    N = numel(R);
    if N == 0
        warning("No valid HashRate_Hs in %s (skipping)", csvFile);
        continue;
    end

    % --- derived ---
    t_ms = 1000 ./ R;              % ms per guess

    % --- stats ---
    muR  = mean(R);  sdR  = std(R);  medR = median(R);
    pR   = prctile(R, p_rate);

    mut  = mean(t_ms); sdt = std(t_ms); medt = median(t_ms);
    pt   = prctile(t_ms, p_time);

    % ---- Console output ----
    fprintf("\nFile: %s\n", csvFile);
    fprintf("Setting: %s\n", labels{f});
    fprintf("N runs                 : %d\n", N);

    fprintf("HashRate (H/s)\n");
    fprintf("  Mean / Std           : %.6f / %.6f\n", muR, sdR);
    fprintf("  Median               : %.6f\n", medR);
    fprintf("  Percentiles ");
    fprintf("p%d ", p_rate);
    fprintf("\n              ");
    fprintf("%.6f ", pR);
    fprintf("\n");

    fprintf("Time per guess (ms)\n");
    fprintf("  Mean / Std           : %.6f / %.6f\n", mut, sdt);
    fprintf("  Median               : %.6f\n", medt);
    fprintf("  Percentiles ");
    fprintf("p%d ", p_time);
    fprintf("\n              ");
    fprintf("%.6f ", pt);
    fprintf("\n");

    % ---- Histogram: HashRate (H/s) ----
    figure('Color','w');
    histogram(R, 'BinMethod','fd');
    grid on;
    xlabel("Argon2id guess rate (H/s)");
    ylabel("Count");
    title(sprintf("Attacker Argon2id GPU rate — %s (N=%d)", labels{f}, N), 'Interpreter','none');

    set(gca, 'FontSize', fontSizeAxes);
    set(get(gca,'Title'), 'FontSize', fontSizeTitle, 'FontWeight','normal');

    hold on;
    yl = ylim;
    xline(medR, '-',  sprintf(' median=%.3f', medR), 'LabelVerticalAlignment','middle');
    xline(pR(p_rate==95), '--', sprintf(' p95=%.3f', pR(p_rate==95)), 'LabelVerticalAlignment','middle');
    xline(pR(p_rate==99), '--', sprintf(' p99=%.3f', pR(p_rate==99)), 'LabelVerticalAlignment','middle');
    ylim(yl);
    hold off;

    % ---- Histogram: Time/guess (ms) ----
    figure('Color','w');
    histogram(t_ms, 'BinMethod','fd');
    grid on;
    xlabel("Time per Argon2id guess (ms)");
    ylabel("Count");
    title(sprintf("Attacker Argon2id GPU time/guess — %s (N=%d)", labels{f}, N), 'Interpreter','none');

    set(gca, 'FontSize', fontSizeAxes);
    set(get(gca,'Title'), 'FontSize', fontSizeTitle, 'FontWeight','normal');

    hold on;
    yl = ylim;
    xline(medt, '-',  sprintf(' median=%.3f', medt), 'LabelVerticalAlignment','middle');
    xline(pt(p_time==95), '--', sprintf(' p95=%.3f', pt(p_time==95)), 'LabelVerticalAlignment','middle');
    xline(pt(p_time==99), '--', sprintf(' p99=%.3f', pt(p_time==99)), 'LabelVerticalAlignment','middle');
    ylim(yl);
    hold off;
end

fprintf("\nDone.\n");
