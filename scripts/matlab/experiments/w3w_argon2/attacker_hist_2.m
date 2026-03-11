% analyze_argon2_gpu.m
% Analyzes Argon2 GPU Sweep Data (Mean & Percentiles)

% 1. Load Data
filename = 'argon2_gpu_sweep_1g_to_8g.csv';

% Set up options to preserve variable names (Mem_MiB, Speed_Hs, etc.)
opts = detectImportOptions(filename);
opts.VariableNamingRule = 'preserve'; 
data = readtable(filename, opts);

% 2. Get Unique Memory Sizes
mem_sizes = unique(data.Mem_MiB);

% 3. Initialize Results Table
results = table();

fprintf('---------------------------------------------------------------------------------------\n');
fprintf('Analysis of GPU Argon2id Performance (RTX A6000)\n');
fprintf('---------------------------------------------------------------------------------------\n');
fprintf('%-10s | %-12s | %-10s | %-10s | %-10s | %-10s | %-10s\n', ...
    'Mem (MiB)', 'Mean (H/s)', 'P05', 'P25', 'Median', 'P75', 'P95');
fprintf('---------------------------------------------------------------------------------------\n');

for i = 1:length(mem_sizes)
    mem = mem_sizes(i);
    
    % Filter rows for current memory size
    subset = data(data.Mem_MiB == mem, :);
    speed = subset.Speed_Hs;
    
    % Calculate Statistics
    avg_speed = mean(speed);
    p_tiles = prctile(speed, [5, 25, 50, 75, 95]);
    
    % Display Row
    fprintf('%-10d | %-12.4f | %-10.4f | %-10.4f | %-10.4f | %-10.4f | %-10.4f\n', ...
        mem, avg_speed, p_tiles(1), p_tiles(2), p_tiles(3), p_tiles(4), p_tiles(5));
        
    % Store in Table for later use or export
    newRow = table(mem, avg_speed, p_tiles(1), p_tiles(2), p_tiles(3), p_tiles(4), p_tiles(5), ...
        'VariableNames', {'Mem_MiB', 'Mean_Hs', 'P05', 'P25', 'Median_P50', 'P75', 'P95'});
    results = [results; newRow];
end

fprintf('---------------------------------------------------------------------------------------\n');

% 4. (Optional) Plotting
figure('Name', 'Argon2 GPU Performance Analysis');
loglog(results.Mem_MiB, results.Mean_Hs, '-s', 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', 'b');
grid on;
xlabel('Memory Cost (MiB)');
ylabel('Hashrate (H/s)');
title('Argon2id Attacker Performance (RTX A6000)');
xticks(results.Mem_MiB);
xticklabels(string(results.Mem_MiB));