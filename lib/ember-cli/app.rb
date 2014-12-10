module EmberCLI
  class App
    attr_reader :name, :options, :pid

    def initialize(name, options={})
      @name, @options = name.to_s, options
    end

    def compile
      prepare
      silence_stream STDOUT do
        system command, chdir: app_path, err: :out
      end
    end

    def run
      prepare
      @pid = spawn(command(watch: true), chdir: app_path, err: :out)
      at_exit{ stop }
    end

    def stop
      Process.kill "INT", pid if pid
      @pid = nil
    end

    def exposed_js_assets
      %W[#{name}/vendor #{name}/#{ember_app_name}]
    end

    private

    delegate :ember_path, to: :configuration
    delegate :tee_path, to: :configuration
    delegate :configuration, to: :EmberCLI

    def prepare
      @prepared ||= begin
        symlink_to_assets_root
        add_assets_to_precompile_list
        true
      end
    end

    def symlink_to_assets_root
      assets_path.join(name).make_symlink dist_path.join("assets")
    end

    def add_assets_to_precompile_list
      Rails.configuration.assets.precompile << /(?:\/|\A)#{name}\//
    end

    def command(options={})
      watch = options[:watch] ? "--watch" : ""
      "#{ember_path} build #{watch} --environment #{environment} --output-path #{dist_path} #{log_pipe}"
    end

    def log_pipe
      "| #{tee_path} -a #{log_path}" if tee_path
    end

    def ember_app_name
      @ember_app_name ||= options.fetch(:name) do
        JSON.parse(app_path.join("package.json").read).fetch("name")
      end
    end

    def app_path
      options.fetch(:path){ Rails.root.join("app", name) }
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
      Rails.env.production? ? "production" : "development"
    end
  end
end
