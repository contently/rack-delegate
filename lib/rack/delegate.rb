require 'rack'

module Rack
  module Delegate
    autoload :Rewriter, 'rack/delegate/rewriter'
    autoload :NetHttpRequestBuilder, 'rack/delegate/net_http_request_builder'
    autoload :Delegator, 'rack/delegate/delegator'
    autoload :NetworkErrorResponse, 'rack/delegate/network_error_response'
    autoload :Constraint, 'rack/delegate/constraint'
    autoload :Action, 'rack/delegate/action'
    autoload :ConstrainedAction, 'rack/delegate/constrained_action'
    autoload :Configuration, 'rack/delegate/configuration'
    autoload :Dispatcher, 'rack/delegate/dispatcher'

    class << self
      attr_accessor :network_error_response
    end
    self.network_error_response = NetworkErrorResponse

    def self.gateway(request, action)
      request_path = request.env['REQUEST_PATH']
      uri = URI(request.env['REQUEST_URI'])
      match = action.pattern.match(request_path).to_s
      res = URI("#{uri.scheme}://#{uri.host}#{uri.port != 80 && uri.port != 443 ? ":#{uri.port}" : ''}")
      res.path = match
      res.to_s
    end

    def self.inject_gateway(request, action)
      request.env['HTTP_X_GATEWAY'] = Delegate.gateway(request, action)
    end

    def self.configure(&block)
      dispatcher = Dispatcher.configure(&block)

      Struct.new(:app) do
        define_method :call do |env|
          request = Request.new(env)
          if (action = dispatcher.dispatch(request))
            Delegate.inject_gateway(request, action)
            action.delegator.call(env)
          else
            app.call(env)
          end
        end
      end
    end
  end
end
