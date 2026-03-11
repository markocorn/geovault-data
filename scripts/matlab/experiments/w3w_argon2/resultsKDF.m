function generate_hardening_1km()
    % GeoVault Security: Hardening Spectrum (1km Radius, No 16GB)
    % Updates:
    % 1. Title changed to reflect "1km Radius Constraint".
    % 2. Filename updated to 'Hardening_Spectrum_1km.pdf'.
    % 3. 16GB tier remains removed.
    
    clear; clc;
    
    % --- Data Setup ---
    % Label, Speed (H/s), Color (RGB)
    tiers = {
        '64 MB',   4991.0,  [0.85 0.32 0.10]; % Orange/Red
        '1 GB',    285.0,   [0.92 0.69 0.12]; % Yellow-Orange
        '4 GB',    3.07,    [0.46 0.67 0.18]; % Green
        % '16 GB' REMOVED
        '32 GB',   0.026,   [0.30 0.00 0.50]; % Purple
    };
    
    % Thresholds
    T_Human = 1e10;        
    T_BIP39 = 1e32;        
    
    % Variables
    n_points = 1:5; 
    H_spatial_bits = [45.7, 72.5, 99.3, 126.1, 152.9]; 
    L_chars = 4:2:24; 
    H_pwd_bits = L_chars * log2(94); 
    
    % --- Create Figure ---
    figure('Color', 'w', 'Position', [100, 100, 800, 900]); 
    
    % =================================================================
    % SUBPLOT 1 (TOP): SPATIAL SECURITY (1km Radius)
    % =================================================================
    subplot(2,1,1);
    hold on;
    
    % Draw Background (Limit 1e50)
    plot_zones(400, 1e50, T_Human, T_BIP39, 5.5);
    
    for i = 1:size(tiers, 1)
        speed = tiers{i, 2};
        color = tiers{i, 3};
        
        % Calculate full time array
        time_geo_full = (2.^H_spatial_bits) ./ speed;
        
        % Truncation Logic (Stop at BIP-39 Zone)
        idx_cut = find(time_geo_full > T_BIP39, 1, 'first');
        if isempty(idx_cut)
            limit = length(time_geo_full);
        else
            limit = idx_cut;
        end
        
        semilogx(time_geo_full(1:limit), n_points(1:limit), '-o', ...
            'LineWidth', 2, 'Color', color, 'MarkerFaceColor', color, ...
            'DisplayName', tiers{i, 1});
    end
    
    ylabel('Spatial Points (n)', 'FontSize', 12, 'FontWeight', 'bold');
    % Updated Title
    title('A) Geographic Hardening Spectrum (1km Radius Constraint)', 'FontSize', 14);
    xlim([400 1e50]); ylim([0.5 5.5]); yticks(1:5); 
    set(gca, 'XScale', 'log', 'Layer', 'top', 'FontSize', 11);
    grid on;
    legend('Location', 'west', 'FontSize', 10);
    
    % =================================================================
    % SUBPLOT 2 (BOTTOM): LINGUISTIC SECURITY
    % =================================================================
    subplot(2,1,2);
    hold on;
    
    % Draw Background
    plot_zones(400, 1e50, T_Human, T_BIP39, 26);
    
    for i = 1:size(tiers, 1)
        speed = tiers{i, 2};
        color = tiers{i, 3};
        
        % Calculate full time array
        time_pwd_full = (2.^H_pwd_bits) ./ speed;
        
        % Truncation Logic
        idx_cut = find(time_pwd_full > T_BIP39, 1, 'first');
        if isempty(idx_cut)
            limit = length(time_pwd_full);
        else
            limit = idx_cut;
        end
        
        semilogx(time_pwd_full(1:limit), L_chars(1:limit), '-s', ...
            'LineWidth', 2, 'Color', color, 'MarkerFaceColor', color, ...
            'DisplayName', tiers{i, 1});
    end
    
    ylabel('Password Length (Chars)', 'FontSize', 12, 'FontWeight', 'bold');
    xlabel('Attacker Work Factor (Seconds, log_{10})', 'FontSize', 12, 'FontWeight', 'bold');
    title('B) Linguistic Hardening Spectrum', 'FontSize', 14);
    xlim([400 1e50]); ylim([2 26]); 
    set(gca, 'XScale', 'log', 'Layer', 'top', 'FontSize', 11);
    grid on;
    
    % Updated Filename
    exportgraphics(gcf, 'Hardening_Spectrum_1km.pdf', 'ContentType', 'vector');
end

% --- Helper Function ---
function plot_zones(xmin, xmax, t1, t2, ymax)
    patch([xmin t1 t1 xmin], [0 0 ymax ymax], [1 0.95 0.95], 'EdgeColor', 'none', 'HandleVisibility', 'off'); 
    patch([t1 t2 t2 t1], [0 0 ymax ymax], [1 1 0.9], 'EdgeColor', 'none', 'HandleVisibility', 'off');   
    patch([t2 xmax xmax t2], [0 0 ymax ymax], [0.9 1 0.9], 'EdgeColor', 'none', 'HandleVisibility', 'off'); 
    
    text(1e5, ymax*0.9, 'INSECURE', 'Color', [0.7 0 0], 'FontSize', 9, 'FontWeight', 'bold');
    text(1e20, ymax*0.9, 'HUMAN-SECURE', 'Color', [0.6 0.4 0], 'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(1e34, ymax*0.9, 'BIP-39 ZONE', 'Color', [0 0.5 0], 'FontSize', 9, 'FontWeight', 'bold');
end