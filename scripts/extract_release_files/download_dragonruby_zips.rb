#!/usr/bin/env ruby

require 'logger'
require 'net/http'
require 'optparse'
require 'uri'

require_relative 'vendor/bundle/bundler/setup'
require 'httparty'
require 'progress_bar'


def redact_values!(message, *secret_values)
  secret_values.each do |secret_value|
    message.gsub!(secret_value, '[REDACTED]')
  end
end

LOGGER = Logger.new(STDOUT)
LOGGER.level = Logger::INFO
LOGGER.formatter = proc do |_severity, _datetime, _progname, msg|
  redact_values!(msg, ENV['ITCH_IO_PASSWORD'])
  "#{msg}\n"
end

def main
  options = parse_options
  output_folder = ARGV.shift || './downloads'
  setup_verbose_logging if options[:verbose]
  check_environment_variables

  standard_download_threads = download_standard_version(output_folder)
  standard_download_threads.each(&:join)

  pro_download_threads = download_pro_version(output_folder)
  pro_download_threads.each(&:join)
end

def parse_options
  result = {}

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] [output_folder]"

    opts.on('-v', '--verbose', 'Run verbosely') do |v|
      result[:verbose] = v
    end
  end
  parser.parse!

  result
end

def setup_verbose_logging
  LOGGER.level = Logger::DEBUG
  LOGGER.formatter = proc do |severity, datetime, _progname, msg|
    redact_values!(msg, ENV['ITCH_IO_PASSWORD'])
    "#{datetime.strftime('%Y-%m-%d %H:%M:%S,%L')} #{severity} - #{msg}\n"
  end
end

def check_environment_variables
  required_environment_variables = [
    'ITCH_IO_USERNAME',
    'ITCH_IO_PASSWORD',
    'ITCH_IO_DRAGONRUBY_DOWNLOAD_KEY',
    'DRAGONRUBY_PRO_USERNAME',
    'DRAGONRUBY_PRO_PASSWORD'
  ]
  missing_environment_variables = required_environment_variables.reject { |required_environment_variable|
    ENV[required_environment_variable]
  }
  return if missing_environment_variables.empty?

  LOGGER.error "Missing environment variables #{missing_environment_variables}"
  exit 1
end

def download_standard_version(output_folder)
  browser = ItchIoBrowser.new(
    username: ENV['ITCH_IO_USERNAME'],
    password: ENV['ITCH_IO_PASSWORD'],
    download_key: ENV['ITCH_IO_DRAGONRUBY_DOWNLOAD_KEY']
  )
  current_page = browser.visit_download_page
  if current_page == :login
    current_page = browser.login
    browser.handle_two_factor_auth if current_page == :two_factor_auth
  end

  threads = []
  ['dragonruby-gtk-windows-amd64.zip', 'dragonruby-gtk-macos.zip', 'dragonruby-gtk-linux-amd64.zip'].each do |filename|
    threads << Thread.start do
      browser.download_upload(browser.uploads[filename], output_folder)
    end
  end
  threads
end

