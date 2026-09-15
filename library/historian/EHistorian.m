classdef EHistorian < handle
    % EHistorian  Time-series data logger for the Digital Twin.
    %
    %   The Historian connects to an ETagDatabase and logs the tag
    %   values at every scan cycle. It provides methods to retrieve
    %   historical data as timetables for analysis, plotting, or AI/ML.
    %
    %   Features:
    %     - Efficient in-memory buffering using preallocated arrays
    %     - Configurable logging rate
    %     - Tag filtering (log all or specific tags)
    %     - Timetable generation for easy MATLAB analysis
    %
    %   Example:
    %     db = ETagDatabase();
    %     % ... register equipment ...
    %     hist = EHistorian(db);
    %     
    %     for k=1:100
    %         db.scanAll();
    %         hist.log();
    %     end
    %     
    %     data = hist.getHistory("T101.LEVEL");
    %
    %   See also: ETagDatabase, timetable

    properties (SetAccess = protected)
        Database (1,1) ETagDatabase
        TagsToLog (:,1) string
        LogAllTags (1,1) logical = true
        
        % Data storage: Map of tag name -> struct with Time and Value arrays
        Storage containers.Map
        CurrentIndex (1,1) double = 0
        BufferSize (1,1) double = 10000 % Preallocation size
    end

    methods
        function obj = EHistorian(db, options)
            % EHistorian  Construct a Historian attached to a database.
            
            arguments
                db (1,1) ETagDatabase
                options.Tags (:,1) string = string.empty
                options.BufferSize (1,1) double = 10000
            end

            obj.Database = db;
            obj.BufferSize = options.BufferSize;
            obj.Storage = containers.Map('KeyType', 'char', 'ValueType', 'any');
            
            if ~isempty(options.Tags)
                obj.TagsToLog = options.Tags;
                obj.LogAllTags = false;
            else
                obj.LogAllTags = true;
            end
        end

        function log(obj)
            % log  Record the current state of the database tags.
            %
            %   This should be called after db.scanAll() to ensure
            %   the data is fresh.

            tbl = obj.Database.MasterTagTable;
            if isempty(tbl)
                return; % Nothing to log
            end
            
            obj.CurrentIndex = obj.CurrentIndex + 1;
            idx = obj.CurrentIndex;
            
            % Determine which tags to process
            if obj.LogAllTags
                tags = cellstr(tbl.Tag);
            else
                tags = cellstr(obj.TagsToLog);
            end
            
            % Fast map for lookup in current table
            % In a real high-performance system, we wouldn't use find() in a loop,
            % but for this digital twin it's sufficient for moderate tag counts.
            
            for i = 1:length(tags)
                tagStr = tags{i};
                
                % Get current tag info from DB
                try
                    info = obj.Database.getTagInfo(tagStr);
                catch
                    continue; % Tag not found, skip
                end
                
                % Initialize storage for this tag if it doesn't exist
                if ~obj.Storage.isKey(tagStr)
                    buffer = struct();
                    buffer.Time = NaT(obj.BufferSize, 1);
                    buffer.Value = NaN(obj.BufferSize, 1);
                    buffer.Quality = strings(obj.BufferSize, 1);
                    
                    obj.Storage(tagStr) = buffer;
                end
                
                % Get buffer
                buffer = obj.Storage(tagStr);
                
                % Expand buffer if needed
                if idx > length(buffer.Value)
                    buffer.Time = [buffer.Time; NaT(obj.BufferSize, 1)];
                    buffer.Value = [buffer.Value; NaN(obj.BufferSize, 1)];
                    buffer.Quality = [buffer.Quality; strings(obj.BufferSize, 1)];
                end
                
                % Store data
                buffer.Time(idx) = info.Timestamp;
                buffer.Value(idx) = info.Value;
                buffer.Quality(idx) = info.Quality;
                
                % Put back in map
                obj.Storage(tagStr) = buffer;
            end
        end

        function tt = getHistory(obj, tagName)
            % getHistory  Retrieve historical data as a timetable.
            %
            %   tt = obj.getHistory(tagName) returns a timetable with
            %   Time, Value, and Quality for the requested tag.

            arguments
                obj
                tagName (1,1) string
            end

            key = char(tagName);
            if obj.Storage.isKey(key)
                buffer = obj.Storage(key);
                
                % Extract only the recorded data (up to CurrentIndex)
                validIdx = 1:obj.CurrentIndex;
                
                Time = buffer.Time(validIdx);
                Value = buffer.Value(validIdx);
                Quality = buffer.Quality(validIdx);
                
                % Create timetable
                tt = timetable(Time, Value, Quality);
                tt.Properties.VariableNames = {'Value', 'Quality'};
            else
                error("EHistorian:NoData", ...
                    "No historical data found for tag '%s'.", tagName);
            end
        end
        
        function tags = getLoggedTags(obj)
            % getLoggedTags  Return a list of all tags currently logged.
            tags = string(obj.Storage.keys())';
        end

        function clearHistory(obj)
            % clearHistory  Reset all logged data.
            obj.Storage = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.CurrentIndex = 0;
        end
    end
end
