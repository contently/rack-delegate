require 'timeout_errors'
require_relative './lib/upstream_mapper'
require_relative './lib/json_helper'
require_relative './lib/response_helpers'

module Rack
  module Delegate
    # The Delegator class acts as the Rack middleware coordinating
    # requests and responses
    class Delegator
      include Rack::Delegate::Mapping
      include Rack::Delegate::JsonHelper
      include Rack::Delegate::ResponseHelpers

      def initialize(upstreams, uri_rewriters, net_http_request_rewriter,
                     timeout_response)

        @upstreams = make_upstreams(upstreams)
        @uri_rewriters = uri_rewriters
        @net_http_request_rewriter = net_http_request_rewriter
        @timeout_response = timeout_response
      end

      def call(env)
        res = if @upstreams.length > 1
                call_multi(env)
              else
                call_single(env, @upstreams[0])
              end
        translate_response(res)
      end

      private

      def translate_response(res)
        (res.is_a? Hash) && res.key?(:response) ? res[:response] : res
      end

      def call_single(env, url)
        rack_request = Request.new(env)
        net_http_request = NetHttpRequestBuilder.new(rack_request,
                                                     @uri_rewriters,
                                                     @net_http_request_rewriter)
                                                .build
        perform_call(net_http_request, url)
      rescue TimeoutErrors
        @timeout_response.call(env)
      end

      def call_multi(env)
        results = @upstreams.map do |url|
          Thread.new do
            call_single(env, url)
          end
        end.map(&:value)
        package_results(results)
      end

      def perform_call(net_http_request, url)
        {
          response: convert_to_rack_response(
            perform_request(net_http_request, url)
          ),
          url: url
        }
      end

      def perform_request(net_http_request, url)
        Net::HTTP.start(*net_http_options(url[:uri])) do |http|
          http.request(net_http_request)
        end
      end

      def package_results(results)
        response = {
          responses: results.map do |r|
            make_result(r)
          end
        }
        [safe_max_status(results.map { |r| r[:response] }),
         headers_of(results[0][:response]),
         [response.to_json]]
      end

      def make_result(result)
        {
          status_code: status_of(result[:response]),
          headers: headers_of(result[:response]),
          domain: result[:url][:domain],
          body: body_of(result[:response])
        }
      end

      def safe_max_status(responses)
        res = responses.max_by { |a| a[0].to_i }[0]
        if res == 304
          res = responses.all? { |r| r[0].to_i == 304 } ? 304 : 200
        end
        res
      end

      def net_http_options(url)
        [url.host, url.port, use_ssl: url.scheme == 'https']
      end

      def convert_to_rack_response(http_response)
        status = http_response.code
        headers = normalize_headers_for(http_response)
        body = Array(http_response.body)

        [status, headers, body]
      end

      def normalize_headers_for(http_response)
        http_response.to_hash.tap do |headers|
          headers.delete('status')

          # Since Ruby 2.1 Net::HTTPHeader#to_hash returns the value as an
          # array of values and not a string. Try to coerce it for 2.0 support.
          headers.each do |header, value|
            headers[header] = Array(value).join('; ')
          end
        end
      end
    end
  end
end
