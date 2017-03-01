require 'yaml'
require 'erb'
require 'active_support/all'
require 'pathname'
require 'tsort'

module Zenith
  class TemplateBuilder
    TEMPLATE_EXT = '.yml.erb'.freeze

    def initialize(base_dir: '.', main_file_name: 'main', erb: true)
      @base_dir = Pathname.new(base_dir)
      @main_file_name = main_file_name
      @erb = erb
      @partial_cache = {}
    end

    def build
      YAML.load(full_template)['template'].deep_dup.to_yaml
    end

    def load_template(path)
      data = IO.read(path)
      @erb ? eval_erb(data) : data
    end

    private
    def unordered_partials
      builder = self

      resolver = PartialResolver.new(@partial_cache) do |name|
        path = @base_dir.join("_#{name}#{TEMPLATE_EXT}").to_s
        builder.load_template(path)
      end

      Pathname.glob(@base_dir.join("_*#{TEMPLATE_EXT}")).map do |path|
        name = File.basename(path).scan(/^_([^.]+)\./).flatten.first
        resolver.resolve(name)
      end
    end

    def partials
      PartialGraph.new(unordered_partials).tsort
    end

    def eval_erb(data)
      ERB.new(data).result
    end

    def partial_contents
      partials.map do |partial|
        [%[#{partial.name}: &#{partial.name}], partial.content.indent(2)].join("\n")
      end
    end

    def main_file_path
      @base_dir.join("#{@main_file_name}#{TEMPLATE_EXT}")
    end

    def full_template
      main = load_template(main_file_path)
      yaml_content = [
        'partials:',
        partial_contents.join("\n").indent(2),
        'template:',
        main.indent(2),
      ].join("\n")
    end
  end

  class PartialGraph
    include TSort

    def initialize(partials)
      @partials = partials
    end

    def tsort_each_node(&block)
      @partials.each(&block)
    end

    def tsort_each_child(node, &block)
      node.dependencies.each(&block)
    end
  end

  class PartialResolver
    def initialize(cache, &block)
      @cache = cache
      @block = block
    end

    def resolve(name)
      if @cache[name]
        return @cache[name]
      end
      @cache[name] = Partial.new(name, @block.call(name), self)
    end
  end

  class Partial
    attr_reader :name, :content, :resolver

    def initialize(name, content, resolver)
      @name = name
      @content = content
      @parsed = YAML.parse(content)
      @resolver = resolver
    end

    def dependencies
      dependency_names.map do |name|
        @resolver.resolve(name)
      end
    end

    def dependency_names(node = nil)
      node ||= @parsed
      deps = []

      if node.is_a?(Psych::Nodes::Alias)
        deps << node.anchor
      end

      [*deps, *(node.children || []).map {|node|
        dependency_names(node)
      }].flatten.uniq
    end
  end

  module YamlExtension
    FUNCTION_NAMES = %i(
      Sub Join GetAtt Base64 GetAZs
      ImportValue Select Split Ref
      And Equals If Not Or
    ).freeze

    class Function
      attr_accessor :args

      class << self
        attr_accessor :tag
        def register!(name)
          klass = Class.new(self) do
            self.tag = name
          end
          const_set name.to_sym, klass
          klass.yaml_tag "!#{name}"
          klass
        end
      end

      def init_with(coder)
        self.args = coder.scalar || coder.seq
      end

      def encode_with(coder)
        if self.args.is_a? Array
          coder.seq = self.args
        else
          coder.scalar = self.args
        end
      end
    end

    def installed?
      !!@installed
    end

    def self.registered_functions
      @registered_functions
    end

    def self.install!
      return if @installed
      @installed = true
      @registered_functions = FUNCTION_NAMES.map do |name|
        Function.register! name
      end
    end
  end
end
