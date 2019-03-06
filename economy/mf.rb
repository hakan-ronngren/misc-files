#!/usr/bin/env ruby

# This script is just a utility that processes data that I extract from a
# Börsdata filter configured like this:
#
# Info                 Senaste rapport      (any)
# Magic Formula        Rank                 0 <= rank <= 250
# Aktiekurs            Senaste              (any)
# (not used)
# Börsvärde            Senaste              (any)
# F-Score              Poäng                >= 4
# Info                 Land                 (any)
# Info                 Bransch              (any)
#
# Export as CSV sorted in any order.
#
# This script sorts the instruments in ascending MF Rank order, excluding
# instruments that are too small or in the wrong business.

require 'date'
require 'pp'

file = nil
dkksek = nil
eursek = nil
noksek = nil
invest = nil
max_count = 20
excluded_names = []

SELECTORS = [
    # Company name not in exclude list
    ->(r) {! excluded_names.include?(r[:company])},
    # Enterprise value at least 500 MSEK
    ->(r) {r[:ev] >= 500},
    # Nothing with oil (multiple categories)
    ->(r) {! r[:business].start_with?('Olja')},
    # Not betting
    ->(r) {r[:business] != 'Betting & Casino'},
    # F-score not too bad
    ->(r) {r[:f_score] >= 4},
    # Latest quarterly report not too old
    ->(r) {(Time.now - Date.strptime(r[:report_date], '%Y-%m-%d').to_time < 100 * 86400)}
]

EXPECTED_HEADER_FIRST = [
    '"Bolagsnamn"',
    '"Info"',
    '"Magic"',
    '"Aktiekurs"',
    '"Börsvärde"',
    '"F-Score"',
    '"Info"',
    '"Info"',
    '"Info"',
]
EXPECTED_HEADER_SECOND = [
    '""',
    '"Sen. Rapport"',
    '"Rank"',
    '"Senaste"',
    '"Senaste"',
    '"Poäng"',
    '"Land"',
    '"Sektor"',
    '"Bransch"',
]

def fail_usage
    puts "usage: #{File.basename(__FILE__)} <FLAGS...> <CSV_FILE>"
    puts "        Mandatory flags:"
    puts "        --dkk-sek <PRICE_IN_SEK>"
    puts "        --eur-sek <PRICE_IN_SEK>"
    puts "        --nok-sek <PRICE_IN_SEK>"
    puts "        --invest  <SEK_PER_INSTRUMENT>"
    puts "        Optional flags:"
    puts "        --max-count <NUMBER> (default: #{max_count})"
    puts "        --exclude <NAME>,<NAME>... (default: none)"
    exit(1)
end

argv = ARGV
while argv[0] do
    if argv[0] == '--dkk-sek' && argv[1].to_f > 0
        argv.shift
        dkksek = argv[0].to_f
    elsif argv[0] == '--eur-sek' && argv[1].to_f > 0
        argv.shift
        eursek = argv[0].to_f
    elsif argv[0] == '--nok-sek' && argv[1].to_f > 0
        argv.shift
        noksek = argv[0].to_f
    elsif argv[0] == '--invest' && argv[1].to_f > 0
        argv.shift
        invest = argv[0].to_f
    elsif argv[0] == '--max-count' && argv[1].to_i > 0
        argv.shift
        max_count = argv[0].to_i
    elsif argv[0] == '--exclude'
        argv.shift
        excluded_names = argv[0].split(',')
    elsif argv[0].start_with?('-')
        fail_usage
    elsif file.nil?
        file = argv[0]
    else
        fail_usage
    end
    argv.shift
end

unless dkksek && eursek && noksek && invest
    fail_usage
end

unless file && File.exists?(file)
    STDERR.puts "#{file}: not found"
    exit 1
end

age = (Time.now - File.mtime(file)) / 3600
if age >= 1
    puts "\e[1m\e[31mWarning: input file is #{age.floor} hours old\e[0m"
end

lines = File.readlines(file).map(&:strip).map {|l| l.force_encoding('ISO-8859-1').encode('UTF-8') }
headers = [lines.shift, lines.shift].map {|h| h.split(';')}
unless headers.first == EXPECTED_HEADER_FIRST
    puts "#{file}: not a Magic Formula list (wrong first line)"
    pp headers.first
    exit 1
end
unless headers.last == EXPECTED_HEADER_SECOND
    puts "#{file}: not a Magic Formula list (wrong second line)"
    pp headers.last
    exit 1
end

# Extract data to an array of hashmap records
records = lines.inject([]) do |rs, l|
    data = l.split(';')

    data =
        data[0..1].map { |v| v.tr('"', '') } +
        [data[2].to_i] +
        data[3..4].map { |v| v.tr(',', '.').to_f } +
        [data[5].to_i] +
        data[6..8].map { |v| v.tr('"', '') }

    r = {
        company:     data[0],
        report_date: data[1],
        mf_rank:     data[2],
        price:       data[3],
        ev:          data[4],
        f_score:     data[5],
        business:    data[8],
    }

    unless r[:report_date] =~ /^\d{4}-\d{2}-\d{2}$/
        r[:report_date] = '1970-01-01'
    end

    country = data[6]
    if country == 'Sverige'
        nil  # correct price
    elsif country == 'Danmark'
        r[:ev] *= dkksek
        r[:price] *= dkksek
    elsif country == 'Finland'
        r[:ev] *= eursek
        r[:price] *= eursek
    elsif country == 'Norge'
        r[:ev] *= noksek
        r[:price] *= noksek
    else
        raise "unexpected country: " + country
    end

    rs.push(r)
end

records.select! {|r| SELECTORS.all? {|s| s.call(r)}}
records.sort_by! {|r| r[:mf_rank]}

puts "Instrument                    Buy      Price  F-score  Business"
puts "--------------------------------------------------------------------------------"
records.first(max_count).each do |r|
    print "%-27s " % r[:company][0,25]
    print "%5d  " % (invest / r[:price]).floor
    print "%9.2f   " % r[:price]
    print "%3s     " % r[:f_score]
    print r[:business]
    puts
end
