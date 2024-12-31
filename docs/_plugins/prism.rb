require 'cgi'

module Jekyll
  module Tags
    class Prism < Liquid::Block
      def initialize(tag_name, text, tokens)
        @arg = text.strip
        super
      end

      def render(context)
        output = super(context)
        output = CGI.escapeHTML(output).strip
        "<pre class=\"language-#{@arg} line-numbers card-panel z-depth-3 \"><code>#{output}</code></pre>"
      end
    end
  end
end

Liquid::Template.register_tag('prism', Jekyll::Tags::Prism)