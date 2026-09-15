classdef EFlowTransmitter < ETransmitter
    % EFlowTransmitter  Industrial flow transmitter model.
    %
    %   Subclass of ETransmitter specialized for measuring flow rates.
    %   Automatically targets the 'FlowRate' property and assigns 'm3/s'
    %   as the engineering unit in tags.
    %
    %   Example:
    %     FT101 = EFlowTransmitter("ID","FT101","Target",Pipe1,...
    %         "RangeMax", 0.5);
    %
    %   See also: ETransmitter, EPipe, EPump

    methods

        function obj = EFlowTransmitter(options)
            arguments
                options.ID string
                options.Target (1,1) handle
                options.RangeMin (1,1) double = 0
                options.RangeMax (1,1) double = 1.0
                options.NoiseStdDev (1,1) double {mustBeNonnegative} = 0.005
            end

            obj@ETransmitter("ID", options.ID, "Target", options.Target, ...
                "Property", "FlowRate", "RangeMin", options.RangeMin, ...
                "RangeMax", options.RangeMax, "NoiseStdDev", options.NoiseStdDev);
            
            obj.Type = "FlowTransmitter";
            obj.Description = sprintf("Flow Transmitter for %s", options.Target.ID);
        end

        function tags = getTags(obj)
            % getTags  Return transmitter tags with flow units.
            tags = getTags@ETransmitter(obj);
            
            idxPV = (tags.Tag == obj.ID + ".PV") | (tags.Tag == obj.ID + ".RAW_PV");
            tags.Unit(idxPV) = "m3/s";
        end

    end
end
