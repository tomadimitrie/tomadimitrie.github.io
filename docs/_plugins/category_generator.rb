module Jekyll
  module CategoryGenerator
    class Reader < Jekyll::Reader
      def read
        super
        config = @site.config["category-generator"]
        allowed_collections = config["collections"]
        collections = @site.collections.select { |key| allowed_collections.include?(key) }.values
        collections.each { |collection|
          collection.docs.each { |doc|
            tokens = doc.url.split("/")
            new_categories = tokens[1..-3]
            doc.data["categories"] ||= []
            doc.data["categories"] += new_categories
            doc.data["challenge"] = tokens[-2]
          }
        }
      end
    end
  end
end

Jekyll::Hooks.register :site, :after_init do |site|
  site.reader = Jekyll::CategoryGenerator::Reader.new(site)
end
