require "fileutils"
require "ember_cli/path_set"

describe EmberCli::PathSet do
  describe "#root" do
    it "depends on the app name" do
      app = build_app(name: "foo")

      path_set = build_path_set(app: app)

      expect(path_set.root).to eq rails_root.join("foo")
    end

    it "can be overridden" do
      app = build_app(name: "foo", options: { path: "not-foo" })

      path_set = build_path_set(app: app)

      expect(path_set.root).to eq rails_root.join("not-foo")
    end
  end

  describe "#tmp" do
    it "is a child of #root" do
      app = build_app

      path_set = build_path_set(app: app)

      expect(path_set.tmp).to exist
      expect(path_set.tmp).to eq rails_root.join(app.name, "tmp")
    end
  end

  describe "#log" do
    it "depends on the environment" do
      app = build_app(name: "foo")
      path_set = build_path_set(app: app, environment: "bar")

      expect(path_set.log).to eq rails_root.join("log", "ember-foo.bar.log")
      expect(rails_root.join("log")).to exist
    end
  end

  describe "#dist" do
    it "depends on the app name" do
      app = build_app(name: "foo")

      path_set = build_path_set(app: app)

      expect(path_set.dist).to exist
      expect(path_set.dist).to eq ember_cli_root.join("apps", "foo")
    end
  end

  describe "#asset_map" do
    it "globs the dist directory for a asset_map.json" do
      app = build_app(name: "foo")
      path_set = build_path_set(app: app)
      asset_map_file = path_set.dist.join("assets", "assetMap-abc123.json")

      create_file(asset_map_file)

      expect(path_set.asset_map).to exist
      expect(path_set.asset_map).to eq(asset_map_file)
    end
  end

  describe "#assets" do
    it "is a child of #dist" do
      app = build_app(name: "foo")
      path_set = build_path_set(app: app)

      expect(path_set.assets).to exist
      expect(path_set.assets).to eq ember_cli_root.join("apps", "foo", "assets")
    end
  end

  describe "#gemfile" do
    it "is a child of #root" do
      app = build_app(name: "foo")

      path_set = build_path_set(app: app)

      expect(path_set.gemfile).to eq rails_root.join("foo", "Gemfile")
    end
  end

  describe "#package_json_file" do
    it "is a child of #root" do
      path_set = build_path_set

      expect(path_set.package_json_file)
        .to eq path_set.root.join("package.json")
    end
  end

  describe "#lockfile" do
    it "is a child of #tmp" do
      path_set = build_path_set

      expect(path_set.lockfile).to eq path_set.tmp.join("build.lock")
    end
  end

  describe "#build_error_file" do
    it "is a child of #tmp" do
      path_set = build_path_set

      expect(path_set.build_error_file).to eq path_set.tmp.join("error.txt")
    end
  end

  describe "#ember" do
    it "is an executable child of #node_modules" do
      app = build_app
      ember_path = rails_root.join(app.name, "node_modules", ".bin", "ember")
      create_executable(ember_path)

      path_set = build_path_set(app: app)

      expect(path_set.ember).to eq ember_path
    end

    it "raises a DependencyError if the file isn't executable" do
      path_set = build_path_set

      expect { path_set.ember }.to raise_error(EmberCli::DependencyError)
    end
  end

  describe "#bower" do
    it "can be overridden" do
      fake_bower = create_executable(ember_cli_root.join("bower"))
      app = build_app(options: { bower_path: fake_bower })

      path_set = build_path_set(app: app)

      expect(path_set.bower).to eq fake_bower
    end

    it "can be configured" do
      fake_bower = create_executable(ember_cli_root.join("bower"))
      configuration = double(bower_path: fake_bower)

      path_set = build_path_set(configuration: configuration)

      expect(path_set.bower).to eq fake_bower
    end
  end

  describe "#npm" do
    it "can be overridden" do
      app = build_app(options: { npm_path: "npm-path" })

      path_set = build_path_set(app: app)

      expect(path_set.npm).to eq "npm-path"
    end

    it "can be configured" do
      configuration = double(npm_path: "npm-path")

      path_set = build_path_set(configuration: configuration)

      expect(path_set.npm).to eq "npm-path"
    end
  end

  describe "#bundler" do
    it "can be overridden" do
      app = build_app(options: { bundler_path: "bundler-path" })

      path_set = build_path_set(app: app)

      expect(path_set.bundler).to eq "bundler-path"
    end

    it "can be configured" do
      configuration = double(bundler_path: "bundler-path")

      path_set = build_path_set(configuration: configuration)

      expect(path_set.bundler).to eq "bundler-path"
    end
  end

  def create_file(path)
    path.parent.mkpath
    FileUtils.touch(path)
    path
  end

  def create_executable(path)
    file = File.new(create_file(path))
    file.chmod(0777)
    path
  end

  def build_app(**options)
    double(
      options.reverse_merge(
        name: "foo",
        options: {},
      ),
    )
  end

  def build_path_set(**options)
    EmberCli::PathSet.new(
      options.reverse_merge(
        app: build_app,
        configuration: nil,
        rails_root: rails_root,
        ember_cli_root: ember_cli_root,
        environment: "test",
      ),
    )
  end

  def ember_cli_root
    Rails.root.join("tmp", "ember_cli").tap(&:mkpath)
  end

  def rails_root
    Rails.root.join("tmp", "rails").tap(&:mkpath)
  end

  around do |example|
    [rails_root, ember_cli_root].each do |dir|
      if dir.exist?
        FileUtils.rm_rf(dir)
      end
    end

    example.run
  end
end
