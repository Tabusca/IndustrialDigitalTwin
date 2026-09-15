classdef EHeater < Equipment
    % EHeater  Industrial heat exchanger / heater.
    %
    %   Raises temperature of fluid.

    methods
        function obj = EHeater(options)
            arguments
                options.ID string
                options.Capacity (1,1) double = 50000 % Watts
            end
            
            obj.ID = options.ID;
            obj.Type = "Heater";
            obj.Description = "Fluid Heater";
            
            obj.Parameters.Capacity = options.Capacity;
            
            obj.State.TemperatureOut = 20; % degC
            
            obj.Inputs.Flow = 0;
            obj.Inputs.TemperatureIn = 20;
            obj.Inputs.Command = 0; % 0-100% heating
            
            obj.Faults.ElementFailure = false;
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function update(obj, dt)
            % Q = m_dot * Cp * dT
            % dT = Q / (m_dot * Cp)
            
            Cp = 4184; % J/kgK (Water)
            rho = 1000; % kg/m3
            
            flow_kg = obj.Inputs.Flow * rho;
            
            heatPower = obj.Parameters.Capacity * (obj.Inputs.Command / 100);
            if obj.Faults.ElementFailure
                heatPower = 0;
            end
            
            if flow_kg > 0.001
                dT = heatPower / (flow_kg * Cp);
                % Simple first order lag for thermal mass
                targetT = obj.Inputs.TemperatureIn + dT;
                obj.State.TemperatureOut = obj.State.TemperatureOut + (targetT - obj.State.TemperatureOut) * 0.1 * dt;
            else
                % If no flow, temperature rises quickly if heater is on
                if heatPower > 0
                    obj.State.TemperatureOut = obj.State.TemperatureOut + 1.0 * dt;
                else
                    % Cools to ambient
                    obj.State.TemperatureOut = obj.State.TemperatureOut + (20 - obj.State.TemperatureOut) * 0.05 * dt;
                end
            end
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function reset(obj)
            obj.State.TemperatureOut = 20;
            obj.Inputs.Flow = 0;
            obj.Inputs.Command = 0;
            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function tags = getTags(obj)
            now = datetime("now");
            Tag = [obj.ID + ".TEMP_OUT"; obj.ID + ".CMD"];
            Value = [obj.Outputs.TemperatureOut; obj.Inputs.Command];
            Unit = ["degC"; "%"];
            Quality = repmat("GOOD", 2, 1);
            Timestamp = repmat(now, 2, 1);
            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end
    end
    
    methods (Access = protected)
        function faults = getSupportedFaults(~)
            faults = ["ElementFailure"];
        end
        function updateOutputs(obj)
            obj.Outputs.TemperatureOut = obj.State.TemperatureOut;
        end
        function updateStatus(obj)
            if obj.hasAnyFault(), obj.Status = "FAULTED"; else, obj.Status = "OK"; end
        end
    end
end
