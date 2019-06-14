#!/usr/bin/env bundle exec ruby

# Calculate the Signal (value growth) to Noise (variations) Ratio
# for one or several instruments.
#
# Pass a list of *-Price.xls files from Börsdata or similarly named
# *-Price.csv files from Yahoo as arguments
# Optionally use the --years option to choose where to cut the history

require 'date'
require 'eps'           # https://github.com/ankane/eps
require 'json'
require 'open-uri'
require 'time'
require 'spreadsheet'   # https://github.com/zdavatz/spreadsheet

$LOAD_PATH.push(File.expand_path('lib', Dir.pwd))
require 'borsdata-client'

DEFAULT_YEARS = 10

argv = ARGV

$years = DEFAULT_YEARS
$export = false

def fail_usage()
    puts "usage: #{__FILE__} [--years <integer>] <TICKER_OR_PRICE_FILE> [...]"
    puts "    --years <float>        history length (default #{DEFAULT_YEARS}"
    puts "    --export               export trend data as csv"
    exit 1
end

class Record
    attr_reader :name, :ticker, :updated, :f_score, :price_vs_trend, :yearly_growth, :rmsd

    def initialize(identifier)
        @identifier = identifier
        if cache_up_to_date?
            load_from_cache
        else
            calculate
        end
    end

    # Import prices from whatever data source we have and return them (no need
    # to keep all that temporary data in an attribute).
    def import
        raise "#{self.class.name}::#{__method__} must be overridden"
    end

    def cache_file
        "/tmp/#{File.basename @identifier}.years=#{$years}.cache"
    end

    def cache_up_to_date?
        false
    end

    def load_from_cache
        values = JSON.parse(File.read(cache_file))
        @ticker         = values['ticker']
        @name           = values['name']
        @updated        = values['updated']
        @f_score        = values['f_score']
        @yearly_growth  = values['yearly_growth']
        @rmsd           = values['rmsd']
        @price_vs_trend = values['price_vs_trend']
    end

    def write_to_cache
        h = {
            ticker:         @ticker,
            name:           @name,
            updated:        @updated,
            yearly_growth:  @yearly_growth,
            rmsd:           @rmsd,
            price_vs_trend: @price_vs_trend,
            f_score:        @f_score
        }
        File.write(cache_file, h.to_json + "\n")
    end

    private

    def calculate
        data = import

        # Adapt a line to the logarithmic data
        model = Eps::Regressor.new(data, target: :log_price)

        @yearly_growth = -1 +
            10 ** model.predict(date: 365) /
            10 ** model.predict(date: 0)

        @rmsd = -1 +
            10 ** Math.sqrt(
                data.inject(0) do |sum, item|
                    sum + (item[:log_price] - model.predict(date: item[:date])) ** 2
                end / data.length)

        # Current price vs. trend
        @price_vs_trend = -1 +
            10 ** data.first[:log_price] /
            10 ** model.predict(date: data.first[:date])

        write_to_cache

        if $export
            output_file = File.expand_path("#{@ticker}-#{@name}-Price-with_trend.csv", Dir.pwd)
            File.open(output_file, 'w') do |f|
                #f.puts("\"%s\"\t\"\"\t\"\"" % File.basename(output_file))
                f.puts("\"%s\"" % File.basename(output_file))
                f.puts "\"Date\"\t\"Close price\"\t\"Predicted price\""
                data.each do |item|
                    f.puts "\"%s\"\t%.2f\t%.2f" % [
                        Time.at(86400 * item[:date]).strftime('%Y-%m-%d'),
                        10 ** item[:log_price],
                        10 ** model.predict(date: item[:date])
                    ]
                end
            end
        end
    end
end

class FileBasedRecord < Record
    def cache_up_to_date?
        File.exists?(cache_file) &&
            File.new(cache_file).mtime > File.new(@identifier).mtime
    end
end

class BorsdataInstrumentRecord < Record
    def cache_up_to_date?
        File.exists?(cache_file) &&
            File.new(cache_file).mtime > Time.now - 3600
    end

    def import
        @ticker = @identifier.upcase
        puts "searching for #{@ticker}"
        instrument = Borsdata::Instrument.by_ticker(@ticker)
        raise "No Borsdata instrument with ticker #{@ticker}" unless instrument
        @name = instrument.name
        data = []
        @updated = '0'
        today = nil

        # TODO: use split info from the API instead of hardcoding split knowledge
        sagax_b_split_time_2019 = Time.parse('2019-05-30').to_i / 86400

        instrument.prices.reverse.each do |row|
            day = row[:date].to_time.to_i / 86400
            today ||= day
            break if day < today - 365.25 * $years
            # TODO: see the comment about splits above
            if @ticker == 'SAGA B' && day < sagax_b_split_time_2019
                row[:close] = row[:close] / 2.0
            end
            data.push({date: day, log_price: Math.log10(row[:close])})
            @updated = [@updated, row[:date].to_s].max
        end
        data.reverse! if data.first[:date] < data.last[:date]
        @f_score = instrument.f_score
        return data
    end
