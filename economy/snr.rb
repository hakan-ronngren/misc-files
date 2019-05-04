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
require 'spreadsheet'   # https://github.com/zdavatz/spreadsheet

$LOAD_PATH.push(File.expand_path('lib', Dir.pwd))
require 'borsdata-client'

DEFAULT_YEARS = 10

argv = ARGV

years = DEFAULT_YEARS
export = false

def fail_usage()
    puts "usage: #{__FILE__} [--years <integer>] <TICKER_OR_PRICE_FILE> [...]"
    puts "    --years <float>        history length (default #{DEFAULT_YEARS}"
    puts "    --export               export trend data as csv"
    exit 1
end

def import_borsdata_instrument(instrument, years)
    data = []
    updated = '0'
    today = nil
    instrument.prices.reverse.each do |row|
        day = row[:date].to_time.to_i / 86400
        today ||= day
        break if day < today - 365.25 * years
        data.push({date: day, log_price: Math.log10(row[:close])})
        updated = [updated, row[:date].to_s].max
    end
    data.reverse! if data.first[:date] < data.last[:date]
    return [data, updated, instrument.f_score]
end

def import_borsdata_excel(input_file, years)
    Spreadsheet.client_encoding = 'ISO-8859-1'
    book = Spreadsheet.open(input_file)
    sheet = book.worksheets.first

    # Prevent a race condition
    sheet.ensure_rows_read

    unless [sheet.rows.first[0], sheet.rows.first[4]] == %w(Date Closeprice)
        puts "#{input_file}: not the expected Börsdata Excel format"
        exit 1
    end

    # Populate the data array with logarithmic data.
    # (Note: map, inject etc don't like break, they would return nil)
    data = []
    today = nil
    sheet.rows[1..-1].each do |row|
        day = row[0].to_time.to_i / 86400
        today ||= day
        break if day < today - 365.25 * years
        price = row[4].to_f
        # Disregard invalid points
        next unless day > 10000 &&
            day <= Time.now.to_i / 86400 &&
            price > 0.0
        data.push({date: day, log_price: Math.log10(price)})
    end

    return [data, sheet.rows[1][0].to_s]
end

def import_yahoo_csv(input_file, years)
    lines = File.readlines(input_file).map(&:strip)
    if lines.first != 'Date,Open,High,Low,Close,Adj Close,Volume'
        puts "#{input_file}: not the expected Yahoo csv format"
        exit 1
    end
    lines.shift

    # Some yahoo csv files are in ascending date order, others in
    # descending. We expect descending.
    d0, d1 = [lines[0].split(',').first, lines[1].split(',').first]
    if d0 < d1
        lines.reverse!
    end

    data = []
    today = nil
    lines.each do |line|
        row = line.split(',')
        day = Date.parse(row[0]).to_time.to_i / 86400
        today ||= day
        break if day < today - 365.25 * years
        price = row[4].to_f
        data.push({date: day, log_price: Math.log10(price)})
    end

    return [data, lines.first.split(',')[0]]
end

while argv[0].start_with?('-') do
    if argv[0] == '--years' && argv[1].to_f > 0
        argv.shift
        years = argv[0].to_f
        fail_usage if years <= 0.0  # nil or anything else than a positive float
    elsif argv[0] == '--export'
        export = true
    else
        fail_usage
    end
    argv.shift
end

records = []
argv.each do |file_or_ticker|
    instrument = Borsdata::Instrument.by_ticker(file_or_ticker)

    if File.file?(file_or_ticker)
        ticker, name = file_or_ticker.split('-')
        if file_or_ticker.end_with?('.xls')
            data, updated = import_borsdata_excel(file_or_ticker, years)
        elsif file_or_ticker.end_with?('.csv')
            data, updated = import_yahoo_csv(file_or_ticker, years)
        else
            fail_usage
        end
    elsif instrument
        ticker = file_or_ticker
        name = instrument.name
        data, updated, f_score = import_borsdata_instrument(instrument, years)
    else
        puts "#{file_or_ticker}: not found, ignoring this instrument"
        next
    end

    # Adapt a line to the logarithmic data
    model = Eps::Regressor.new(data, target: :log_price)

    record = {
        ticker:  ticker,
        name:    name,
        updated: updated,
        f_score: f_score
    }

    record[:yearly_growth] = -1 +
        10 ** model.predict(date: 365) /
        10 ** model.predict(date: 0)

    rmsd = Math.sqrt(
        data.inject(0) do |sum, item|
            sum + (item[:log_price] - model.predict(date: item[:date])) ** 2
        end / data.length
    )

    record[:rmsd] = 10.0 ** rmsd - 1

    # Current price vs. trend
    record[:price_vs_trend] = -1 +
        10 ** data.first[:log_price] /
        10 ** model.predict(date: data.first[:date])

    records.push(record)

    if export
        output_file = File.expand_path("#{ticker}-#{name}-Price-with_trend.csv", Dir.pwd)
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

# Sort by descending SNR
records.sort_by! do |record|
    -record[:yearly_growth] / record[:rmsd]
end

puts "\e[1mTicker     Name               %3d yrs ø    RMSD    SNR     Now   FS     Updated\e[0m" % years
yearly_growths = []
records.each do |record|
    # Unfortunately, Börsdata reports 0 both when it really is 0 and when it is not applicable,
    # e.g. for real estate businesses. We therefore prefer to leave the value empty instead.
    f_score = record[:f_score] && record[:f_score] > 0 ? record[:f_score] : nil
    snr = record[:yearly_growth] / record[:rmsd]
    if record[:yearly_growth] >= 0.2 &&
            snr > 1.5 &&
            record[:price_vs_trend].abs <= record[:rmsd]
        print "\e[32m"
    elsif snr <= 1.0
        print "\e[31m"
    else
        print "\e[33m"
    end
    print "%-10s " % record[:ticker]
    print "%-20s " % record[:name][0..19]
    print "%+6.1f%% " % (100 * record[:yearly_growth])
    print "%6.1f%% " % (100 * record[:rmsd])
    print "%6.2f " % snr
    print "%+6.1f%% " % (100 * record[:price_vs_trend])
    print "%4s" % f_score.to_s
    print "%12s" % record[:updated]
    puts "\e[0m"
    yearly_growths << record[:yearly_growth]
end

average_yearly_growth = yearly_growths.inject(0.0) {|sum, yg| sum + yg} / yearly_growths.length
puts "Average:                        %+6.1f%%" % (100 * average_yearly_growth)
