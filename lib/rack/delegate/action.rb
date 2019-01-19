module Rack
  module Delegate
    # Represents an Action
    #
    # A regex pattern and a delegator are supplied to this Struct
    # During an inbound request, the request is mapped across the
    # known actions, and if a matching url is found, the supplied
    # Delegator is called.
    class Action < Struct.new(:pattern, :delegator)
      def dispatch(request)
        pattern.match(request.fullpath) do
          throw :dispatched, self
        end
      end
    end
  end
end
