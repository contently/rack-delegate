module Rack
  module Delegate
    # Provides mapping helpers
    module Mapping
      def map_to(to)
        if to.is_a? Hash
          { uri: URI(to[:uri]), domain: to[:domain] }
        elsif to.is_a? String
          { uri: URI(to), domain: nil }
        end
      end

      def make_upstreams(upstreams)
        if upstreams.is_a? Array
          upstreams.map { |u| map_to(u) }
        else
          [URI(upstreams)]
        end
      end
    end
  end
end
