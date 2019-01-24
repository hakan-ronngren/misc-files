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

# Overall requirement
HARD_REQUIRED_PERCENTAGE = 15.0
HARD_REQUIRED_MULTIPLIER = 1 + HARD_REQUIRED_PERCENTAGE / 100.0

# Weaker requirement to allow for some variation
WEAK_REQUIRED_PERCENTAGE = 10.0
WEAK_REQUIRED_MULTIPLIER = 1 + WEAK_REQUIRED_PERCENTAGE / 100.0

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

file = nil
show_all = false
show_prices = false

while (arg = ARGV.shift) do
    if ['-a', '--all'].include? arg
        show_all = true
    elsif ['-p', '--prices'].include? arg
        show_prices = true
    elsif arg[0] == '-'
        puts "usage: #{File.basename(__FILE__)} [options] <CSV_FILE>"
        puts "        -a --all     Display even the instruments that do not qualify"
        exit(1)
    else
        file = arg
    end
end

unless file && File.exists?(file)
    STDERR.puts "#{file}: not found"
    exit 1
end

lines = File.readlines(file).map(&:strip).map {|l| l.force_encoding('ISO-8859-1').encode('UTF-8') }
headers = [lines.shift, lines.shift].map {|h| h.split(';')}
unless headers.first == EXPECTED_HEADER_FIRST
    puts "#{file}: not a +15% list (wrong first line)"
    pp headers.first
    exit 1
end
unless headers.last == EXPECTED_HEADER_SECOND
    puts "#{file}: not a +15% list (wrong second line)"
    pp headers.last
    exit 1
end

# Extract data to an array of hashmap records
records = lines.inject([]) do |rs, l|
    data = l.split(';')

    data =
        data[0..1].map { |v| v.tr('"', '') } +
        data[2..8].map { |v| v.tr(',', '.').to_f }

    # Prefer '-' to empty string if F-score is missing
    if data[1].empty?
        data[1] = '-'
    end

    r = {
        # Company name
        company: data[0],
        # Piotroski F-score
        fscore: data[1],
        # Average yearly multiplier from year -10 to current
        m10to0: (1.0 + data[2]) ** 0.1,
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

    r[:points] = 0

    r[:weaknesses] = []
    # Over the entire period, we require a certain average growth, and the
    # same for the last year.
    [:m10to0, :m1to0].each do |k|
        if r[k] < HARD_REQUIRED_MULTIPLIER
            r[:weaknesses].push(k)
        end
    end

    # To not recommend companies that have accumulated most of their 10-years
    # value growth in the recent year, require a certain level of growth on
    # average during each of the period.
    [:m10to5, :m5to3, :m3to1].each do |k|
        if r[k] < WEAK_REQUIRED_MULTIPLIER
            r[:weaknesses].push(k)
        end
    end
    # Also do not recommend companies that currently have a negative relative
    # momentum (3 or 6 months)
    [:rel6, :rel3].each do |k|
        if r[k] < 1.0
            r[:weaknesses].push(k)
        end
    end

    rs.push(r)
end

[:m10to5, :m5to3, :m3to1, :m1to0].each do |key|
    records.sort_by! do |r|
        r[key]
    end.each_with_index do |r, i|
        if r[:weaknesses].empty?
            r[:points] += i
        end
    end
end

unless show_all
    records.select! {|r| r[:weaknesses].empty?}
end

records.sort_by! do |r|
    r[:points]
end

def multiplier_as_percentage(m)
    100 * (m - 1.0)
end

def print_percentage_field(record, key, format)
    if record[:weaknesses].empty?
        print "\e[32m"
    elsif record[:weaknesses].include?(key)
        print "\e[31m"
    else
        print "\e[0m"
    end
    printf '%6.1f%% ', multiplier_as_percentage(record[key])
    print "\e[0m"
end

print "\e[1m"
print "Instrument          F-score  10yrs ø  10-5y ø  5-3y ø  3-1y ø      1y    6m rel  3m rel"
print "      price" if show_prices
print "\e[0m"
puts
sums = {
    sum10to0: 0.0,
    sum10to5: 0.0,
    sum5to3:  0.0,
    sum3to1:  0.0,
    sum1to0:  0.0,
    sumr6:    0.0,
    sumr3:    0.0
}
records.reverse.each do |r|
    print "%-20s " % r[:company][0,18]
    print "%3s     " % r[:fscore]

    print_percentage_field(r, :m10to0, '%6.1f%% ')
    print_percentage_field(r, :m10to5, '%6.1f%% ')
    print_percentage_field(r, :m5to3, '%6.1f%% ')
    print_percentage_field(r, :m3to1, '%6.1f%% ')
    print_percentage_field(r, :m1to0, '%6.1f%% ')

    print '  '

    print_percentage_field(r, :rel6, '%6.1f%% ')
    print_percentage_field(r, :rel3, '%6.1f%% ')

    print "%10.2f" % r[:price] if show_prices
    puts

    sums[:sum10to0] += r[:m10to0]
    sums[:sum10to5] += r[:m10to5]
    sums[:sum5to3]  += r[:m5to3]
    sums[:sum3to1]  += r[:m3to1]
    sums[:sum1to0]  += r[:m1to0]
    sums[:sumr6]    += r[:rel6]
    sums[:sumr3]    += r[:rel3]
end
n = records.length
h = records.inject({sum6: 0, sum3: 0}) do |h, r|
    h[:sum6] += r[:rel6]
    h[:sum3] += r[:rel3]
    h
end

print "\e[1m%-20s\e[0m " % 'Average'
print ' ' * 8
print "%6.1f%% " % multiplier_as_percentage(sums[:sum10to0] / n)
print "%6.1f%% " % multiplier_as_percentage(sums[:sum10to5] / n)
print "%6.1f%% " % multiplier_as_percentage(sums[:sum5to3] / n)
print "%6.1f%% " % multiplier_as_percentage(sums[:sum3to1] / n)
print "%6.1f%% " % multiplier_as_percentage(sums[:sum1to0] / n)
print '  '
print "%6.1f%% " % multiplier_as_percentage(sums[:sumr6] / n)
print "%6.1f%% " % multiplier_as_percentage(sums[:sumr3] / n)
puts

average_rel6 = h[:sum6] / n
average_rel3 = h[:sum3] / n
print "\e[1m%-20s\e[0m " % 'Extrapolated yearly'
print ' ' * 50
print "%6.1f%% " % multiplier_as_percentage(average_rel6 ** 2)
print "%6.1f%% " % multiplier_as_percentage(average_rel3 ** 4)
puts

puts "(%d instruments)" % n
