require "timeout"

module EmberCLI
  class App
    ADDON_VERSION = "0.0.11"
    EMBER_CLI_VERSION = "~> 0.1.5"

    class BuildError < StandardError; end

    attr_reader :name, :options, :pid

    def initialize(name, options={})
      @name, @options = name.to_s, options
    end

    def tests_path
      dist_path.join("tests")
    end

    def compile
      prepare
      silence_build { exec command }
      check_for_build_error!
    end

    def install_dependencies
      exec "#{bundler_path} install" if gemfile_path.exist?
      exec "#{npm_path} install"
    end

    def run
      prepare
      cmd = command(watch: true)
      @pid = exec(cmd, method: :spawn)
      at_exit{ stop }
    end

    def run_tests
      prepare
      tests_pass = exec("#{ember_path} test")
      exit 1 unless tests_pass
    end

    def stop
      Process.kill "INT", pid if pid
      @pid = nil
    end

    def exposed_js_assets
      %W[#{name}/vendor #{name}/#{ember_app_name}]
    end

    def exposed_css_assets
      %W[#{name}/vendor #{name}/#{ember_app_name}]
    end

    def wait
      Timeout.timeout(build_timeout) do
        wait_for_build_complete_or_error
      end
    rescue Timeout::Error
      suggested_timeout = build_timeout + 5

      warn <<-MSG.strip_heredoc
        ============================= WARNING! =============================

          Seems like Ember #{name} application takes more than #{build_timeout}
          seconds to compile.

          To prevent race conditions consider adjusting build timeout
          configuration in your ember initializer:

            EmberCLI.configure do |config|
              config.build_timeout = #{suggested_timeout} # in seconds
            end

          Alternatively, you can set build timeout per application like this:

            EmberCLI.configure do |config|
              config.app :#{name}, build_timeout: #{suggested_timeout}
            end

        ============================= WARNING! =============================
      MSG
    end

    def ember_path
      @ember_path ||= app_path.join("node_modules", ".bin", "ember").tap do |path|
        fail <<-MSG.strip_heredoc unless path.executable?
          No local ember executable found. You should run `npm install`
          inside the #{name} app located at #{app_path}
        MSG
      end
    end

    private

    delegate :match_version?, :non_production?, to: Helpers
    delegate :configuration, to: EmberCLI
    delegate :tee_path, :npm_path, :bundler_path, to: :configuration

    def default_app_path
      path = Rails.root.join("app", name)

      return name unless path.directory?

      ActiveSupport::Deprecation.warn <<-MSG.strip_heredoc
        We have found that placing your EmberCLI
        application inside Rails' app has negative performance implications.

        Please see, https://github.com/rwz/ember-cli-rails/issues/66 for more
        detailed information.

        It is now recommended to place your EmberCLI application into the Rails
        root path.
      MSG

      path
    end

    def silence_build(&block)
      if ENV.fetch("EMBER_CLI_RAILS_VERBOSE"){ !Helpers.non_production? }
        yield
      else
        silence_stream(STDOUT, &block)
      end
    end

    def build_timeout
      options.fetch(:build_timeout){ configuration.build_timeout }
    end

    def lockfile
      @lockfile ||= tmp_path.join("build.lock")
    end

    def check_for_build_error!
      raise_build_error! if build_error?
    end

    def build_error_file
      @build_error_file ||= tmp_path.join("error.txt")
    end

    def reset_build_error!
      build_error_file.delete if build_error?
    end

    def build_error?
      build_error_file.exist?
    end

    def raise_build_error!
      error = BuildError.new("EmberCLI app #{name.inspect} has failed to build")
      error.set_backtrace build_error_file.read.split(?\n)
      fail error
    end

    def prepare
      @prepared ||= begin
        check_addon!
        check_ember_cli_version!
        reset_build_error!
        FileUtils.touch lockfile
        symlink_to_assets_root
        add_assets_to_precompile_list
        true
      end
    end

    def check_ember_cli_version!
      version = dev_dependencies.fetch("ember-cli").split(?-).first

      unless match_version?(version, EMBER_CLI_VERSION)
        fail <<-MSG.strip_heredoc
          EmberCLI Rails require ember-cli NPM package version to be
          #{EMBER_CLI_VERSION} to work properly. From within your EmberCLI directory
          please update your package.json accordingly and run:

            $ npm install

        MSG
      end
    end

    def check_addon!
      unless addon_present?
        fail <<-MSG.strip_heredoc
          EmberCLI Rails requires your Ember app to have an addon.

          From within your EmberCLI directory please run:

            $ npm install --save-dev ember-cli-rails-addon@#{ADDON_VERSION}

          in you Ember application root: #{app_path}
        MSG
      end
    end

    def symlink_to_assets_root
      assets_path.join(name).make_symlink dist_path.join("assets")
    rescue Errno::EEXIST
      # Sometimes happens when starting multiple Unicorn workers.
      # Ignoring...
    end

    def add_assets_to_precompile_list
      Rails.configuration.assets.precompile << /\A#{name}\//
    end

    def command(options={})
      watch = options[:watch] ? "--watch" : ""
      "#{ember_path} build #{watch} --environment #{environment} --output-path #{dist_path} #{log_pipe}"
    end

    def log_pipe
      "| #{tee_path} -a #{log_path}" if tee_path
    end

    def ember_app_name
      @ember_app_name ||= options.fetch(:name){ package_json.fetch(:name) }
    end

    def app_path
      @app_path ||= begin
        path = options.fetch(:path){ default_app_path }
        pathname = Pathname.new(path)
        pathname.absolute?? pathname : Rails.root.join(path)
      end
    end

    def tmp_path
      @tmp_path ||= app_path.join("tmp").tap(&:mkpath)
    end

    def log_path
      Rails.root.join("log", "ember-#{name}.#{Rails.env}.log")
    end

    def dist_path
      @dist_path ||= EmberCLI.root.join("apps", name).tap(&:mkpath)
    end

    def assets_path
      @assets_path ||= EmberCLI.root.join("assets").tap(&:mkpath)
    end

    def environment
      non_production?? "development" : "production"
    end

    def package_json
      @package_json ||= JSON.parse(app_path.join("package.json").read).with_indifferent_access
    end

    def dev_dependencies
      package_json.fetch("devDependencies", {})
    end

    def addon_present?
      dev_dependencies["ember-cli-rails-addon"] == ADDON_VERSION &&
        app_path.join("node_modules", "ember-cli-rails-addon", "package.json").exist?
    end

    def excluded_ember_deps
      Array.wrap(options[:exclude_ember_deps]).join(?,)
    end

    def env_hash
      ENV.clone.tap do |vars|
        vars.store "DISABLE_FINGERPRINTING", "true"
        vars.store "EXCLUDE_EMBER_ASSETS", excluded_ember_deps
        vars.store "BUNDLE_GEMFILE", gemfile_path.to_s if gemfile_path.exist?
      end
    end

    def gemfile_path
      app_path.join("Gemfile")
    end

    def exec(cmd, options={})
      method_name = options.fetch(:method, :system)

      Dir.chdir app_path do
        Kernel.public_send(method_name, env_hash, cmd, err: :out)
      end
    end

    def wait_for_build_complete_or_error
      loop do
        check_for_build_error!
        break unless lockfile.exist?
        sleep 0.1
      end
    end
  end
end
