classdef EMixer < Equipment
    % EMixer  Industrial mixer tank.
    %
    %   Mixes two inflows, tracks composition (concentration).

    methods
        function obj = EMixer(options)
            arguments
                options.ID string
                options.Volume (1,1) double = 10 % m3
            end
            
            obj.ID = options.ID;
            obj.Type = "Mixer";
            obj.Description = "Stirred Tank Mixer";
            
            obj.Parameters.Volume = options.Volume;
            
            obj.State.Level = 0; % fraction 0-1
            obj.State.Concentration = 0; % 0-1
            
            obj.Inputs.FlowA = 0;
            obj.Inputs.ConcA = 1.0;
            obj.Inputs.FlowB = 0;
            obj.Inputs.ConcB = 0.0;
            obj.Inputs.FlowOut = 0;
            
            obj.Faults.AgitatorFailure = false;
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function update(obj, dt)
            V = obj.Parameters.Volume;
            
            % Mass balance
            Qin = obj.Inputs.FlowA + obj.Inputs.FlowB;
            Qout = obj.Inputs.FlowOut;
            dV = (Qin - Qout) * dt;
            
            currentVol = obj.State.Level * V;
            newVol = currentVol + dV;
            newVol = max(0, min(V, newVol));
            
            % Component balance
            if newVol > 0 && ~obj.Faults.AgitatorFailure
                massIn = obj.Inputs.FlowA * obj.Inputs.ConcA + obj.Inputs.FlowB * obj.Inputs.ConcB;
                currentMass = currentVol * obj.State.Concentration;
                massOut = Qout * obj.State.Concentration;
                
                newMass = currentMass + (massIn - massOut) * dt;
                obj.State.Concentration = newMass / newVol;
            end
            % If agitator fails, perfect mixing assumption breaks down.
            % We simulate this by stopping concentration updates.
            
            obj.State.Level = newVol / V;
            
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function reset(obj)
            obj.State.Level = 0;
            obj.State.Concentration = 0;
            obj.Inputs.FlowA = 0;
            obj.Inputs.FlowB = 0;
            obj.Inputs.FlowOut = 0;
            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end
        
        function tags = getTags(obj)
            now = datetime("now");
            Tag = [obj.ID + ".LEVEL"; obj.ID + ".CONC"];
            Value = [obj.Outputs.Level; obj.Outputs.Concentration];
            Unit = ["%"; "%"];
            Quality = repmat("GOOD", 2, 1);
            Timestamp = repmat(now, 2, 1);
            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end
    end
    
    methods (Access = protected)
        function faults = getSupportedFaults(~)
            faults = ["AgitatorFailure"];
        end
        function updateOutputs(obj)
            obj.Outputs.Level = obj.State.Level * 100;
            obj.Outputs.Concentration = obj.State.Concentration * 100;
        end
        function updateStatus(obj)
            if obj.hasAnyFault(), obj.Status = "FAULTED"; else, obj.Status = "OK"; end
        end
    end
end
