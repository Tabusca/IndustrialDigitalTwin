classdef EPressureTransmitter < ETransmitter
    % EPressureTransmitter  Industrial pressure transmitter model.
    %
    %   Subclass of ETransmitter specialized for measuring pressure or head.
    %   Can target properties like 'PressureDrop' (Pipes) or 'Head' (Pumps).
    %
    %   Example:
    %     PT101 = EPressureTransmitter("ID","PT101","Target",Pump1,...
    %         "Property","Head","RangeMax", 50, "Unit", "m");
    %
    %   See also: ETransmitter, EPipe, EPump

    properties (SetAccess = protected)
        UnitString string
    end

    methods

        function obj = EPressureTransmitter(options)
            arguments
                options.ID string
                options.Target (1,1) handle
                options.Property (1,1) string = "PressureDrop"
                options.RangeMin (1,1) double = 0
                options.RangeMax (1,1) double = 100000 % 1 bar default
                options.NoiseStdDev (1,1) double {mustBeNonnegative} = 100
                options.Unit (1,1) string = "Pa"
            end

            obj@ETransmitter("ID", options.ID, "Target", options.Target, ...
                "Property", options.Property, "RangeMin", options.RangeMin, ...
                "RangeMax", options.RangeMax, "NoiseStdDev", options.NoiseStdDev);
            
            obj.Type = "PressureTransmitter";
            obj.Description = sprintf("Pressure Transmitter for %s", options.Target.ID);
            obj.UnitString = options.Unit;
        end

        function tags = getTags(obj)
            % getTags  Return transmitter tags with pressure units.
            tags = getTags@ETransmitter(obj);
            
            idxPV = (tags.Tag == obj.ID + ".PV") | (tags.Tag == obj.ID + ".RAW_PV");
            tags.Unit(idxPV) = obj.UnitString;
        end

    end
end
