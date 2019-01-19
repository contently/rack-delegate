module Rack
  module Delegate
    # Provides ResponseHelpers for mapping multi-responses
    module ResponseHelpers
      def status_of(response)
        response.first
      end

      def headers_of(response)
        response[1]
      end

      def body_of(response)
        safe_parse(response[2][0] || '') || ''
      end
    end
  end
end
