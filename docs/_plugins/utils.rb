require "cgi"

module Jekyll
  module Unescape
    def unescape(input)
      CGI.unescape(input)
    end
  end
end

Liquid::Template.register_filter(Jekyll::Unescape)
