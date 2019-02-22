#!/usr/bin/env bundle exec ruby

# Calculate the Signal (value growth) to Noise (variations) Ratio
# for one or several instruments.
#
# Pass a list of *-Price.xls files from Börsdata or similarly named
# *-Price.csv files from Yahoo as arguments
# Optionally use the --years option to choose where to cut the history

require 'date'
require 'eps'           # https://github.com/ankane/eps
require 'spreadsheet'   # https://github.com/zdavatz/spreadsheet

DEFAULT_YEARS = 10

argv = ARGV

years = DEFAULT_YEARS
export = false

def fail_usage()
    puts "usage: #{__FILE__} [--years <integer>] <BORSDATA-Price.xls> [...]"
    puts "    --years <float>        history length (default #{DEFAULT_YEARS}"
    puts "    --export               export trend data as csv"
    exit 1
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

    record = {}

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

    data
end

def import_yahoo_csv(input_file, years)
    lines = File.readlines(input_file).map(&:strip)
    if lines.first != 'Date,Open,High,Low,Close,Adj Close,Volume'
        puts "#{input_file}: not the expected Yahoo csv format"
        exit 1
    end
    lines.shift

    data = []
    today = nil
    lines.reverse.each do |line|
        row = line.split(',')
        day = Date.parse(row[0]).to_time.to_i / 86400
        today ||= day
        break if day < today - 365.25 * years
        price = row[4].to_f
        data.push({date: day, log_price: Math.log10(price)})
    end

    data
end

while argv[0].start_with?('-') do
    if argv[0] == '--years' && argv[1].to_i > 0
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
argv.each do |input_file|
    unless File.file?(input_file)
        puts "#{input_file}: not found, ignoring this file"
        next
    end

    if input_file.end_with?('.xls')
        data = import_borsdata_excel(input_file, years)
    elsif input_file.end_with?('.csv')
        data = import_yahoo_csv(input_file, years)
    else
        fail_usage
    end

    # Adapt a line to the logarithmic data
    model = Eps::Regressor.new(data, target: :log_price)

    record = {}
    record[:ticker], record[:name] = input_file.split('-')

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
        output_file = File.join(
            File.dirname(input_file),
            input_file.gsub(/\..*/, '') + '-with_trend.csv')

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

puts "\e[1mTicker     Name                   %3d yrs ø    RMSD    SNR     Now\e[0m" % years
records.each do |record|
    snr = record[:yearly_growth] / record[:rmsd]
    if snr > 1.5 && record[:price_vs_trend].abs <= record[:rmsd]
        print "\e[32m"
    elsif snr <= 1.0
        print "\e[31m"
    else
        print "\e[33m"
    end
    print "%-10s " % record[:ticker]
    print "%-24s " % record[:name]
    print "%+6.1f%% " % (100 * record[:yearly_growth])
    print "%6.1f%% " % (100 * record[:rmsd])
    print "%6.2f " % snr
    print "%+6.1f%% " % (100 * record[:price_vs_trend])
    puts "\e[0m"
end
