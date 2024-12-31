require "cgi"

module Jekyll
  module CategoryTree
    def category_tree(input)
      create_list = ->(items) {
        format_text = ->(key) {
          if key.is_a?(Array)
            "<a href=\"#{key[1]}\">#{CGI.unescape(key[0])}</a>"
          else
            "<a href=\"/category/#{key}\" style=\"color: white;\">#{CGI.unescape(key)}</a>"
          end
        }

        if items.empty?
          return ""
        end

        <<-EOF
          <ul>#{items.map { |key, value| "<li>#{format_text.call(key)} #{create_list.call(value)}</li>" }.join "" }</ul>
        EOF
      }

      tokens = input.map { |item| item.url.split("/")[2..-3] + [[item.data["challenge"], item.url]] }
      categories = tokens.each_with_object({}) do |current, accumulator|
        previous_accumulator = accumulator
        previous_token = current[0]
        previous_accumulator[previous_token] ||= {}
        current[1..].each { |token|
          previous_accumulator[previous_token][token] ||= {}
          previous_accumulator = previous_accumulator[previous_token]
          previous_token = token
        }
      end
      create_list.call(categories)
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryTree)
