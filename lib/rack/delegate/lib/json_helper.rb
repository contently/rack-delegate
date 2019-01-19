module Rack
  module Delegate
    # Provides JSON helpers
    module JsonHelper
      def safe_parse(str)
        return str if str.empty?

        res = JSON.parse(str)
        res
      rescue StandardError
        str
      end
    end
  end
end
