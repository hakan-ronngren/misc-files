require 'borsdata-client/util'

module Borsdata
    class Country
        attr_reader :id, :name

        @@all = nil
        @@by_id = nil

        def self.by_id(id)
            init
            # The API returns country ids that are not listed in the country json.
            # We therefore have to be able to invent countries on the fly.
            country = @@by_id[id]
            unless country
                country = Country.new({'id' => id, 'name' => "Country #{id}"})
                @@all << country
                @@by_id[id] = country
            end
            country
        end

        def initialize(h)
            @id = h['id']
            @name = h['name']
        end

        class << self
            private

            def init
                return if @@all
                @@all = Array.new
                @@by_id = Hash.new
                data = Util.get_data("/v1/countries", 86400)
                data['countries'].each do |item|
                    country = Country.new(item)
                    @@all << country
                    @@by_id[item['id']] = country
                end
            end
        end
    end
end
