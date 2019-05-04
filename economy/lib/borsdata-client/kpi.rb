require 'borsdata-client/util'

module Borsdata
    class KPI
        attr_reader :number, :string

        def self.raw_by_instrument_id_and_kpi_id(instrument_id, kpi_id)
            response = Util.get_data("/v1/instruments/#{instrument_id}/kpis/#{kpi_id}/last/point", 86400)
            [
                response['value']['n'],
                response['value']['s']
            ]
        end
    end

    class FScore < KPI
        attr_reader :value

        def self.by_instrument_id(instrument_id)
            raw = raw_by_instrument_id_and_kpi_id(instrument_id, 167)
            FScore.new(raw.first.to_i)
        end

        def initialize(value)
            @value = value
        end
    end
end
