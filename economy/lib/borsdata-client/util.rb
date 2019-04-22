require 'fileutils'
require 'json'
require 'open-uri'
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
                    Time.now - File.mtime(cache_file) < max_age_seconds
                JSON.parse(File.read(cache_file))
            else
                t1 = Time.now
                uri = "https://#{API_HOST}#{path}?authKey=#{config['api_key']}"
                data = JSON.parse(open(uri).read)
                FileUtils.mkdir_p(File.dirname(cache_file))
                File.write(cache_file, JSON.pretty_generate(data))
                t2 = Time.now
                sleep [0.0, 0.55 - (t2 - t1)].max    # Max 2 calls per second
                data
            end
        end
    end
end
