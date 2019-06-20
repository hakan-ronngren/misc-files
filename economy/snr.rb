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
require 'yaml'
require 'pp'

$LOAD_PATH.push(File.expand_path('lib', Dir.pwd))
require 'borsdata-client'

DEFAULT_YEARS = 10.0
DEFAULT_MIN_GROWTH = 20.0
DEFAULT_MIN_SNR = 1.5

argv = ARGV

$years = DEFAULT_YEARS
$export = false
$min_growth_percent = DEFAULT_MIN_GROWTH
$min_snr = DEFAULT_MIN_SNR
$print_some_extra = false

def fail_usage()
    puts "usage: #{__FILE__} [--years <integer>] <TICKER_OR_PRICE_FILE> [...]"
    puts "    --years <float>        history length (default #{'%.1f' % DEFAULT_YEARS})"
    puts "    --min-growth <float>   minimum growth in percent (default #{'%.1f' % DEFAULT_MIN_GROWTH})"
    puts "    --min-snr <float>      minimum SNR (default #{'%.1f' % DEFAULT_MIN_SNR})"
    puts "    --export               export trend data as csv"
    exit 1
end

class Record
    attr_reader :name, :ticker, :updated, :f_score, :price_vs_trend, :yearly_growth, :rmsd, :full_years
    attr_reader :yearly_eps_growth, :yearly_tps_growth, :yearly_okf_growth
    attr_reader :yearly_eps_rmsd, :yearly_tps_rmsd, :yearly_okf_rmsd

    def initialize(identifier)
        @identifier = identifier
        if cache_up_to_date? && ! $export  # Need full price data to export
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

    def snr
        @yearly_growth / @rmsd
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
        @full_years     = values['full_years']
    end

    def write_to_cache
        h = {
            ticker:         @ticker,
            name:           @name,
            updated:        @updated,
            yearly_growth:  @yearly_growth,
            rmsd:           @rmsd,
            price_vs_trend: @price_vs_trend,
            f_score:        @f_score,
            full_years:     @full_years,
        }
        File.write(cache_file, h.to_json + "\n")
    end

    private

    def calculate
        import

        # TODO: what about when we are using weekly data? Subtract dates instead
        @full_years = @data.length / 251.0

        # Adapt a line to the logarithmic data
        model = Eps::Regressor.new(@data, target: :log_price)

        @yearly_growth = -1 +
            10 ** model.predict(date: 365) /
            10 ** model.predict(date: 0)
        if @yearly_growth.nan?
            @yearly_growth = 0.0
        end

        @rmsd = -1 +
            10 ** Math.sqrt(
                @data.inject(0) do |sum, item|
                    sum + (item[:log_price] - model.predict(date: item[:date])) ** 2
                end / @data.length)
        if @rmsd.nan?
            @rmsd = 0.001
        end

        # Current price vs. trend
        @price_vs_trend = -1 +
            10 ** @data.first[:log_price] /
            10 ** model.predict(date: @data.first[:date])
        if @price_vs_trend.nan?
            @price_vs_trend = 0.0
        end

        write_to_cache

        if $export
            output_file = File.expand_path("#{@ticker}-#{@name}-Price-with_trend.csv", Dir.pwd)
            File.open(output_file, 'w') do |f|
                #f.puts("\"%s\"\t\"\"\t\"\"" % File.basename(output_file))
                f.puts("\"%s\"" % File.basename(output_file))
                f.puts "\"Date\"\t\"Close price\"\t\"Predicted price\""
                @data.each do |item|
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
            File.new(cache_file).mtime > Time.now - 86400
    end

    def import
        @ticker = @identifier.upcase
        instrument = Borsdata::Instrument.by_ticker(@ticker)
        raise "No Borsdata instrument with ticker #{@ticker}" unless instrument
        @name = instrument.name
        @data = []
        @updated = '0'
        today = nil

        instrument.prices.reverse.each do |row|
            day = row[:date].to_time.to_i / 86400
            today ||= day
            break if day < today - 365.25 * $years
            price = row[:close]
            if ['SCA A', 'SCA B'].include?(@ticker) && row[:date].to_s <= '2017-06-09'
              # SCA including Essity
              price /= 4.824
            end
            @data.push({date: day, log_price: Math.log10(price)})
            @updated = [@updated, row[:date].to_s].max
        end
        @data.reverse! if @data.first[:date] < @data.last[:date]
        @f_score = instrument.f_score
    end
end

