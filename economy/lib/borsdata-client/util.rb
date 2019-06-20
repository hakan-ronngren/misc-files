require 'fileutils'
require 'net/http'
require 'json'
require 'yaml'

module Borsdata
    class Util
        API_HOST = 'apiservice.borsdata.se'

        def self.rootDirectory
            dir = File.expand_path('.borsdata-client', '~')
            FileUtils.mkdir_p(dir)
            dir
        end

        def self.config
            file = File.expand_path('config.yml', rootDirectory)
            unless File.exists?(file)
                File.write(file, {
                          'api_key' => 'xxx'
                }.to_yaml)
            end
            YAML.load(File.read(file))
        end

        def self.get_data(path, max_age_seconds)
            cache_file = File.expand_path("cache#{path}.json",
                                          rootDirectory)
            if File.exists?(cache_file) &&
                    (Borsdata.offline || (Time.now - File.mtime(cache_file) < max_age_seconds))
                JSON.parse(File.read(cache_file))
            elsif ! Borsdata.offline
                uri = URI("https://#{API_HOST}#{path}?authKey=#{config['api_key']}")
                data = nil
                begin
                    # TODO: finish this code, using https
                    #http = Net::HTTP.new(uri.hostname)
                    #http.set_debug_output($stderr)
                    #text = http.get([uri.path, uri.query].join('?'))
                    text = `curl -s --fail "#{uri.to_s}"`
                    raise "Failed to call #{uri.to_s}" unless $?.exitstatus == 0
                    data = JSON.parse(text)
                rescue SocketError
                    puts 'Failed to connect to the Börsdata API'
                    exit 1
                end
                FileUtils.mkdir_p(File.dirname(cache_file))
                File.write(cache_file, JSON.pretty_generate(data))
                sleep 0.55       # Max 2 calls per second
                data
            end
        end
    end
end
