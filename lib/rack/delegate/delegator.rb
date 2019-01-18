require 'timeout_errors'

module Rack
  module Delegate
    class Delegator
      def initialize(upstreams, uri_rewriters, net_http_request_rewriter, timeout_response)
        @upstreams = if upstreams.is_a? Array
                  upstreams.map { |u| map_to(u) }
                else
                  [URI(upstreams)]
                end
        # puts @upstreams.to_s
        # puts "--- #{@upstreams.length}"
        @uri_rewriters = uri_rewriters
        @net_http_request_rewriter = net_http_request_rewriter
        @timeout_response = timeout_response
      end

      def call(env)
        res = nil
        res = if @upstreams.length > 1
                call_multi(env)
              else
                call_single(env, @upstreams[0])[:response]
              end
        res
      end

      private

      def map_to(to)
        if to.is_a? Hash
          { uri: URI(to[:uri]), domain: to[:domain] }
        elsif to.is_a? String
          { uri: URI(to), domain: nil }
        end
      end

      def call_single(env, url)
        rack_request = Request.new(env)
        net_http_request = NetHttpRequestBuilder.new(rack_request,
                                                     @uri_rewriters,
                                                     @net_http_request_rewriter)
                                                .build

        http_response = Net::HTTP.start(*net_http_options(url[:uri])) do |http|
          http.request(net_http_request)
        end

        { response: convert_to_rack_response(http_response), url: url }
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

      def package_results(results)
        if results.length > 1
          response = {
            responses: results.map do |r|
              {
                status_code: status_of(r[:response]),
                headers: headers_of(r[:response]),
                domain: r[:url][:domain],
                body: body_of(r[:response])
              }
            end
          }
          return [safe_max_status(results.map { |r| r[:response] }),
                  headers_of(results[0][:response]),
                  [response.to_json]]
        end
        [status_of(results[0][:response]), headers_of(results[0][:response]), body_of(results[0][:response])]
      end

      def status_of(response)
        response[0]
      end

      def headers_of(response)
        response[1]
      end

      def body_of(response)
        safe_parse(response[2][0] || '') || ''
      end

      def safe_parse(str)
        return str if str.empty?

        res = JSON.parse(str)
        res
      rescue StandardError
        str
      end

      def safe_max_status(responses)
        res = responses.max_by { |a| a[0].to_i }[0]
        if res == 304
          res = responses.all? { |r| r[0].to_i == 304 } ? 304 : 200
        end
        res
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