class BorsdataExcelRecord < FileBasedRecord

    def get_report_row(sheet, ix, expected_name)
        row = sheet.rows[ix]
        unless row[0] == expected_name
            raise "Expected row #{ix} to be #{expected_name}"
        end
        row
    end

    def import
        @ticker, @name = File.basename(@identifier, '.xls').split('-')
        Spreadsheet.client_encoding = 'UTF-8'
        book = Spreadsheet.open(@identifier)

        # Calculate F-score if possible.
        sheet = book.worksheet('R12')
        begin
            # TODO: Use column headings to make sure that we get the right values.
            # Sometimes the sheet has only one quarter per year (e.g. Zoom), and then
            # we compare over four years instead of one.
            if sheet
                sheet.ensure_rows_read
                turnover_row = get_report_row(sheet, 1, 'Omsättning')
                earnings_row = get_report_row(sheet, 5, 'Resultat Hänföring Aktieägare')
                no_of_shares_row = get_report_row(sheet, 7, 'Antal Aktier')
                current_assets_row = get_report_row(sheet, 15, 'Summa Omsättningstillgångar')
                total_assets_row = get_report_row(sheet, 16, 'Summa Tillgångar')
                long_debt_row = get_report_row(sheet, 18, 'Långfristiga Skulder')
                short_debt_row = get_report_row(sheet, 19, 'Kortfristiga Skulder')
                oper_cashflow_row = get_report_row(sheet, 23, 'Kassaf LöpandeVerk')
                margin_row = get_report_row(sheet, 45, 'Rörelsemarginal')
                roa_row = get_report_row(sheet, 52, 'Avkastning på T')
                @f_score = [
                    earnings_row.last > 0,
                    oper_cashflow_row.last > 0,
                    roa_row.last > roa_row[-5],
                    oper_cashflow_row.last > earnings_row.last,
                    (long_debt_row.last / total_assets_row.last) < (long_debt_row[-5] / total_assets_row[-5]),
                    (current_assets_row.last / short_debt_row.last) > (current_assets_row[-5] / short_debt_row[-5]),
                    no_of_shares_row.last <= no_of_shares_row[-5],
                    margin_row.last > margin_row[-5],
                    (turnover_row.last / total_assets_row.last) > (turnover_row[-5] / total_assets_row[-5]),
                ].select {|v| v}.count
            end
        rescue
            # Incomplete data (particularly for new companies) will crash us. No F-score.
        end

        # Calculate growth in turnover and earnings
        sheet = book.worksheet('Year')
        if sheet && $print_some_extra
            sheet.ensure_rows_read
            turnover_per_share_row = get_report_row(sheet, 33, 'Omsättning/Aktie')
            earnings_per_share_row = get_report_row(sheet, 35, 'Vinst/Aktie')
            okf_per_share_row  = get_report_row(sheet, 39, 'Operativ kassaflöde/Aktie')

            # Find the last full year column before any quarter column, which may in turn
            # be followed by an estimate column that looks like a full year except that
            # it has a yellow background (not taken into account here)
            first_full_year_col = 2
            while sheet.rows.first.to_a[first_full_year_col].to_i == 0
                first_full_year_col += 1
            end
            last_full_year_col = 0
            sheet.rows.first.to_a[first_full_year_col..-1].each_with_index do |h, i|
                break if h.start_with?('Q')
                last_full_year_col = first_full_year_col + i
            end

            ary = (first_full_year_col..last_full_year_col).map do |col|
                {
                    year: sheet.rows.first[col].to_i,
                    eps: earnings_per_share_row[col],
                    log_eps: Math.log10([earnings_per_share_row[col], 0.0].max),
                    tps: turnover_per_share_row[col],
                    log_tps: Math.log10(turnover_per_share_row[col] || 0.0),
                    okf: okf_per_share_row[col],
                    log_okf: Math.log10([okf_per_share_row[col] || 0.0, 0.001].max),
                }
            end

            eps_ary = ary.map { |e| ({year: e[:year], log_eps: e[:log_eps]}) }
            model = Eps::Regressor.new(eps_ary, target: :log_eps)
            @yearly_eps_growth = -1 +
                10 ** model.predict(year: 2001) /
                10 ** model.predict(year: 2000)
            @yearly_eps_rmsd = -1 +
                10 ** Math.sqrt(
                    eps_ary.inject(0) do |sum, item|
                        sum + (item[:log_eps] - model.predict(year: item[:year])) ** 2
                    end / eps_ary.length)

            tps_ary = ary.map { |e| ({year: e[:year], log_tps: e[:log_tps]}) }
            model = Eps::Regressor.new(tps_ary, target: :log_tps)
            @yearly_tps_growth = -1 +
                10 ** model.predict(year: 2001) /
                10 ** model.predict(year: 2000)
            @yearly_tps_rmsd = -1 +
                10 ** Math.sqrt(
                    tps_ary.inject(0) do |sum, item|
                        sum + (item[:log_tps] - model.predict(year: item[:year])) ** 2
                    end / tps_ary.length)

            okf_ary = ary.map { |e| ({year: e[:year], log_okf: e[:log_okf]}) }
            model = Eps::Regressor.new(okf_ary, target: :log_okf)
            @yearly_okf_growth = -1 +
                10 ** model.predict(year: 2001) /
                10 ** model.predict(year: 2000)
            @yearly_okf_rmsd = -1 +
                10 ** Math.sqrt(
                    okf_ary.inject(0) do |sum, item|
                        sum + (item[:log_okf] - model.predict(year: item[:year])) ** 2
                    end / okf_ary.length)
        end

        sheet = book.worksheet('PriceDay')            # new books have multiple sheets
        sheet = book.worksheets.first if sheet.nil?   # old ones have only one
        @updated = sheet.rows[1][0].to_s

        sheet.ensure_rows_read

        unless [sheet.rows.first[0], sheet.rows.first[4]] == %w(Date Closeprice)
            puts "#{@identifier}: not the expected Börsdata Excel format"
            exit 1
        end

        # Populate the data array with logarithmic data.
        # (Note: map, inject etc don't like break, they would return nil)
        @data = []
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
            @data.push({date: day, log_price: Math.log10(price)})
        end
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

        @data = []
        today = nil
        lines.each do |line|
            row = line.split(',')
            day = Date.parse(row[0]).to_time.to_i / 86400
            today ||= day
            break if day < today - 365.25 * $years
            price = row[4].to_f
            @data.push({date: day, log_price: Math.log10(price)})
        end
    end
