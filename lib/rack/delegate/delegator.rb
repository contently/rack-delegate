require 'timeout_errors'

module Rack
  module Delegate
    class Delegator
      def initialize(urls, uri_rewriters, net_http_request_rewriter, timeout_response)
        @urls = if urls.is_a? Array
                  urls.map { |u| URI(u) }
                else
                  [URI(urls)]
                end
        puts @urls
        @uri_rewriters = uri_rewriters
        @net_http_request_rewriter = net_http_request_rewriter
        @timeout_response = timeout_response
      end

      def call(env)
        if @urls.length > 1
          call_multi(env)
        else
          call_single(env, @urls[0])
        end
      end

      private

      def call_single(env, url)
        rack_request = Request.new(env)
        net_http_request = NetHttpRequestBuilder.new(rack_request,
                                                     @uri_rewriters,
                                                     @net_http_request_rewriter)
                                                .build

        http_response = Net::HTTP.start(*net_http_options(url)) do |http|
          http.request(net_http_request)
        end

        convert_to_rack_response(http_response)
      rescue TimeoutErrors
        @timeout_response.call(env)
      end

      def call_multi(env)
        results = @urls.map do |url|
          Thread.new do
            call_single(env, url)
          end
        end.map(&:value)
        package_results(results)
      end

      def package_results(results)
        if results.length > 1
          response = {
            responses: results.map do |r|
              {
                status_code: status_of(r),
                body: body_of(r).force_encoding('ISO-8859-1').encode('UTF-8')
              }
            end
          }
          return [max_status(results),
                  headers_of(results[0]),
                  [response.to_json]]
        end
        [status_of(results[0]), headers_of(results[0]), body_of(results[0])]
      end

      def status_of(response)
        response[0]
      end

      def headers_of(response)
        response[1]
      end

      def body_of(response)
        response[2][0]
      end

      def max_status(responses)
        responses.max_by { |a| a[0].to_i }[0]
      end

      def net_http_options(url)
        [url.host, url.port, https: url.scheme == 'https']
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
          headers.each { |header, value| headers[header] = Array(value).join('; ') }
        end
      end
    end
  end
end
