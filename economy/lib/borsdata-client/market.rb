require 'borsdata-client/util'

module Borsdata
    class Market
        attr_reader :id, :name, :country, :exchangeName

        @@by_id = nil

        def self.by_id(id)
            init
            @@by_id[id]
        end

        def initialize(h)
            @id = h['id']
            @name = h['name']
            @country = Borsdata::Country.by_id(h['countryId'])
            @isIndex = h['isIndex']
            @exchangeName = h['exchangeName']
        end

        def to_s
            "#{exchangeName}/#{name} (#{country})"
        end
        
        class << self
            private 

            def init
                return if @@by_id
                @@by_id = Hash.new
                data = Util.get_data("/v1/markets", 86400)
                data['markets'].each do |item|
                    @@by_id[item['id']] = Market.new(item)
                end
            end
        end
    end
end
