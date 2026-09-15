classdef EConnection < handle
    % EConnection  Links equipment outputs to inputs.
    %
    %   Transfers a value from Source.Outputs.(SourceProp) to
    %   Target.Inputs.(TargetProp).

    properties
        Source 
        SourceProp string
        Target 
        TargetProp string
    end
    
    methods
        function obj = EConnection(src, srcProp, tgt, tgtProp)
            obj.Source = src;
            obj.SourceProp = srcProp;
            obj.Target = tgt;
            obj.TargetProp = tgtProp;
        end
        
        function update(obj)
            % Transfer value
            val = obj.Source.Outputs.(obj.SourceProp);
            obj.Target.setInput(obj.TargetProp, val);
        end
    end
end
