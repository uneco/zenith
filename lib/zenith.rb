require 'yaml'
require 'erb'
require 'active_support/all'
require 'pathname'

module Zenith
  class TemplateBuilder
    TEMPLATE_EXT = '.yml.erb'.freeze

    def initialize(base_dir: '.', main_file_name: 'main', erb: true)
      @base_dir = Pathname.new(base_dir)
      @main_file_name = main_file_name
      @erb = erb
    end

    def build
      YAML.load(full_template)['template'].to_yaml
    end

    private
    def partials
      Pathname.glob(@base_dir.join("_*#{TEMPLATE_EXT}"))
    end

    def load_template(path)
      data = IO.read(path)
      @erb ? eval_erb(data) : data
    end

    def eval_erb(data)
      ERB.new(data).result
    end

    def partial_contents
      partials.map do |template|
        data = load_template(template)
        name = File.basename(template).scan(/^_([^.]+)\./).flatten.first
        [%[#{name}: &#{name}], data.indent(2)].join("\n")
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

    def self.install!
      return if @installed
      @installed = true
      FUNCTION_NAMES.each do |name|
        Function.register! name
      end
    end
  end
end
