classdef ETransmitterTest < matlab.unittest.TestCase
    % ETransmitterTest  Comprehensive test suite for Transmitter classes.

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..', '..');
            addpath(fullfile(projectRoot, 'library', 'core'));
            addpath(fullfile(projectRoot, 'library', 'process'));
            addpath(fullfile(projectRoot, 'library', 'instrumentation'));
        end
    end

    methods (Test)
        function testBasicScaling(testCase)
            Tank1 = ETank("ID", "T1", "Diameter", 5.0, "Height", 10.0, "InitialLevel", 5.0);
            LT = ELevelTransmitter("ID", "LT1", "Target", Tank1, "RangeMin", 0, "RangeMax", 10, "NoiseStdDev", 0);
            
            % Initialize
            LT.update(0.1);
            
            % 5m on 0-10m scale is 50%. 4-20mA range: 4 + 0.5*16 = 12mA
            testCase.verifyEqual(LT.Outputs.RawValue, 5.0);
            testCase.verifyEqual(LT.Outputs.MeasuredValue, 5.0);
            testCase.verifyEqual(LT.Outputs.ElectricalSignal, 12.0);
        end

        function testSaturationLimits(testCase)
            Tank1 = ETank("ID", "T1", "Diameter", 5.0, "Height", 20.0, "InitialLevel", 15.0);
            LT = ELevelTransmitter("ID", "LT1", "Target", Tank1, "RangeMin", 0, "RangeMax", 10, "NoiseStdDev", 0);
            
            LT.update(0.1);
            
            % Sensor limit is 5% over-range (10.5m)
            testCase.verifyEqual(LT.Outputs.MeasuredValue, 10.5);
            % Signal limit is 20.5 mA
            testCase.verifyEqual(LT.Outputs.ElectricalSignal, 20.5);
        end
        
        function testNoise(testCase)
            Tank1 = ETank("ID", "T1", "Diameter", 5.0, "Height", 10.0, "InitialLevel", 5.0);
            LT = ELevelTransmitter("ID", "LT1", "Target", Tank1, "NoiseStdDev", 0.5);
            
            LT.update(0.1);
            val1 = LT.Outputs.MeasuredValue;
            LT.update(0.1);
            val2 = LT.Outputs.MeasuredValue;
            
            % Very unlikely to be exactly equal with noise
            testCase.verifyNotEqual(val1, val2);
        end

        function testSignalLossFault(testCase)
            Tank1 = ETank("ID", "T1", "Diameter", 5.0, "Height", 10.0, "InitialLevel", 5.0);
            LT = ELevelTransmitter("ID", "LT1", "Target", Tank1);
            
            LT.injectFault("SignalLoss");
            LT.update(0.1);
            
            testCase.verifyTrue(isnan(LT.Outputs.MeasuredValue));
            testCase.verifyEqual(LT.Outputs.ElectricalSignal, 0.0);
            testCase.verifyEqual(LT.Status, "FAULTED");
        end
        
        function testFrozenSignalFault(testCase)
            Tank1 = ETank("ID", "T1", "Diameter", 5.0, "Height", 10.0, "InitialLevel", 5.0);
            LT = ELevelTransmitter("ID", "LT1", "Target", Tank1, "NoiseStdDev", 0);
            
            LT.update(0.1);
            testCase.verifyEqual(LT.Outputs.MeasuredValue, 5.0);
            
            LT.injectFault("FrozenSignal");
            
            % Change target level
            Tank1.setFlows(1.0, 0); % Fill tank
            Tank1.update(1.0);
            testCase.verifyGreaterThan(Tank1.Outputs.Level, 5.0);
            
            % Transmitter should be frozen at 5.0
            LT.update(1.0);
            testCase.verifyEqual(LT.Outputs.MeasuredValue, 5.0);
        end
        
        function testCalibrationLossFault(testCase)
            Tank1 = ETank("ID", "T1", "Diameter", 5.0, "Height", 20.0, "InitialLevel", 10.0);
            LT = ELevelTransmitter("ID", "LT1", "Target", Tank1, "RangeMax", 100, "NoiseStdDev", 0);
            
            LT.update(0.1);
            testCase.verifyEqual(LT.Outputs.MeasuredValue, 10.0);
            
            LT.injectFault("CalibrationLoss");
            LT.update(0.1);
            
            % 20% span error: 10 * 1.2 = 12.0
            testCase.verifyEqual(LT.Outputs.MeasuredValue, 12.0);
        end
        
        function testUnits(testCase)
            Tank1 = ETank("ID", "T1", "Diameter", 5.0, "Height", 10.0);
            LT = ELevelTransmitter("ID", "LT1", "Target", Tank1);
            Pipe1 = EPipe("ID", "P1", "Length", 10, "Diameter", 0.1);
            FT = EFlowTransmitter("ID", "FT1", "Target", Pipe1);
            PT = EPressureTransmitter("ID", "PT1", "Target", Pipe1, "Property", "PressureDrop", "Unit", "bar");
            
            tLT = LT.getTags();
            tFT = FT.getTags();
            tPT = PT.getTags();
            
            % Find PV tags
            ltPV = tLT(tLT.Tag == "LT1.PV", :);
            ftPV = tFT(tFT.Tag == "FT1.PV", :);
            ptPV = tPT(tPT.Tag == "PT1.PV", :);
            
            testCase.verifyEqual(ltPV.Unit(1), "m");
            testCase.verifyEqual(ftPV.Unit(1), "m3/s");
            testCase.verifyEqual(ptPV.Unit(1), "bar");
        end
    end
end
