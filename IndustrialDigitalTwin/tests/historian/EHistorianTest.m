classdef EHistorianTest < matlab.unittest.TestCase
    % EHistorianTest  Test suite for Historian data logger.

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..', '..');
            addpath(fullfile(projectRoot, 'library', 'core'));
            addpath(fullfile(projectRoot, 'library', 'process'));
            addpath(fullfile(projectRoot, 'library', 'historian'));
        end
    end

    methods (Test)
        function testLoggingAndRetrieval(testCase)
            db = ETagDatabase();
            T1 = ETank("ID", "T1", "Diameter", 5, "Height", 10, "InitialLevel", 0);
            db.register(T1);
            
            % Small buffer for testing preallocation expansion
            hist = EHistorian(db, "BufferSize", 5); 
            
            % Run simulation for 10 steps
            for k=1:10
                T1.setFlows(1.0, 0); % fill with 1.0 m3/s
                T1.update(1.0); % 1 sec step
                db.scanAll();
                hist.log();
            end
            
            tt = hist.getHistory("T1.VOLUME");
            
            % We should have 10 rows
            testCase.verifyEqual(height(tt), 10);
            
            % Value should increase by 1.0 each step
            testCase.verifyEqual(tt.Value(1), 1.0, 'RelTol', 1e-12);
            testCase.verifyEqual(tt.Value(10), 10.0, 'RelTol', 1e-12);
            
            % Quality should be good
            testCase.verifyEqual(tt.Quality(1), "GOOD");
        end

        function testFilteredLogging(testCase)
            db = ETagDatabase();
            T1 = ETank("ID", "T1", "Diameter", 5, "Height", 10, "InitialLevel", 0);
            db.register(T1);
            
            % Only log LEVEL, ignore others like VOLUME or ALARM
            hist = EHistorian(db, "Tags", ["T1.LEVEL"]);
            
            db.scanAll();
            hist.log();
            
            tags = hist.getLoggedTags();
            testCase.verifyEqual(length(tags), 1);
            testCase.verifyEqual(tags(1), "T1.LEVEL");
        end
        
        function testEmptyDatabase(testCase)
            db = ETagDatabase();
            hist = EHistorian(db);
            
            % Should not crash
            db.scanAll();
            hist.log();
            
            testCase.verifyError(@() hist.getHistory("ANYTHING"), "EHistorian:NoData");
        end
    end
end