end

while argv[0].start_with?('-') do
    if argv[0] == '--years' && argv[1].to_f > 0
        argv.shift
        $years = argv[0].to_f
        fail_usage if $years <= 0.0  # nil or anything else than a positive float
    elsif argv[0] == '--min-growth' && argv[1].to_f > 0
        argv.shift
        $min_growth_percent = argv[0].to_f
        fail_usage if $min_growth_percent <= 0.0  # nil or anything else than a positive float
    elsif argv[0] == '--min-snr' && argv[1].to_f > 0
        argv.shift
        $min_snr = argv[0].to_f
        fail_usage if $min_snr <= 0.0  # nil or anything else than a positive float
    elsif argv[0] == '--export'
        $export = true
    else
        fail_usage
    end
    argv.shift
end

$print_some_extra = true if argv.length == 1

records = []
argv.uniq.each do |arg|
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

if $print_some_extra &&
        records.first &&
        records.first.yearly_eps_growth &&
        records.first.yearly_tps_growth &&
        records.first.yearly_okf_growth
    puts "Omsättning/aktie %+.1f%% [%.1f%%]" % [
        100 * records.first.yearly_tps_growth,
        100 * records.first.yearly_tps_rmsd,
    ]
    puts "Operativt KF/aktie %+.1f%% [%.1f%%]" % [
        100 * records.first.yearly_okf_growth,
        100 * records.first.yearly_okf_rmsd,
    ]
    puts "Vinst/aktie %+.1f%% per år [%.1f%%]" % [
        100 * records.first.yearly_eps_growth,
        100 * records.first.yearly_eps_rmsd,
    ]
    puts
end

puts "\e[1mTicker     Name               %3d yrs ø    RMSD    SNR     Now   FS  Yrs     Updated\e[0m" % $years
yearly_growths = []

# Rearrange the records, putting the favored ones on top
records =
    records.select { |r| r.snr >= $min_snr && r.yearly_growth >= $min_growth_percent / 100.0 && r.full_years >= $years } +
    records.select { |r| r.snr < $min_snr || r.yearly_growth < $min_growth_percent / 100.0 || r.full_years < $years }

# List all records
records.each do |record|
    # Unfortunately, Börsdata reports 0 both when it really is 0 and when it is not applicable,
    # e.g. for real estate businesses. We therefore prefer to leave the value empty instead.
    f_score = record.f_score && record.f_score > 0 ? record.f_score : nil
    if record.snr < $min_snr || record.yearly_growth < $min_growth_percent / 100.0 || record.full_years < $years
        # red
        print "\e[31m"
    elsif record.price_vs_trend.abs <= record.rmsd
        # green
        print "\e[32m"
    else
        # yellow
        print "\e[33m"
    end
    print "%-10s " % record.ticker
    print "%-20s " % record.name[0..19]
    print "%+6.1f%% " % (100 * record.yearly_growth)
    print "%6.1f%% " % (100 * record.rmsd)
    print "%6.2f " % record.snr
    print "%+6.1f%% " % (100 * record.price_vs_trend)
    print "%4s" % f_score.to_s
    print "%5d" % record.full_years
    print "%12s" % record.updated
    puts "\e[0m"
    yearly_growths << record.yearly_growth
end

if yearly_growths.any?
    average_yearly_growth = yearly_growths.inject(0.0) {|sum, yg| sum + yg} / yearly_growths.length
    puts "Average:                        %+6.1f%%" % (100 * average_yearly_growth)
end
