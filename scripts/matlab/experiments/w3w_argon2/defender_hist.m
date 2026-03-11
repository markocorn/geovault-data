% argon2_percentile_band_vs_memory_p5_p95.m
% Single chart: RAM (log scale) vs latency (ms) with 90% band (p5–p95)
% Also prints median + percentiles to console.

clear; clc;

% ---- Input files ----
files = {
    'defender_argon2id_cpu_m64MiB_raw.csv'
    'defender_argon2id_cpu_m128MiB_raw.csv'
    'defender_argon2id_cpu_m256MiB_raw.csv'
    'defender_argon2id_cpu_m512MiB_raw.csv'
    'defender_argon2id_cpu_m1024MiB_raw.csv'
    'defender_argon2id_cpu_m2048MiB_raw.csv'
    'defender_argon2id_cpu_m4096MiB_raw.csv'
    'defender_argon2id_cpu_m8192MiB_raw.csv'
};

labels = {'64 MiB','128 MiB','256 MiB','512 MiB','1024 MiB','2048 MiB','4096 MiB','8192 MiB'};
mem_mib = [64 128 256 512 1024 2048 4096 8192];

% ---- Percentiles to compute/print ----
p_list = [1 5 10 25 50 75 90 95 99];

% ---- Load data ----
times = cell(size(files));
for i = 1:numel(files)
    if ~isfile(files{i})
        error('Missing file: %s', files{i});
    end
    T = readtable(files{i});     % expects columns: Run, Time_ms
    if ~ismember('Time_ms', T.Properties.VariableNames)
        error('File %s does not contain column "Time_ms".', files{i});
    end
    x = T.Time_ms;
    x = x(isfinite(x) & x > 0);
    times{i} = x(:);
end

% ---- Compute stats per memory setting ----
nSets = numel(times);

N   = zeros(nSets,1);
mu  = zeros(nSets,1);
sd  = zeros(nSets,1);

p05 = zeros(nSets,1);
p50 = zeros(nSets,1);
p95 = zeros(nSets,1);

% Full percentile table for console
P = zeros(nSets, numel(p_list));

for i = 1:nSets
    x = times{i};
    N(i)  = numel(x);
    mu(i) = mean(x);
    sd(i) = std(x);

    Pi = prctile(x, p_list);
    P(i,:) = Pi;

    p05(i) = Pi(p_list == 5);
    p50(i) = Pi(p_list == 50);
    p95(i) = Pi(p_list == 95);
end

% ---- Plot: RAM (log) vs latency with p5–p95 band ----
figure('Color','w'); hold on; grid on;

x = mem_mib(:);

% 90% band (p5–p95) — visible
x_fill = [x; flipud(x)];
y_fill = [p05; flipud(p95)];
fill(x_fill, y_fill, 'k', 'FaceAlpha', 0.16, 'EdgeColor', 'none');

% Median
plot(x, p50, '-o', 'LineWidth', 2.2, 'MarkerSize', 6);

set(gca, 'XScale', 'log');
xticks(x);
xticklabels(labels);
xtickangle(35);

xlabel('Argon2 memory cost');
ylabel('Time per Argon2id (ms)');
title('Argon2id latency vs memory (median with p5–p95 band)');

legend({'p5–p95 band', 'Median (p50)'}, 'Location', 'northwest');

set(gca, 'FontSize', 14);
set(get(gca,'Title'), 'FontSize', 16, 'FontWeight', 'normal');
set(get(gca,'XLabel'), 'FontSize', 15);
set(get(gca,'YLabel'), 'FontSize', 15);

% ---- Console output ----
fprintf('\nArgon2id latency summary (ms)\n');
fprintf('-------------------------------------------------------------------------------------------------\n');
fprintf('%-10s %6s %10s %10s', 'Mem','N','Mean','Std');
for p = p_list
    if p == 50
        fprintf('%10s', 'Median');
    else
        fprintf('%10s', sprintf('p%d', p));
    end
end
fprintf('\n');

for i = 1:nSets
    fprintf('%-10s %6d %10.3f %10.3f', labels{i}, N(i), mu(i), sd(i));
    for j = 1:numel(p_list)
        fprintf('%10.3f', P(i,j));
    end
    fprintf('\n');
end
fprintf('-------------------------------------------------------------------------------------------------\n\n');
