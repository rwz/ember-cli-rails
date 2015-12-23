require "html_page/renderer"
require "ember_cli/path_set"
require "ember_cli/shell"
require "ember_cli/build_monitor"
require "ember_cli/deploy/file"

module EmberCli
  class App
    attr_reader :name, :options, :paths

    def initialize(name, **options)
      @name = name.to_s
      @options = options
      @paths = PathSet.new(
        app: self,
        environment: Rails.env,
        rails_root: Rails.root,
        ember_cli_root: EmberCli.root,
      )
      @shell = Shell.new(
        paths: @paths,
        env: env_hash,
        options: options,
      )
      @build = BuildMonitor.new(name, @paths)
    end

    def root_path
      paths.root
    end

    def dist_path
      paths.dist
    end

    def compile
      @compiled ||= begin
        prepare
        @shell.compile
        @build.check!
        true
      end
    end

    def build
      if development?
        build_and_watch
      elsif test?
        compile
      end

      @build.wait!
    end

    def index_html(head:, body:)
      html = HtmlPage::Renderer.new(
        head: head,
        body: body,
        content: deploy.index_html,
      )

      html.render
    end

    def install_dependencies
      @shell.install
    end

    def test
      prepare

      @shell.test
    end

    def check_for_errors!
      @build.check!
    end

    private

    def development?
      env.to_s == "development"
    end

    def test?
      env.to_s == "test"
    end

    def deploy
      deploy_strategy.new(self)
    end

    def deploy_strategy
      strategy = options.fetch(:deploy, {})

      if strategy.respond_to?(:fetch)
        strategy.fetch(rails_env, EmberCli::Deploy::File)
      else
        strategy
      end
    end

    def rails_env
      Rails.env.to_s.to_sym
    end

    def env
      EmberCli.env
    end

    def build_and_watch
      prepare
      @shell.build_and_watch
    end

    def prepare
      @prepared ||= begin
        @build.reset
        true
      end
    end

    def excluded_ember_deps
      Array.wrap(options[:exclude_ember_deps]).join("?")
    end

    def env_hash
      ENV.to_h.tap do |vars|
        vars["RAILS_ENV"] = Rails.env
        vars["EXCLUDE_EMBER_ASSETS"] = excluded_ember_deps
        vars["BUNDLE_GEMFILE"] = paths.gemfile.to_s if paths.gemfile.exist?
      end
    end
  end
end