end

class BorsdataExcelRecord < FileBasedRecord
    def import
        @ticker, @name = File.basename(@identifier, '.xls').split('-')
        Spreadsheet.client_encoding = 'ISO-8859-1'
        book = Spreadsheet.open(@identifier)
        sheet = book.worksheet('PriceWeek')           # new books have multiple sheets
        sheet = book.worksheets.first if sheet.nil?   # old ones have only one
        @updated = sheet.rows[1][0].to_s

        # Prevent a race condition
        sheet.ensure_rows_read

        unless [sheet.rows.first[0], sheet.rows.first[4]] == %w(Date Closeprice)
            puts "#{@identifier}: not the expected Börsdata Excel format"
            exit 1
        end

        # Populate the data array with logarithmic data.
        # (Note: map, inject etc don't like break, they would return nil)
        data = []
        today = nil
        sheet.rows[1..-1].each do |row|
            day = if row[0].respond_to?(:to_time)
                      row[0].to_time      # old books have an Excel Date
                  else
                      Time.parse(row[0])  # new ones have a String
                  end.to_i / 86400
            today ||= day
            break if day < today - 365.25 * $years
            price = row[4].to_f
            # Disregard invalid points
            next unless day > 10000 &&
                day <= Time.now.to_i / 86400 &&
                price > 0.0
            data.push({date: day, log_price: Math.log10(price)})
        end

        return data
    end
end

class YahooCSVRecord < FileBasedRecord
    def import
        @ticker, @name = @identifier.split('-')
        lines = File.readlines(@identifier).map(&:strip)
        if lines.first != 'Date,Open,High,Low,Close,Adj Close,Volume'
            puts "#{@identifier}: not the expected Yahoo csv format"
            exit 1
        end
        lines.shift

        # Some yahoo csv files are in ascending date order, others in
        # descending. We expect descending.
        d0, d1 = [lines[0].split(',').first, lines[1].split(',').first]
        if d0 < d1
            lines.reverse!
        end
        @updated = lines.first.split(',')[0]

        data = []
        today = nil
        lines.each do |line|
            row = line.split(',')
            day = Date.parse(row[0]).to_time.to_i / 86400
            today ||= day
            break if day < today - 365.25 * $years
            price = row[4].to_f
            data.push({date: day, log_price: Math.log10(price)})
        end

        return data
    end
end

while argv[0].start_with?('-') do
    if argv[0] == '--years' && argv[1].to_f > 0
        argv.shift
        $years = argv[0].to_f
        fail_usage if $years <= 0.0  # nil or anything else than a positive float
    elsif argv[0] == '--export'
        $export = true
    else
        fail_usage
    end
    argv.shift
end

records = []
argv.each do |arg|
    if File.file?(arg)
        if arg.end_with?('.xls')
            records.push(BorsdataExcelRecord.new(arg))
        elsif arg.end_with?('.csv')
            records.push(YahooCSVRecord.new(arg))
        else
            fail_usage
        end
    elsif Borsdata::Instrument.by_ticker(arg.upcase)
        records.push(BorsdataInstrumentRecord.new(arg))
    else
        puts "#{arg}: not found, ignoring this instrument"
        next
    end
end

# Sort by descending SNR
records.sort_by! do |record|
    -record.yearly_growth / record.rmsd
end

puts "\e[1mTicker     Name               %3d yrs ø    RMSD    SNR     Now   FS     Updated\e[0m" % $years
yearly_growths = []
records.each do |record|
    # Unfortunately, Börsdata reports 0 both when it really is 0 and when it is not applicable,
    # e.g. for real estate businesses. We therefore prefer to leave the value empty instead.
    f_score = record.f_score && record.f_score > 0 ? record.f_score : nil
    snr = record.yearly_growth / record.rmsd
    if record.yearly_growth >= 0.2 &&
            snr > 1.5 &&
            record.price_vs_trend.abs <= record.rmsd
        print "\e[32m"
    elsif snr <= 1.0
        print "\e[31m"
    else
        print "\e[33m"
    end
    print "%-10s " % record.ticker
    print "%-20s " % record.name[0..19]
    print "%+6.1f%% " % (100 * record.yearly_growth)
    print "%6.1f%% " % (100 * record.rmsd)
    print "%6.2f " % snr
    print "%+6.1f%% " % (100 * record.price_vs_trend)
    print "%4s" % f_score.to_s
    print "%12s" % record.updated
    puts "\e[0m"
    yearly_growths << record.yearly_growth
end

if yearly_growths.any?
    average_yearly_growth = yearly_growths.inject(0.0) {|sum, yg| sum + yg} / yearly_growths.length
    puts "Average:                        %+6.1f%%" % (100 * average_yearly_growth)
end
