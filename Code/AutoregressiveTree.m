%% Read the output file

clear

filename = '5ZoneSteamBaseboard.csv';
[~,~,RawData] = xlsread(filename);

% First 48 numeric entries in the excel file correspond to design days.
% These must be excluded. Higher start index can be chosen to account for
% autoregrssive part
OrderOfAR = 4; % less than 24 here
StartIndex = 242;

%% Organize the data

% Input Variables
InputData = {};

% Training Features without autoregressive contribution
% Specify the features from EnergyPlus .idf output variables
% TrainingData{end+1}.Name = '';
InputData{end+1}.Name = 'Environment:Site Outdoor Air Drybulb Temperature [C](Hourly)';
InputData{end+1}.Name = 'Environment:Site Direct Solar Radiation Rate per Area [W/m2](Hourly)';
InputData{end+1}.Name = 'Environment:Site Outdoor Air Relative Humidity [%](Hourly)';
InputData{end+1}.Name = 'Environment:Site Wind Speed [m/s](Hourly)';
InputData{end+1}.Name = 'Environment:Site Wind Direction [deg](Hourly)';
InputData{end+1}.Name = 'SPACE1-1:Zone People Occupant Count [](Hourly)';
InputData{end+1}.Name = 'SPACE1-1:Zone Lights Total Heating Energy [J](Hourly)';
InputData{end+1}.Name = 'SPACE1-1 BASEBOARD:Baseboard Total Heating Rate [W](Hourly)';

for idx = 1:size(InputData,2)
    for idy = 1:size(RawData,2)
        if strcmp(RawData{1,idy}, InputData{idx}.Name)
            InputData{idx}.Data = RawData(StartIndex:end,idy);
        end
    end
end

NoOfDataPoints = size(InputData{1}.Data,1);

% Training Features with autoregressive contribution
% 'SPACE1-1:Zone Air Temperature [C](Hourly)';

ARVariable.Name = 'SPACE1-1:Zone Air Temperature [C](Hourly)';

for idx = 1:OrderOfAR
    for idy = 1:size(RawData,2)
        if strcmp(RawData{1,idy}, ARVariable.Name)
%             ARVariable.Data = RawData(50:end,idy);
            InputData{end+1}.Name = [ARVariable.Name '(k-' num2str(idx) ')'];
            InputData{end}.Data = RawData(StartIndex-idx:StartIndex-idx+NoOfDataPoints-1,idy);
        end
    end
end
% Reference for day of week
% Example: Start Day  = Monday
% Mon = 0, Tue = 1, Wed = 2, Thur = 3, Fri = 4, Sat = 5, Sun = 6

NoOfDays = NoOfDataPoints/24;
InputData{end+1}.Name = 'Day';

x1 = [0:NoOfDataPoints-1]';
x2 = mod(x1,24);
InputData{end}.Data = mod((x1-x2)/24,7);

% Time of day
InputData{end+1}.Name = 'Time';
for idy = 1:size(RawData,2)
    if strcmp(RawData{1,idy}, 'Date/Time')
        InputData{end}.Data = RawData(StartIndex:end,idy);
        chartime = char(InputData{end}.Data);
        InputData{end}.Data = str2num(chartime(:,9:10)); %#ok<ST2NM>
    end
end

% Output Variables
NoOfOutput = 1;
OutputData = {};
OutputData{end+1}.Name = 'SPACE1-1:Zone Air Temperature [C](Hourly)';
for idx = 1:NoOfOutput
    for idy = 1:size(RawData,2)
        if strcmp(RawData{1,idy}, OutputData{idx}.Name)
            OutputData{idx}.Data = RawData(StartIndex:end,idy);
        end
    end
end

%% Divide into training and testing data

NoOfFeatures = size(InputData,2);
Input = zeros(NoOfDataPoints, NoOfFeatures);
for idx = 1:NoOfFeatures
    if iscell(InputData{idx}.Data)
        Input(:,idx) = cell2mat(InputData{idx}.Data);
    else
        Input(:,idx) = InputData{idx}.Data;
    end
end

TrainingDays = 60;
TrainingInput = Input(1:24*TrainingDays,:);
TestingInput = Input(1+24*TrainingDays:end,:);

Output = cell2mat(OutputData{1}.Data);
TrainingOutput = Output(1:24*TrainingDays,:);

%% Optimal ARMAX model
% Caution training data without autoregression features should be used
% i.e. OrderOfAR = 0;

% ARMAXTrainingdata = iddata(TrainingOutput, TrainingInput, 3600);
% ARMAXTestingdata = iddata(TestingOutput, TestingInput, 3600);
% 
% LossARMAX = arxstruc(ARMAXTrainingdata, ARMAXTestingdata, struc(1:10,1:10,0));
% bestARMAXOrder = selstruc(LossARMAX,0); % best ARMAX order

%% Fit regression tree

rtree = fitrtree(TrainingInput, TrainingOutput, 'MinLeafSize',10);
[~,~,~,bestLevel] = cvloss(rtree, 'SubTrees', 'all', 'KFold', 5);
view(rtree, 'Mode', 'graph');

prunedrtree = prune(rtree, 'Level', bestLevel);
% view(prunedtree, 'Mode', 'graph');


%% Fit boosted tree

brtree = fitensemble(TrainingInput, TrainingOutput, 'LSBoost', 500, 'Tree');

%% Predict results

ActualOutput = Output(1+24*TrainingDays:end,:);

rtreeOutput = predict(rtree, TestingInput);
brtreeOutput = predict(brtree, TestingInput);

rtreeNRMSE = sqrt(mean((rtreeOutput-ActualOutput).^2))/mean(ActualOutput);
brtreeNRMSE = sqrt(mean((brtreeOutput-ActualOutput).^2))/mean(ActualOutput);

figure; hold on;
title(['Order of AR = ' num2str(OrderOfAR)]);
h1 = plot(1:length(ActualOutput), ActualOutput, 'b');
h2 = plot(1:length(ActualOutput), rtreeOutput, 'r');
h3 = plot(1:length(ActualOutput), brtreeOutput, '--g');
% h4 = plot(1:length(ActualOutput), ActualOutput, 'b');
legend([h1, h2, h3], 'Actual', ['Single Tree ' num2str(rtreeNRMSE,2)], ['Boosted Tree ' num2str(brtreeNRMSE,2)])

