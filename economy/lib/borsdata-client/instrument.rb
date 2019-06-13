require 'date'
require 'borsdata-client/util'

module Borsdata
    class Instrument
        attr_reader :id, :name, :isin, :ticker

        @@all = nil
        @@by_ticker = nil

        def self.by_ticker(ticker)
            init
            @@by_ticker[ticker]
        end

        def initialize(h)
            @id = h['insId']
            @name = h['name']
            @isin = h['isin']
            @ticker = h['ticker']
            @prices = nil
        end

        def f_score
            f = FScore.by_instrument_id(@id)
            f ? f.value : nil
        end

        def prices
            if ! @prices.nil?
                @prices
            elsif id >= 0
                # TODO: base the cache decision on the fact that new prices are published at 8PM
                data = Util.get_data("/v1/instruments/#{id}/stockprices", 3600)
                @prices = data['stockPricesList'].map do |item|
                    {
                        date: Date.parse(item['d']),
                        open: item['o'],
                        close: item['c'],
                        high: item['h'],
                        low: item['l'],
                        volume: item['v']
                    }
                end
            else
                raise "can't handle non-Börsdata instruments yet"
            end
        end

        class << self
            private

            def init
                return if @@all
                @@all = Array.new
                @@by_ticker = Hash.new
                data = Util.get_data("/v1/instruments", 86400)
                data['instruments'].each do |item|
                    instrument = Instrument.new(item)
                    @@all << instrument
                    @@by_ticker[item['ticker']] = instrument
                end
            end
        end
    end
end
