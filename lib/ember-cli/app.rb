require "timeout"

module EmberCLI
  class App
    ADDON_VERSION = "0.0.7"
    EMBER_CLI_VERSION = "~> 0.1.3"
    JQUERY_VERSIONS = ["~> 1.7", "~> 2.1"].freeze

    attr_reader :name, :options, :pid

    def initialize(name, options={})
      @name, @options = name.to_s, options
    end

    def compile
      prepare
      silence_stream(STDOUT){ exec command }
      copy_ember_assets_to_rails
      add_fingerprinted_ember_assets_to_manifest unless Helpers.non_production?
    end

    def run
      prepare
      # cmd = command(watch: true)
      # @pid = exec(cmd, method: :spawn)
      @pid = exec command
      copy_ember_assets_to_rails
      add_fingerprinted_ember_assets_to_manifest unless Helpers.non_production?
      at_exit{ stop }
    end

    def stop
      Process.kill "INT", pid if pid && pid.is_a?(Integer)
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
        sleep 0.1 while lockfile.exist?
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
    delegate :tee_path, to: :configuration
    delegate :configuration, to: :EmberCLI

    def build_timeout
      options.fetch(:build_timeout){ configuration.build_timeout }
    end

    def lockfile
      tmp_path.join("build.lock")
    end

    def prepare
      @prepared ||= begin
        check_addon!
        check_ember_cli_version!
        FileUtils.touch lockfile
        symlink_to_assets_root
        add_assets_to_precompile_list
        true
      end
    end

    def suppress_jquery?
      return false unless defined?(Jquery::Rails::JQUERY_VERSION)

      JQUERY_VERSIONS.any? do |requirement|
        match_version?(Jquery::Rails::JQUERY_VERSION, requirement)
      end
    end

    def check_ember_cli_version!
      version = dev_dependencies.fetch("ember-cli").split("-").first

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

    def copy_ember_assets_to_rails

      ember_assets_path = [EmberCLI.root, 'apps', name, 'assets', '.'].join('/')
      ember_fonts_path = [EmberCLI.root, 'apps', name, 'fonts'].join('/')
      rails_assets_path = [Rails.root, 'public', 'assets'].join('/')
      rails_fonts_path = [Rails.root, 'public'].join('/')

      puts "Copying Ember dist/assets into rails public/assets..."
      puts "#{ember_assets_path} \n--> #{rails_assets_path}"
      FileUtils.cp_r(ember_assets_path, rails_assets_path)

      if File.directory?(ember_fonts_path)
        puts "Copying Ember dist/fonts into rails public/fonts..."
        puts "#{ember_fonts_path} \n--> #{rails_fonts_path}"
        FileUtils.cp_r(ember_fonts_path, rails_fonts_path)
      end
    end

    def add_fingerprinted_ember_assets_to_manifest
      rails_assets_path = [Rails.root, 'public', 'assets'].join('/')

      fingerprints = {}
      Dir["#{rails_assets_path}/*"].map{|path| File.basename(path)}.each do |fn|
        fingerprints[:app_js] = fn if fn.index("#{ember_app_name}-") == 0 && File.extname(fn) == '.js'
        fingerprints[:app_css] = fn if fn.index("#{ember_app_name}-") == 0 && File.extname(fn) == '.css'
        fingerprints[:vendor_js] = fn if fn.index("vendor-") == 0 && File.extname(fn) == '.js'
        fingerprints[:vendor_css] = fn if fn.index("vendor-") == 0 && File.extname(fn) == '.css'
        fingerprints[:manifest_json] = fn if fn.index("manifest-") == 0 && File.extname(fn) == '.json'
      end
      fingerprints[:manifest_json_path] = [rails_assets_path, fingerprints[:manifest_json]].join('/')
      manifest = JSON.parse(File.open(fingerprints[:manifest_json_path]).read)

      manifest['assets']["#{name}/#{ember_app_name}.js"] = fingerprints[:app_js]
      manifest['assets']["#{name}/#{ember_app_name}.css"] = fingerprints[:app_css]
      manifest['assets']["#{name}/vendor.js"] = fingerprints[:vendor_js]
      manifest['assets']["#{name}/vendor.css"] = fingerprints[:vendor_css]

      puts "Updating manifest.json with fingerprints:"
      puts "#{fingerprints.to_json}"

      File.open(fingerprints[:manifest_json_path],"w") do |f|
        f.write(manifest.to_json)
      end
    end

    def log_pipe
      "| #{tee_path} -a #{log_path}" if tee_path
    end

    def ember_app_name
      @ember_app_name ||= options.fetch(:name){ package_json.fetch(:name) }
    end

    def app_path
      @app_path ||= begin
        path = options.fetch(:path){ Rails.root.join("app", name) }
        Pathname.new(path)
      end
    end

    def tmp_path
      @tmp_path ||= begin
        path = app_path.join("tmp")
        path.mkdir unless path.exist?
        path
      end
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

    def env_hash
      ENV.clone.tap do |vars|
        # vars.store "DISABLE_FINGERPRINTING", "true"
        # vars.store "SUPPRESS_JQUERY", "true" if suppress_jquery?
      end
    end

    def exec(cmd, options={})
      method_name = options.fetch(:method, :system)

      Dir.chdir app_path do
        Kernel.public_send(method_name, env_hash, cmd, err: :out)
      end
    end
  end
end
