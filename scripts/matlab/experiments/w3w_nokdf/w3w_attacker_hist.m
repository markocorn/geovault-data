% w3w_attacker_sha256_hist.m
% Robust version: does not assume exact column names

clear; clc;

csvFile = "w3w_attacker_sha256_gpu_raw_results.csv";

T = readtable(csvFile, 'TextType','string');

% ---- Debug: show actual variable names (keep once if needed) ----
disp("Detected table variables:");
disp(T.Properties.VariableNames);

% ---- Locate throughput column robustly ----
vars = T.Properties.VariableNames;

idx = find(contains(vars, "Total", 'IgnoreCase', true) & ...
           contains(vars, "H",     'IgnoreCase', true), 1);

if isempty(idx)
    error("Could not locate throughput column. Found variables: %s", ...
        strjoin(vars, ", "));
end

R = T{:, idx};
if ~isnumeric(R)
    R = str2double(string(R));
end

% Drop invalid rows
R = R(~isnan(R) & R > 0);

% ---- Derived quantities ----
N = numel(R);

R_GHs = R / 1e9;        % throughput in GH/s
t_ns  = (1 ./ R) * 1e9; % time per check in ns

% ---- Statistics ----
muR  = mean(R_GHs);
sdR  = std(R_GHs);
medR = median(R_GHs);
pR   = prctile(R_GHs, [5 50 95 99]);

mut  = mean(t_ns);
sdt  = std(t_ns);
medt = median(t_ns);
pt   = prctile(t_ns, [90 95 99]);

% ---- Print summary ----
fprintf("File: %s\n", csvFile);
fprintf("N runs             : %d\n", N);
fprintf("Mean throughput    : %.4f GH/s\n", muR);
fprintf("Std dev throughput : %.4f GH/s\n", sdR);
fprintf("Median throughput  : %.4f GH/s\n", medR);
fprintf("P05/P50/P95/P99    : %.4f  %.4f  %.4f  %.4f GH/s\n", pR);
fprintf("\n");
fprintf("Mean time/check    : %.3f ns\n", mut);
fprintf("Std dev time/check : %.3f ns\n", sdt);
fprintf("Median time/check  : %.3f ns\n", medt);
fprintf("P90/P95/P99        : %.3f  %.3f  %.3f ns\n", pt);

% ---- Histogram: Throughput (recommended for paper) ----
figure;
histogram(R_GHs, 'BinMethod','fd');
grid on;
xlabel("SHA-256 throughput (GH/s)");
ylabel("Count");
title(sprintf("W3W Attacker Throughput (N=%d)", N), 'Interpreter','none');

hold on;
yl = ylim;
xline(medR, '-',  sprintf(' median=%.3f', medR), 'LabelVerticalAlignment','middle');
xline(pR(3), '--', sprintf(' P95=%.3f', pR(3)), 'LabelVerticalAlignment','middle');
xline(pR(4), '--', sprintf(' P99=%.3f', pR(4)), 'LabelVerticalAlignment','middle');
ylim(yl);
hold off;
