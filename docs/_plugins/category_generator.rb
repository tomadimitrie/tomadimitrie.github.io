module Jekyll
  module CategoryGenerator
    class Reader < Jekyll::Reader
      def read
        super
        config = @site.config["category-generator"]
        allowed_collections = config["collections"]
        collections = @site.collections.select { |key| allowed_collections.include?(key) }.values
        for collection in collections
          for doc in collection.docs
            new_categories = doc.url.split("/")[1..-2]
            doc.data["categories"] ||= []
            doc.data["categories"] += new_categories 
          end
        end
      end
    end
  end
end

Jekyll::Hooks.register :site, :after_init do |site|
  site.reader = Jekyll::CategoryGenerator::Reader.new(site)
end
