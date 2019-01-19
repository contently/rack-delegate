require 'pry'
module Rack
  module Delegate
    # The configurator/DSL provider for the configuration
    class Configuration
      def self.from_block(&block)
        config = new
        config.instance_eval(&block)
        config.actions
      end

      attr_reader :actions

      def initialize
        @actions = []
        @constraints = []
        @rewriter = Rewriter.new
        @changer = Rewriter.new
        @timeout = NetworkErrorResponse
      end

      def from(pattern, to:, constraints: nil, rewrite: nil)
        rewriters = [@rewriter]

        rewriters << make_rewriter(&rewrite) unless rewrite.nil?
        action = Action.new(pattern,
                            Delegator.new(to, rewriters, @changer, @timeout))

        action = Rack::Timeout.new(action) if timeout?

        constraints = Array(constraints).concat(@constraints)

        unless constraints.empty?
          action = ConstrainedAction.new(action, constraints)
        end

        @actions << action
      end

      def rewrite(&block)
        @rewriter = make_rewriter(&block)
        @rewriter
      end

      def change
        @changer = Rewriter.new do |request|
          yield request
          request
        end
      end

      def timeout(response_object = nil, &block)
        @timeout = response_object if response_object
        @timeout = block if block
      end

      private

      def constraints(*args, &block)
        @constraints << args.flatten << block
      end

      def timeout?
        require 'rack/timeout'
        true
      rescue LoadError
        false
      end

      def make_rewriter(&block)
        Rewriter.new do |uri|
          uri.instance_eval(&block)
          uri
        end
      end
    end
  end
end
