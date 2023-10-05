%% Model Identification Script
clear; clc; close all

%% Compute the potentiometer and strain constants
compute_constants;

%% Model Identification (Computations)

% Plotting Parameters
plot_plant_data = true;
plot_comparison_data = true;

filenames=dir('ModelIdentificationData\*.mat');

fileID = fopen('ModelIdentificationLog.txt','w');
fprintf(fileID,'LOGGINGS');



for file_id = 1:length(filenames)
    load(['ModelIdentificationData\' filenames(file_id).name], 'ScopeData')

    % Getting the input amplitude and frequency
    filename = split(filenames(file_id).name, '.'); filename_orig = filename{1};
    filename = split(filename_orig, '_');

    amp = split(filename{3}, 'a'); amp = amp{2};
    amp = str2num(amp)/10;

    freq = split(filename{4}, 'f'); freq = freq{2};
    freq = str2num(freq)/10;

    wave = filename{5};

    fprintf(fileID,'\n\nAnalysis for: Amplitude: %1.2f; Frequency: %1.2f; Waveform: %s;\n',amp, freq, wave);

    % Load Time and Signal Values from Scope Data
    t = ScopeData.time;
    sigs = ScopeData.signals.values;
    clear ScopeData

    % Removing the first 5 seconds from the data (using array masking)
    time_array = t(t>=5);
    signal_array = sigs(t>=5, :);
    clear t sigs

    % Signal Data
    utrend = signal_array(:, 1); % Motor Excitation Signals
    thetae = signal_array(:, 2); % Potentiometer Signals
    alphae = signal_array(:, 3); % Strain Gage Signals

    % Estimating bar tip position
    ytrend = kp*thetae + kb*alphae;

    % Plot the u, y and alpha
    if plot_plant_data
        fig = figure();

        subplot(3,1,1)
        plot(time_array,utrend)
        xlabel('Time [secs]')
        ylabel('u [V]')
    
        subplot(3,1,2)
        plot(time_array,thetae)
        xlabel('Time [secs]')
        ylabel('theta [V]')
    
        subplot(3,1,3)
        plot(time_array,alphae)
        xlabel('Time [secs]')
        ylabel('alpha [V]')

        sgtitle( sprintf('Amp = %.2fV Freq = %.2fHz %s Wave', amp, freq, wave) )

        savefig(['ModelIdentificationPlots\ReadData\a' num2str(amp) '_f' num2str(freq) '_wave_' wave '.fig'])
        set(fig, 'visible', 'off');
    end

    % Removing pole at the origin and detrending.
    af = 0.9;
    Afilt = [1, -af];
    Bfilt = (1-af)*[1, -1];
    
    yfilter = filter(Bfilt,Afilt,ytrend); % Differentiating and detrending
    yf = medfilt1(yfilter, 10); % Median Filter

    clear af Afilt Bfilt

    % TODO: Remove the tref average value from the input signal

    u = detrend(utrend); % Removing trend from input signal
    
    % Model Identification with ARMAX
    z = [yf, u];
    
    clear IdentifStruct
    IdentifStruct(14) = struct();
    
    id = 0;

    for na = 3:6 % Poles
        for nb = 1:6 % Zeros
            if nb >= na; continue; end
            id  = id + 1; 

            IdentifStruct(id).pole = na; IdentifStruct(id).zero = nb;

            nc = na; nk = 1; nn = [na, nb, nc, nk];
            IdentifStruct(id).th = armax(z, nn);

            % Simulating the result obtained
            [den1, num1] = polydata( IdentifStruct(id).th ); % Obtaining the numerator and denominator of identified model
            IdentifStruct(id).yfsim = filter(num1, den1, u);
            IdentifStruct(id).tf_num = num1;
            IdentifStruct(id).tf_den = den1;

            % Computing Root Mean Square Error
            IdentifStruct(id).error = sqrt(mean((yf - IdentifStruct(id).yfsim).^2));

            fprintf(fileID,'Npoles: %2d. Nzeros: %2d Error: %1.4f.\n',na, nb, IdentifStruct(id).error );
        end
    end

    % Select the best model based on RMSE
    min_error = min([(IdentifStruct.error)]);
    min_error_id = find([(IdentifStruct.error)] == min_error, 1, 'first' );

    % Get the values of yfsim for the best model.
    fprintf(fileID,'\nBest Model: Npoles: %2d. Nzeros: %2d Error: %1.4f.\n', IdentifStruct(min_error_id).pole, IdentifStruct(min_error_id).zero, IdentifStruct(min_error_id).error );
    
    pole = roots(IdentifStruct(min_error_id).tf_den);
    fprintf(fileID, '\nPoles: %1.5f%+fj', real(pole), imag(pole) );

    zero = roots(IdentifStruct(min_error_id).tf_num);
    fprintf(fileID, '\nZeros: %1.5f%+fj', real(zero), imag(zero) );

    
    % Comparing the results with original data.
    if plot_comparison_data
        fig = figure();

        plot(time_array, yf, '--b', time_array, IdentifStruct(min_error_id).yfsim, '-r')
        
        xlabel('Time [secs]')
        ylabel('Deflection [degs]')
        legend('Data', 'Model')
        title( sprintf('Amp = %.2fV Freq = %.2fHz %s Wave', amp, freq, wave) )

        savefig(['ModelIdentificationPlots\ComparisonPlots\a' num2str(amp) '_f' num2str(freq) '_wave_' wave '.fig'])
        set(fig, 'visible', 'off');
    end
    
    % Poles and Zeros Plots
    fig = figure();
    
    zplane(zero,pole)
    grid
    title('Zero-Pole Plot')

    savefig(['ModelIdentificationPlots\PolesZeros\a' num2str(amp) '_f' num2str(freq) '_wave_' wave '.fig'])
    set(fig, 'visible', 'off');

end
clear filenames file_id

fclose(fileID);

%% Model Identification (Selection)


