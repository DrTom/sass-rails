require 'sass'
require 'sprockets/sass_importer'
require 'tilt'

module Sass
  module Rails
    class SassImporter < Sass::Importers::Filesystem
      module Globbing
        GLOB = /(\A|\/)(\*|\*\*\/\*)\z/

        def find_relative(name, base, options)
          if m = name.match(GLOB)
            path = name.sub(m[0], "")
            base = File.expand_path(path, File.dirname(base))
            glob_imports(base, m[2], options)
          else
            super
          end
        end

        def find(name, options)
          # globs must be relative
          return if name =~ GLOB
          super
        end

        private
          def glob_imports(base, glob, options)
            contents = ""
            each_globbed_file(base, glob) do |filename|
              next if filename == options[:filename]
              contents << "@import #{filename.inspect};\n"
            end
            return nil if contents == ""
            Sass::Engine.new(contents, options.merge(
              :importer => self,
              :syntax => :scss
            ))
          end

          def each_globbed_file(base, glob)
            raise ArgumentError unless glob == "*" || glob == "**/*"

            exts = extensions.keys.map { |ext| Regexp.escape(".#{ext}") }.join("|")
            sass_re = Regexp.compile("(#{exts})$")

            context.depend_on(base)

            Dir["#{base}/#{glob}"].sort.each do |path|
              if File.directory?(path)
                context.depend_on(path)
              elsif sass_re =~ path
                yield path
              end
            end
          end
      end

      module ERB
        def extensions
          {
            'css.erb'  => :scss_erb,
            'scss.erb' => :scss_erb,
            'sass.erb' => :sass_erb
          }.merge(super)
        end

        def erb_extensions
          {
            :scss_erb => :scss,
            :sass_erb => :sass
          }
        end

        def find_relative(*args)
          process_erb_engine(super)
        end

        def find(*args)
          process_erb_engine(super)
        end

        private
          def process_erb_engine(engine)
            if engine && syntax = erb_extensions[engine.options[:syntax]]
              template = Tilt::ERBTemplate.new(engine.options[:filename])
              contents = template.render(context, {})

              Sass::Engine.new(contents, engine.options.merge(:syntax => syntax))
            else
              engine
            end
          end
      end

      include ERB
      include Globbing

      attr_reader :context

      def initialize(context, *args)
        @context = context
        super(*args)
      end

      # Allow .css files to be @import'd
      def extensions
        { 'css' => :scss }.merge(super)
      end
    end
  end
end
