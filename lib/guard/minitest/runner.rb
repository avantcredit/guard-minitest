require 'guard/minitest/inspector'

module Guard
  class Minitest
    class Runner
      attr_accessor :inspector

      def initialize(options = {})
        @options = {
          all_after_pass:     false,
          bundler:            File.exist?("#{Dir.pwd}/Gemfile"),
          rubygems:           false,
          drb:                false,
          zeus:               false,
          spring:             false,
          include:            [],
          test_folders:       %w[test spec],
          test_file_patterns: %w[*_test.rb test_*.rb *_spec.rb],
          cli:                nil
        }.merge(options)

        parse_deprecated_options

        [:test_folders, :test_file_patterns].each do |k|
          @options[k] = Array(@options[k]).uniq.compact
        end

        @inspector = Inspector.new(test_folders, test_file_patterns)
      end

      def run(paths, options = {})
        message = "Running: #{options[:all] ? 'all tests' : paths.join(' ')}"
        UI.info message, reset: true

        status = if bundler?
          system(minitest_command(paths))
        else
          if defined?(::Bundler)
            ::Bundler.with_clean_env do
              system(minitest_command(paths))
            end
          else
            system(minitest_command(paths))
          end
        end

        # When using zeus or spring, the Guard::Minitest::Reporter can't be used because the minitests run in another
        # process, but we can use the exit status of the client process to distinguish between :success and :failed.
        if zeus? || spring?
          ::Guard::Notifier.notify(message, title: 'Minitest results', image: status ? :success : :failed)
        end

        if @options[:all_after_pass] && status && !options[:all]
           run_all
        else
          status
        end
      end

      def run_all
        paths = inspector.clean_all
        run(paths, all: true)
      end

      def run_on_modifications(paths = [])
        paths = inspector.clean(paths)
        run(paths, all: all_paths?(paths))
      end

      def run_on_additions(paths)
        inspector.clear_memoized_test_files
        true
      end

      def run_on_removals(paths)
        inspector.clear_memoized_test_files
      end

      def cli_options
        @cli_options ||= Array(@options[:cli])
      end

      def bundler?
        @options[:bundler] && !@options[:spring]
      end

      def rubygems?
        !bundler? && @options[:rubygems]
      end

      def drb?
        @options[:drb]
      end

      def zeus?
        @options[:zeus].is_a?(String) || @options[:zeus]
      end

      def spring?
        @options[:spring].is_a?(String) || @options[:spring]
      end

      def all_after_pass?
        @options[:all_after_pass]
      end

      def test_folders
        @options[:test_folders]
      end

      def include_folders
        @options[:include]
      end

      def test_file_patterns
        @options[:test_file_patterns]
      end

      private

      def minitest_command(paths)
        cmd_parts = []

        cmd_parts << 'bundle exec' if bundler?
        cmd_parts << if drb?
          drb_command(paths)
        elsif zeus?
          zeus_command(paths)
        elsif spring?
          spring_command(paths)
        else
          ruby_command(paths)
        end

        cmd_parts.compact.join(' ')
      end

      def drb_command(paths)
        %w[testdrb] + relative_paths(paths)
      end

      def zeus_command(paths)
        command = @options[:zeus].is_a?(String) ? @options[:zeus] : 'test'
        ['zeus', command] + relative_paths(paths)
      end

      def spring_command(paths)
        command = @options[:spring].is_a?(String) ? @options[:spring] : 'testunit'
        cmd_parts = ['spring', command]
        cmd_parts << File.expand_path('../runners/old_runner.rb', __FILE__) unless (Utils.minitest_version_gte_5? || command != 'testunit')
        if cli_options.length > 0
          cmd_parts + paths + ['--'] + cli_options
        else
          cmd_parts + paths.collect{|p| "TEST=#{p}"}
        end
      end

      def ruby_command(paths)
        cmd_parts  = ['ruby']
        cmd_parts.concat(generate_includes)
        cmd_parts << '-r rubygems' if rubygems?
        cmd_parts << '-r bundler/setup' if bundler?
        cmd_parts << '-r minitest/autorun'
        cmd_parts.concat(paths.map { |path| "-r ./#{path}" })

        unless Utils.minitest_version_gte_5?
          cmd_parts << "-r #{File.expand_path('../runners/old_runner.rb', __FILE__)}"
        end

        # All the work is done through minitest/autorun
        # and requiring the test files, so this is just
        # a placeholder so Ruby doesn't try to exceute
        # code from STDIN.
        cmd_parts << '-e ""'

        cmd_parts << '--'
        cmd_parts += cli_options
      end

      def generate_includes
        (test_folders + include_folders).map {|f| %[-I"#{f}"] }
      end

      def relative_paths(paths)
        paths.map { |p| "./#{p}" }
      end

      def all_paths?(paths)
        paths == inspector.all_test_files
      end

      def parse_deprecated_options
        if @options.key?(:notify)
          UI.info %{DEPRECATION WARNING: The :notify option is deprecated. Guard notification configuration is used.}
        end

        [:seed, :verbose].each do |key|
          if value = @options.delete(key)
            final_value = "--#{key}"
            final_value << " #{value}" unless [TrueClass, FalseClass].include?(value.class)
            cli_options << final_value

            UI.info %{DEPRECATION WARNING: The :#{key} option is deprecated. Pass standard command line argument "--#{key}" to Minitest with the :cli option.}
          end
        end
      end

    end
  end
end
