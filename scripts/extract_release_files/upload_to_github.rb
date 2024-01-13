#!/usr/bin/env ruby

require 'logger'

require_relative 'vendor/bundle/bundler/setup'
require 'httparty'

def main
  input_folder = ARGV.shift || './downloads'
  release = read_release(input_folder)
  puts "Uploading version #{release[:version]} to GitHub..."

  github_release = get_or_create_github_release(release[:version])

  upload_release_assets(github_release, release[:files])
end

def read_release(input_folder)
  release_files = Dir.glob("#{input_folder}/dragonruby-for-ci-*.zip")
  raise 'One or more release files not found' if release_files.size < 6

  basename = File.basename(release_files.first)
  prefix_length = 'dragonruby-for-ci-'.length
  {
    files: release_files,
    # dragonruby-for-ci-5.7-[PLATFORM].zip
    version: basename[prefix_length..-1].split('-')[0]
  }
end

def get_or_create_github_release(version)
  release = DragonRubyForCiRepository.try_get_release(version)
  if release
    puts 'Release already exists'
    return release
  end

  release = DragonRubyForCiRepository.create_release(version)
  puts 'Release created'
  release
end

def upload_release_assets(github_release, files)
  upload_url = github_release['upload_url'].gsub('{?name,label}', '')
  threads = []
  files.each do |file|
    threads << Thread.new do
      upload_release_asset(upload_url, file)
    end
  end
  threads.each(&:join)
end

def upload_release_asset(upload_url, file)
  filename = File.basename(file)
  puts "Uploading #{filename}..."
  DragonRubyForCiRepository.upload_release_asset(upload_url, file)
  puts "Uploaded #{filename} successfully"
end

class DragonRubyForCiRepository
  include HTTParty
  base_uri 'https://api.github.com/repos/kfischer-okarin/dragonruby-for-ci'
  headers 'Accept' => 'application/vnd.github+json',
          'Authorization' => "Bearer #{ENV['GITHUB_TOKEN']}",
          'X-GitHub-Api-Version' => '2022-11-28'

  class << self
    def try_get_release(version)
      response = get("/releases/tags/#{version}")
      return JSON.parse(response.body) if response.code == 200
    end

    def create_release(version)
      response = post(
        '/releases',
        body: {
          tag_name: version,
          name: version
        }.to_json
      )

      raise "Failed to create release: #{response.code} #{response.body}" unless response.code == 201

      JSON.parse(response.body)
    end

    def upload_release_asset(upload_url, file)
      filename = File.basename(file)
      response = post(
        "#{upload_url}?name=#{filename}",
        body: File.read(file),
        headers: {
          'Content-Type' => 'application/zip'
        }
      )

      raise "Failed to upload release asset: #{response.code} #{response.body}" unless response.code == 201

      JSON.parse(response.body)
    end
  end
end

main if $PROGRAM_NAME == __FILE__