class ItchIoBrowser
  include HTTParty

  def initialize(username:, password:, download_key:)
    @username = username
    @password = password
    @download_key = download_key
    @current_url = nil
    @last_response = nil
    @cookies = load_cookies
    @csrf_token = nil
  end

  def current_page
    if @current_url.start_with? 'https://itch.io/login'
      :login
    elsif @current_url.start_with? 'https://itch.io/totp/verify'
      :two_factor_auth
    elsif @current_url.start_with? 'https://dragonruby.itch.io/dragonruby-gtk/download'
      :download
    else
      raise "Unknown page #{@current_url}\n\n#{@last_response.body}"
    end
  end

  def html
    @last_response.parsed_response
  end

  def visit_download_page
    visit download_page_url
  end

  def visit(url)
    handle_redirect do
      LOGGER.debug "Visiting #{url}"
      @last_response = self.class.get(url, no_follow: true, cookies: @cookies)
      @current_url = url
      store_response_cookies @last_response
      current_page
    end
  end

  def login
    LOGGER.info "Logging in as #{@username}..."
    post_form(
      @current_url,
      body: {
        username: @username,
        password: @password,
        csrf_token: csrf_token,
        tz: tz
      }
    )
  end

  def handle_two_factor_auth
    print "Enter the code from your authenticator app: "
    verification_code = gets.chomp
    post_form(
      @current_url,
      body: {
        code: verification_code,
        user_id: user_id,
        tz: tz,
        csrf_token: csrf_token
      }
    )
  end

  def uploads
    result = {}
    pattern = /<div class="upload">.*?<\/strong>/
    html.scan(pattern).each do |upload_html|
      strong_tag = all_tags('strong', in_html: upload_html).first
      filename = tag_attribute(strong_tag, 'title')
      result[filename] = {
        upload_id: tag_attribute(upload_html, 'data-upload_id'),
        filename: filename
      }
    end
    LOGGER.debug "Found uploads #{result}"
    result
  end

  def download_upload(upload, output_folder)
    LOGGER.info "Downloading #{upload[:filename]}..."
    response = post_form(
      "https://dragonruby.itch.io/dragonruby-gtk/file/#{upload[:upload_id]}",
      body: {
        csrf_token: csrf_token
      },
      query: {
        key: @download_key,
        source: 'game_download'
      }
    )
    download_url = response.parsed_response['url']
    download_file_with_progress(download_url, File.join(output_folder, upload[:filename]))
  end

  private

  def post_form(url, body:, **options)
    LOGGER.debug "Posting to #{url} with #{body}"
    handle_redirect do
      self.class.post(
        url,
        body: URI.encode_www_form(body),
        cookies: @cookies,
        no_follow: true,
        **options
      )
    end
  end

  def handle_redirect
    yield
  rescue HTTParty::RedirectionTooDeep => e
    LOGGER.debug "Redirected to #{e.response['location']}"
    store_response_cookies(e.response)
    visit e.response['location']
  end

  def store_response_cookies(response)
    cookies = case response
              when HTTParty::Response
                response.headers['set-cookie']
              when Net::HTTPResponse
                response['set-cookie']
              else
                raise "Unknown response type #{response.class}"
              end
    return unless cookies

    store_cookies(cookies)
  end

  def user_id
    user_id_hidden_input = all_tags('input').find { |tag| tag.include? 'user_id' }
    raise 'Could not find user_id' unless user_id_hidden_input

    tag_attribute(user_id_hidden_input, 'value')
  end

  def csrf_token
    csrf_token_tag = all_tags('meta').find { |tag| tag.include? 'csrf_token' }
    raise 'Could not find csrf_token' unless csrf_token_tag

    tag_attribute(csrf_token_tag, 'value')
  end

  def all_tags(tag, in_html: nil)
    pattern = /<#{tag}[^>]*>/
    (in_html || html).scan(pattern)
  end

  def tag_attribute(tag_html, attribute)
    pattern = /#{attribute}="([^"]+)"/
    match = pattern.match tag_html
    raise "Could not find #{attribute} in #{tag_html}" unless match

    match[1]
  end

  def tz
    (-Time.now.utc_offset / 60).to_s
  end

  def load_cookies
    result = HTTParty::CookieHash.new
    result.add_cookies(File.read('cookies.txt')) if File.exist? 'cookies.txt'
    LOGGER.debug "Loaded cookies #{result}"
    result
  end

  def store_cookies(cookies)
    LOGGER.debug "Newly Storing cookies #{cookies}"
    @cookies.add_cookies(cookies)
    File.write('cookies.txt', @cookies.to_cookie_string)
    LOGGER.debug "All Stored cookies #{@cookies}"
  end

  def download_page_url
    "https://dragonruby.itch.io/dragonruby-gtk/download/#{@download_key}"
  end
end

def download_pro_version(output_folder)
  download_links_json = HTTParty.get('https://dragonruby.org/api').parsed_response
  LOGGER.debug "Download links #{download_links_json}"

  threads = []
  ['pro_windows', 'pro_mac', 'pro_linux'].each do |platform|
    get_download_url_url = download_links_json['__links__']['download'][platform]
    download_url = HTTParty.get(
      get_download_url_url,
      basic_auth: {
        username: ENV['DRAGONRUBY_PRO_USERNAME'],
        password: ENV['DRAGONRUBY_PRO_PASSWORD']
      }
    ).body
    threads << Thread.start do
      filename = PRO_FILENAMES[platform]
      LOGGER.info "Downloading #{filename}..."
      download_file_with_progress(
        download_url,
        File.join(output_folder, File.basename(filename))
      )
    end
  end
  threads
end

PRO_FILENAMES = {
  'pro_windows' => 'dragonruby-pro-windows-amd64.zip',
  'pro_mac' => 'dragonruby-pro-macos.zip',
  'pro_linux' => 'dragonruby-pro-linux-amd64.zip'
}.freeze

def download_file_with_progress(url, output_filename)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request_get(uri) do |response|
      total_bytes = response.content_length
      downloaded_bytes = 0
      percent_complete = 0
      bar = ProgressBar.new
      LOGGER.debug "Downloading to #{output_filename} from #{url}"
      File.open(output_filename, 'wb') do |file|
        response.read_body do |fragment|
          file.write(fragment)
          downloaded_bytes += fragment.length
          new_percent_complete = (downloaded_bytes * 100 / total_bytes).to_i
          if new_percent_complete != percent_complete
            percent_complete = new_percent_complete
            bar.increment!
          end
        end
      end
    end
  end
end

main if $PROGRAM_NAME == __FILE__
