# frozen_string_literal: true
require 'singleton'
require_relative 'delta'

module Coverband
  module Collectors
    ###
    # TODO: look at alternatives to semaphore
    # StandardError seems like be better option
    # coverband previously had RuntimeError here
    # but runtime error can let a large number of error crash this method
    # and this method is currently in a ensure block in middleware and threads
    ###
    class Coverage
      include Singleton
      extend Forwardable

      def reset_instance
        @project_directory = File.expand_path(Coverband.configuration.root)
        @ignore_patterns = Coverband.configuration.ignore + ['internal:prelude', 'schema.rb']
        @reporting_frequency = Coverband.configuration.reporting_frequency
        @store = Coverband.configuration.store
        @verbose  = Coverband.configuration.verbose
        @logger   = Coverband.configuration.logger
        @test_env = Coverband.configuration.test_env
        @track_gems = Coverband.configuration.track_gems
        Delta.reset
        self
      end

      def runtime!
        @store.type = nil
      end

      def eager_loading!
        @store.type = Coverband::EAGER_TYPE
      end

      def report_coverage(force_report = false)
        return if !ready_to_report? && !force_report
        raise 'no Coverband store set' unless @store

        original_previous_set = Delta.previous_results
        files_with_line_usage = filtered_files(Delta.results)

        ###
        # Hack to prevent processes and threads from reporting first Coverage hit
        # when we are in runtime collection mode, which do not have a cache of previous
        # coverage to remove the initial stdlib Coverage loading data
        ###
        if ((original_previous_set.nil? && @store.type == Coverband::EAGER_TYPE) ||
           (original_previous_set && @store.type != Coverband::EAGER_TYPE))
          @store.save_report(files_with_line_usage)
        end
      rescue StandardError => err
        if @verbose
          @logger&.error 'coverage failed to store'
          @logger&.error "error: #{err.inspect} #{err.message}"
          @logger&.error err.backtrace
        end
        raise err if @test_env
      end

      protected

      ###
      # Normally I would break this out into additional methods
      # and improve the readability but this is in a tight loop
      # on the critical performance path, and any refactoring I come up with
      # would slow down the performance.
      ###
      def track_file?(file)
        @ignore_patterns.none? do |pattern|
          file.include?(pattern)
        end && (file.start_with?(@project_directory) ||
                (@track_gems &&
                 Coverband.configuration.gem_paths.any? { |path| file.start_with?(path) }))
      end

      private

      def filtered_files(new_results)
        new_results.each_with_object({}) do |(file, line_counts), file_line_usage|
          file_line_usage[file] = line_counts if track_file?(file)
        end.select { |_file_name, coverage| coverage.any? { |value| value&.nonzero? } }
      end

      def ready_to_report?
        (rand * 100.0) >= (100.0 - @reporting_frequency)
      end

      def initialize
        if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
          raise NotImplementedError, 'not supported until Ruby 2.3.0 and later'
        end
        require 'coverage'
        if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.5.0')
          ::Coverage.start unless ::Coverage.running?
        else
          ::Coverage.start
        end
        if Coverband.configuration.safe_reload_files
          Coverband.configuration.safe_reload_files.each do |safe_file|
            load safe_file
          end
        end
        reset_instance
      end
    end
  end
end
