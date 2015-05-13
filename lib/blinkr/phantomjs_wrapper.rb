require 'typhoeus'
require 'ostruct'
require 'tempfile'
require 'blinkr/http_utils'
require 'parallel'

module Blinkr
  class PhantomJSWrapper 
    include HttpUtils

    SNAP_JS = File.expand_path('snap.js', File.dirname(__FILE__))

    attr_reader :count

    def initialize config, context
      @config = config.validate
      @context = context
      @count = 0
    end

    def process_all urls, limit, opts = {}, &block
      Parallel.each(urls, :in_threads => Parallel.processor_count * 4) do |url|
        process url, limit, opts, &block
      end
    end

    def process url, limit, opts = {}, &block
      _process url, limit, limit, opts, &block
    end

    def name
      'phantomjs'
    end

    private

    def _process url, limit, max, opts = {}, &block
      raise "limit must be set. url: #{url}, limit: #{limit}, max: #{max}" if limit.nil?
      unless @config.skipped? url
        Tempfile.open('blinkr') do|f|
          if system "phantomjs #{SNAP_JS} #{url} #{@config.viewport} #{f.path}"
            json = JSON.load(File.read(f.path))
            response = Typhoeus::Response.new(code: 200, body: json['content'], effective_url: json['url'], mock: true)
            response.request = Typhoeus::Request.new(url)
            Typhoeus.stub(url).and_return(response)
            block.call response, json['resourceErrors'], json['javascriptErrors']
          else
            if limit > 1
              puts "Loading #{url} via phantomjs (attempt #{max - limit + 2} of #{max})" if @config.verbose
              _process url, limit - 1, max, &block
            else
              puts "Loading #{url} via phantomjs failed" if @config.verbose
              response = Typhoeus::Response.new(code: 0, status_message: "Server timed out after #{max} retries", mock: true)
              response.request = Typhoeus::Request.new(url)
              Typhoeus.stub(url).and_return(response)
              block.call response, nil, nil
            end
          end
        end
        @count += 1
      end
    end

  end
end
