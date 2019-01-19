#!/usr/bin/env ruby

# This script is just a utility that processes data that I extract from a
# Börsdata filter configured like this:
#
# F-Score              Poäng                (any)
# Kursutveckling       Utveckling 10 år     > 304  (avg +15%/year)
# Kursutveckling       Utveckling 5 år      > 101       - " -
# Kursutveckling       Utveckling 3 år      > 52        - " -
# Kursutveckling       Utveckling 1 år      > 15        - " -
# Relativ utveckling   Utveckling 6m        > 0    (beat OMXS30)
# Relativ utveckling   Utveckling 3m        > 0         - " -
# Aktiekurs            Senaste              (any)
#
# Export as CSV sorted in any order.
#
# This script sorts the instruments in falling order of evenness over the
# different partisions of the last ten years (10-5, 5-3, 3-1 and 1-now),
# and also highlights where the average yearly percentage requirement is
# not satisfied.
#
# When I started to use this script, I wanted to see the Piotroski F-score
# of the companies that the screening procedure picked. I noticed that even
# though there is no fundamental data included anywhere in the procedure,
# the top companies tend to have quite a high score. I guess that companies
# that have delivered +15% yearly for at least ten years are generally quite
# well managed.
#
# P/E values are generally high, though. This screening procedure does not
# give you a list of undiscovered gems... :-)
#
# Usage: femtonplussare.rb <CSV_file>

require 'pp'

REQUIRED_YEARLY_PERCENTAGE = 10.0
REQUIRED_YEARLY_MULTIPLIER = 1 + REQUIRED_YEARLY_PERCENTAGE / 100.0

EXPECTED_HEADER_FIRST = [
    '"Bolagsnamn"',
    '"F-Score"',
    '"Kursutveck."',
    '"Kursutveck."',
    '"Kursutveck."',
    '"Kursutveck."',
    '"Rel. utveck."',
    '"Rel. utveck."',
    '"Aktiekurs"',
]
EXPECTED_HEADER_SECOND = [
    '""',
    '"Poäng"',
    '"Utveck.  10 år"',
    '"Utveck.  5 år"',
    '"Utveck.  3 år"',
    '"Utveck.  1 år"',
    '"Utveck. 6m"',
    '"Utveck. 3m"',
    '"Senaste"',
]

unless File.exists?(ARGV[0])
    STDERR.puts "#{ARGV[0]}: not found"
    exit 1
end

lines = File.readlines(ARGV[0]).map(&:strip).map {|l| l.force_encoding('ISO-8859-1').encode('UTF-8') }
headers = [lines.shift, lines.shift].map {|h| h.split(';')}
unless headers.first == EXPECTED_HEADER_FIRST
    puts "#{ARGV[0]}: not a +15% list (wrong first line)"
    pp headers.first
    exit 1
end
unless headers.last == EXPECTED_HEADER_SECOND
    puts "#{ARGV[0]}: not a +15% list (wrong second line)"
    pp headers.last
    exit 1
end

# Extract data to an array of hashmap records
records = lines.inject([]) do |rs, l|
    data = l.split(';').map do |v|
        # Delete quotes
        v.tr!('"', '')
        # Use decimal period instead of comma
        if v =~ /-?\d+,\d+/
            v = v.tr(',', '.').to_f
        end
        v
    end

    if data[1].empty?
        data[1] = '-'
    end

    r = {
        # Company name
        company: data[0],
        # Piotroski F-score
        fscore: data[1],
        # Average yearly multiplier from year -10 to year -5
        m10to5: ((1.0 + data[2]) / (1.0 + data[3])) ** 0.2,
        # Average yearly multiplier from year -5 to year -3
        m5to3: ((1.0 + data[3]) / (1.0 + data[4])) ** 0.5,
        # Average yearly multiplier from year -3 to year -1
        m3to1: ((1.0 + data[4]) / (1.0 + data[5])) ** 0.5,
        # Multiplier last year
        m1to0: (1.0 + data[5]),
        # Relative to OMXS30, 6 months
        rel6: (1.0 + data[6]),
        # Relative to OMXS30, 3 months
        rel3: (1.0 + data[7]),
        # Latest price
        price: data[8],
    }

    # Give points to all companies, but punish those that cheated their way
    # into the list by having an extreme multiplier the last year, masking
    # poor performance earlier years.
    if [:m10to5, :m5to3, :m3to1].map {|k| r[k]}.min >= REQUIRED_YEARLY_MULTIPLIER
        r[:points] = 0
    else
        r[:points] = -1000
    end

    rs.push(r)
end

[:m10to5, :m5to3, :m3to1, :m1to0].each do |key|
    records.sort_by! do |r|
        r[key]
    end.each_with_index do |r, i|
        r[:points] += i
    end
end

records.sort_by! do |r|
    r[:points] || -1
end

def print_yearly_percentage(multiplier, orig_color)
    print "\e[31m" if multiplier < REQUIRED_YEARLY_MULTIPLIER
    printf "%6.1f%% ", (100.0 * (multiplier - 1.0))
    print orig_color
end

print "\e[1m"
puts "Instrument          F-score  10-5y ø  5-3y ø  3-1y ø      1y    6m rel  3m rel      price"
print "\e[0m"
records.reverse.each do |r|
    print "%-20s " % r[:company][0,18]
    print "(FS %s)  " % r[:fscore]

    if [r[:m10to5], r[:m5to3], r[:m3to1], r[:m1to0]].min > REQUIRED_YEARLY_MULTIPLIER
        color = "\e[32m"
    else
        color = "\e[0m"
    end
    print color
    print_yearly_percentage(r[:m10to5], color)
    print_yearly_percentage(r[:m5to3], color)
    print_yearly_percentage(r[:m3to1], color)
    print_yearly_percentage(r[:m1to0], color)
    print "\e[0m  "

    printf "%6.1f%% ", (100.0 * (r[:rel6] - 1.0))
    printf "%6.1f%%   ", (100.0 * (r[:rel3] - 1.0))
    print "%8.2f" % r[:price]
    puts
end
puts "(#{records.length} instruments)"
