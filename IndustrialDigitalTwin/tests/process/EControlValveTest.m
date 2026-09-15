classdef EControlValveTest < matlab.unittest.TestCase
    % EControlValveTest  Comprehensive test suite for the EControlValve class.

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..', '..');
            addpath(fullfile(projectRoot, 'library', 'core'));
            addpath(fullfile(projectRoot, 'library', 'process'));
        end
    end

    methods (Test)
        function testConstruction(testCase)
            CV1 = EControlValve("ID", "CV1", "Characteristic", "linear", "TimeConstant", 2.0);
            testCase.verifyEqual(CV1.ID, "CV1");
            testCase.verifyEqual(CV1.Parameters.Characteristic, "linear");
            testCase.verifyEqual(CV1.Parameters.Actuator.TimeConstant, 2.0);
            testCase.verifyEqual(CV1.Outputs.Position, 0);
        end

        function testFirstOrderDynamics(testCase)
            CV1 = EControlValve("ID", "CV1", "TimeConstant", 1.0);
            CV1.setCommand(100); % Step to 1.0 position
            
            % Exact analytical solution for first order: y(t) = 1 - exp(-t/tau)
            dt = 0.1;
            for i=1:10
                CV1.update(dt);
            end
            % After 1 sec (t = tau), response should be approx 1 - exp(-1) = 0.632
            % But Euler integration used in class gives an approximation
            % Let's verify it reaches 99% within 5 time constants (5 seconds)
            for i=1:40
                CV1.update(dt);
            end
            
            testCase.verifyGreaterThan(CV1.Outputs.Position, 0.98);
        end

        function testLinearCharacteristic(testCase)
            CV1 = EControlValve("ID", "CV1", "Characteristic", "linear", "TimeConstant", 1.0);
            f = CV1.computeCharacteristic(0.5);
            testCase.verifyEqual(f, 0.5, 'RelTol', 1e-12);
        end

        function testEqualPercentageCharacteristic(testCase)
            CV1 = EControlValve("ID", "CV1", "Characteristic", "equalpercentage", "Rangeability", 50);
            f0 = CV1.computeCharacteristic(0);
            testCase.verifyEqual(f0, 1/50, 'RelTol', 1e-12);
            
            f1 = CV1.computeCharacteristic(1);
            testCase.verifyEqual(f1, 1, 'RelTol', 1e-12);
            
            f_half = CV1.computeCharacteristic(0.5);
            testCase.verifyEqual(f_half, 50^(-0.5), 'RelTol', 1e-12);
        end

        function testQuickOpeningCharacteristic(testCase)
            CV1 = EControlValve("ID", "CV1", "Characteristic", "quickopening");
            f = CV1.computeCharacteristic(0.25);
            testCase.verifyEqual(f, 0.5, 'RelTol', 1e-12);
        end

        function testStuckFault(testCase)
            CV1 = EControlValve("ID", "CV1", "TimeConstant", 1.0);
            CV1.setCommand(50);
            for i=1:20, CV1.update(0.1); end
            
            pos1 = CV1.Outputs.Position;
            
            % Inject stuck fault
            CV1.injectFault("Stuck");
            CV1.setCommand(100);
            for i=1:20, CV1.update(0.1); end
            
            testCase.verifyEqual(CV1.Outputs.Position, pos1, 'RelTol', 1e-12);
            testCase.verifyEqual(CV1.Status, "FAULTED");
        end

        function testActuatorFailureFault(testCase)
            CV1 = EControlValve("ID", "CV1", "TimeConstant", 1.0, "FailPosition", 0);
            CV1.setCommand(100);
            for i=1:50, CV1.update(0.1); end
            testCase.verifyGreaterThan(CV1.Outputs.Position, 0.95);
            
            % Actuator failure should drive valve to fail position (0)
            CV1.injectFault("ActuatorFailure");
            for i=1:50, CV1.update(0.1); end
            
            testCase.verifyLessThan(CV1.Outputs.Position, 0.05);
        end

        function testTags(testCase)
            CV1 = EControlValve("ID", "CV1");
            tags = CV1.getTags();
            testCase.verifyEqual(height(tags), 8);
            testCase.verifyTrue(any(tags.Tag == "CV1.POSITION"));
            testCase.verifyTrue(any(tags.Tag == "CV1.COMMAND"));
        end
    end
end
