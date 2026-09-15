classdef EPumpTest < matlab.unittest.TestCase
    % EPumpTest  Comprehensive test suite for the EPump class.

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
            Pump1 = EPump("ID", "Pump1", "RatedFlow", 1.0, "RatedHead", 50, "RatedSpeed", 3000);
            testCase.verifyEqual(Pump1.ID, "Pump1");
            testCase.verifyEqual(Pump1.Parameters.Rated.Flow, 1.0);
            testCase.verifyEqual(Pump1.Parameters.Rated.Head, 50);
            testCase.verifyEqual(Pump1.Parameters.Rated.Speed, 3000);
            testCase.verifyEqual(Pump1.Parameters.Curve.ShutoffHead, 1.25 * 50);
        end

        function testPumpCurve(testCase)
            Pump1 = EPump("ID", "Pump1", "RatedFlow", 1.0, "RatedHead", 50, "RatedSpeed", 3000);
            
            % Shutoff head (Q=0)
            H_shutoff = Pump1.computeHead(0, 3000);
            testCase.verifyEqual(H_shutoff, 1.25 * 50, 'RelTol', 1e-12);
            
            % Rated head (Q=RatedFlow)
            H_rated = Pump1.computeHead(1.0, 3000);
            testCase.verifyEqual(H_rated, 50, 'RelTol', 1e-12);
        end

        function testDynamicsAndSteadyState(testCase)
            Pump1 = EPump("ID", "Pump1", "RatedFlow", 1.0, "RatedHead", 50, "RatedSpeed", 3000, "SpeedTimeConstant", 1.0);
            Pump1.start();
            Pump1.setInput("FlowRate", 1.0);
            
            % Simulate for enough time to reach steady state
            dt = 0.1;
            for i=1:100
                Pump1.update(dt);
            end
            
            testCase.verifyEqual(Pump1.Outputs.Speed, 3000, 'RelTol', 1e-4);
            testCase.verifyEqual(Pump1.Outputs.Head, 50, 'RelTol', 1e-4);
            testCase.verifyTrue(Pump1.Outputs.Running);
        end

        function testMotorFailureFault(testCase)
            Pump1 = EPump("ID", "Pump1", "RatedFlow", 1.0, "RatedHead", 50, "RatedSpeed", 3000, "SpeedTimeConstant", 1.0);
            Pump1.start();
            
            for i=1:100, Pump1.update(0.1); end
            
            % Inject fault
            Pump1.injectFault("MotorFailure");
            for i=1:200, Pump1.update(0.1); end
            
            testCase.verifyEqual(Pump1.Outputs.Speed, 0, 'AbsTol', 1e-4);
            testCase.verifyFalse(Pump1.Outputs.Running);
            testCase.verifyEqual(Pump1.Status, "FAULTED");
        end

        function testBearingFaultPower(testCase)
            Pump1 = EPump("ID", "Pump1", "RatedFlow", 1.0, "RatedHead", 50, "RatedSpeed", 3000, "Efficiency", 0.8, "SpeedTimeConstant", 0.1);
            Pump1.start();
            Pump1.setInput("FlowRate", 1.0);
            for i=1:50, Pump1.update(0.1); end
            
            P_normal = Pump1.Outputs.Power;
            
            Pump1.injectFault("BearingFault");
            Pump1.update(0.1);
            P_fault = Pump1.Outputs.Power;
            
            % Efficiency reduced by 30% -> Power = P_hyd / (0.8 * 0.7) = P_normal / 0.7
            testCase.verifyEqual(P_fault, P_normal / 0.7, 'RelTol', 1e-12);
        end

        function testReset(testCase)
            Pump1 = EPump("ID", "Pump1", "RatedFlow", 1.0, "RatedHead", 50);
            Pump1.start();
            Pump1.update(1);
            
            Pump1.reset();
            testCase.verifyFalse(Pump1.Outputs.Running);
            testCase.verifyEqual(Pump1.Outputs.Speed, 0);
            testCase.verifyEqual(Pump1.Outputs.Head, 0);
        end
        
        function testTags(testCase)
            Pump1 = EPump("ID", "Pump1", "RatedFlow", 1.0, "RatedHead", 50);
            tags = Pump1.getTags();
            testCase.verifyEqual(height(tags), 9);
            testCase.verifyTrue(ismember('Tag', tags.Properties.VariableNames));
            testCase.verifyTrue(any(tags.Tag == "Pump1.POWER"));
        end
    end
end
