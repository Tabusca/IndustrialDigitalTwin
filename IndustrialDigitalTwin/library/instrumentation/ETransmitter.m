classdef ETransmitter < Equipment
    % ETransmitter  Industrial sensor/transmitter model.
    %
    %   ETransmitter models a field device that measures a physical
    %   property from a Target equipment object and converts it into
    %   a scaled industrial signal (e.g., 4-20 mA).
    %
    %   Features:
    %     - Target binding (reads directly from Equipment.Outputs)
    %     - Gaussian noise injection
    %     - Linear drift simulation (zero and span)
    %     - Signal scaling (Engineering Units to 4-20mA)
    %     - NAMUR NE43 fault states (Signal loss = <3.6mA)
    %
    %   Signal Conversion:
    %     Normalized = (Value - RangeMin) / (RangeMax - RangeMin)
    %     Electrical = 4 + 16 * Normalized
    %
    %   Faults:
    %     FrozenSignal - The output stops updating, holding the last value.
    %     SignalLoss   - The electrical signal drops to 0 mA (cable break),
    %                    and MeasuredValue goes to NaN.
    %     CalibrationLoss - Introduces a massive 20% span error.
    %
    %   Parameters:
    %     Target       - Handle to the Equipment being measured
    %     Property     - String name of the field in Target.Outputs
    %     RangeMin     - Lower bound of measurement range (EU)
    %     RangeMax     - Upper bound of measurement range (EU)
    %     NoiseStdDev  - Standard deviation of Gaussian noise (EU)
    %
    %   Outputs:
    %     MeasuredValue    [EU] - The corrupted measurement in Eng. Units
    %     ElectricalSignal [mA] - The 4-20mA scaled equivalent
    %     RawValue         [EU] - The perfect true value from the target
    %
    %   Example:
    %     Tank1 = ETank("ID","T1","Height",10);
    %     LT101 = ETransmitter("ID","LT101","Target",Tank1,...
    %         "Property","Level","RangeMin",0,"RangeMax",10,...
    %         "NoiseStdDev",0.01);
    %     LT101.update(0.1);
    %     fprintf('mA: %.2f\n', LT101.Outputs.ElectricalSignal);
    %
    %   See also: Equipment, ELevelTransmitter, EFlowTransmitter


    properties (SetAccess = protected)
        Target          % Handle to the target equipment
        TargetProperty string  % Property name in Target.Outputs
    end


    methods

        function obj = ETransmitter(options)
            % ETransmitter  Construct a transmitter.

            arguments
                options.ID string
                options.Target (1,1) handle
                options.Property (1,1) string
                options.RangeMin (1,1) double = 0
                options.RangeMax (1,1) double = 100
                options.NoiseStdDev (1,1) double {mustBeNonnegative} = 0.0
            end

            if options.RangeMin >= options.RangeMax
                error("ETransmitter:InvalidRange", ...
                    "RangeMin must be less than RangeMax.");
            end

            % Identity
            obj.ID = options.ID;
            obj.Type = "Transmitter";
            obj.Description = sprintf("Transmitter for %s.%s", ...
                options.Target.ID, options.Property);

            % Bindings
            obj.Target = options.Target;
            obj.TargetProperty = options.Property;

            % Parameters
            obj.Parameters.Range.Min = options.RangeMin;
            obj.Parameters.Range.Max = options.RangeMax;
            obj.Parameters.Noise.StdDev = options.NoiseStdDev;
            
            % Drift parameters (can be modified externally to simulate wear)
            obj.Parameters.Drift.Zero = 0.0; % Additive offset in EU
            obj.Parameters.Drift.Span = 1.0; % Multiplicative factor

            % State
            obj.State.RawValue = 0;
            obj.State.MeasuredValue = 0;
            obj.State.ElectricalSignal = 4.0;
            obj.State.FrozenValue = NaN;

            % Faults
            obj.Faults.FrozenSignal = false;
            obj.Faults.SignalLoss = false;
            obj.Faults.CalibrationLoss = false;

            % Initialize outputs
            obj.updateOutputs();
            obj.updateStatus();
        end


        function update(obj, dt)
            % update  Read from target and compute signal.
            
            arguments
                obj
                dt (1,1) double {mustBePositive}
            end

            % --- 1. Read true value from target ---
            try
                trueValue = obj.Target.Outputs.(obj.TargetProperty);
            catch
                % If property doesn't exist or target is invalid, output NaN
                trueValue = NaN;
            end
            
            obj.State.RawValue = trueValue;

            % --- 2. Process Faults & Signal ---
            
            if obj.Faults.SignalLoss
                % Cable broken / power lost
                obj.State.MeasuredValue = NaN;
                obj.State.ElectricalSignal = 0.0; % NAMUR < 3.6mA indicates failure
                
            elseif obj.Faults.FrozenSignal
                % Analog-to-Digital converter locked up
                if isnan(obj.State.FrozenValue)
                    % Capture value on first freeze tick
                    obj.State.FrozenValue = obj.State.MeasuredValue;
                end
                % Maintain frozen value, electrical signal stays same
                
            else
                % Normal operation (reset frozen state if fault cleared)
                obj.State.FrozenValue = NaN;
                
                % Add Noise
                noise = randn() * obj.Parameters.Noise.StdDev;
                
                % Add Drift (and massive error if CalibrationLoss)
                zeroDrift = obj.Parameters.Drift.Zero;
                spanDrift = obj.Parameters.Drift.Span;
                
                if obj.Faults.CalibrationLoss
                    spanDrift = spanDrift * 1.20; % 20% span error
                end
                
                % Corrupted value
                val = (trueValue * spanDrift) + zeroDrift + noise;
                
                % Clamp to realistic sensor limits (e.g. 5% over-range)
                rMin = obj.Parameters.Range.Min;
                rMax = obj.Parameters.Range.Max;
                span = rMax - rMin;
                
                val = max(rMin - 0.05*span, min(rMax + 0.05*span, val));
                obj.State.MeasuredValue = val;
                
                % Convert to 4-20mA
                normalized = (val - rMin) / span;
                mA = 4.0 + 16.0 * normalized;
                
                % Clamp mA signal to 3.8 - 20.5 mA typical limits
                obj.State.ElectricalSignal = max(3.8, min(20.5, mA));
            end

            obj.updateOutputs();
            obj.updateStatus();
        end


        function reset(obj)
            % reset  Clear faults and reset state.

            obj.State.RawValue = 0;
            obj.State.MeasuredValue = 0;
            obj.State.ElectricalSignal = 4.0;
            obj.State.FrozenValue = NaN;
            
            % Reset drift
            obj.Parameters.Drift.Zero = 0.0;
            obj.Parameters.Drift.Span = 1.0;

            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end


        function tags = getTags(obj)
            % getTags  Return transmitter industrial tags.

            now = datetime("now");
            statusCode = 0;
            
            % Determine quality code based on faults
            if obj.Faults.SignalLoss
                qual = "BAD_COMM";
                statusCode = 3;
            elseif obj.Faults.FrozenSignal
                qual = "UNCERTAIN_STALE";
                statusCode = 2;
            elseif obj.Faults.CalibrationLoss
                qual = "UNCERTAIN_CALIBRATION";
                statusCode = 2;
            else
                qual = "GOOD";
                statusCode = 0;
            end

            Tag = [
                obj.ID + ".PV"         % Process Value (Measured)
                obj.ID + ".SIGNAL"     % 4-20mA signal
                obj.ID + ".RAW_PV"     % True physical value (for twin logic)
                obj.ID + ".FAULT_LOSS"
                obj.ID + ".FAULT_FREEZE"
                obj.ID + ".FAULT_CAL"
                obj.ID + ".STATUS"
            ];

            Value = [
                obj.Outputs.MeasuredValue
                obj.Outputs.ElectricalSignal
                obj.Outputs.RawValue
                double(obj.Faults.SignalLoss)
                double(obj.Faults.FrozenSignal)
                double(obj.Faults.CalibrationLoss)
                statusCode
            ];

            % Units are somewhat dynamic, we leave them blank or generic here.
            % Subclasses can override getTags to provide specific units.
            Unit = ["EU";"mA";"EU";"-";"-";"-";"-"];
            Quality = repmat(string(qual), length(Tag), 1);
            Timestamp = repmat(now, length(Tag), 1);

            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end

    end


    methods (Access = protected)

        function faults = getSupportedFaults(~)
            faults = ["SignalLoss", "FrozenSignal", "CalibrationLoss"];
        end

        function updateOutputs(obj)
            obj.Outputs.RawValue = obj.State.RawValue;
            obj.Outputs.MeasuredValue = obj.State.MeasuredValue;
            obj.Outputs.ElectricalSignal = obj.State.ElectricalSignal;
        end

        function updateStatus(obj)
            if obj.hasAnyFault()
                obj.Status = "FAULTED";
            else
                obj.Status = "OK";
            end
        end

    end

end
