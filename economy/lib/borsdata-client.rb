require 'borsdata-client/country'
require 'borsdata-client/instrument'
require 'borsdata-client/kpi'
require 'borsdata-client/market'
require 'borsdata-client/util'

module Borsdata
    class << self
        attr_accessor :offline
    end
end

Borsdata.offline = false
