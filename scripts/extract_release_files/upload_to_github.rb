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
  response = DragonRubyForCiRepository.get("/releases/tags/#{version}")
  if response.code == 200
    puts 'Release already exists'
    return JSON.parse(response.body)
  end

  response = DragonRubyForCiRepository.post(
    '/releases',
    body: {
      tag_name: version,
      name: version,
    }.to_json
  )

  if response.code == 201
    puts 'Release created'
    return JSON.parse(response.body)
  end

  raise "Failed to create release: #{response.code} #{response.body}"
end

def upload_release_assets(github_release, files)
  threads = []
  files.each do |file|
    threads << Thread.new do
      upload_release_asset(github_release, file)
    end
  end
  threads.each(&:join)
end

def upload_release_asset(github_release, file)
  filename = File.basename(file)
  puts "Uploading #{filename}..."
  upload_url = github_release['upload_url'].gsub('{?name,label}', '')
  response = DragonRubyForCiRepository.post(
    "#{upload_url}?name=#{filename}",
    body: File.read(file),
    headers: {
      'Content-Type' => 'application/zip'
    }
  )

  if response.code == 201
    puts "Uploaded #{filename} successfully"
    return JSON.parse(response.body)
  end

  raise "Failed to upload release asset: #{response.code} #{response.body}"
end

class DragonRubyForCiRepository
  include HTTParty
  base_uri 'https://api.github.com/repos/kfischer-okarin/dragonruby-for-ci'
  headers 'Accept' => 'application/vnd.github+json',
          'Authorization' => "Bearer #{ENV['GITHUB_TOKEN']}",
          'X-GitHub-Api-Version' => '2022-11-28'
end

main if $PROGRAM_NAME == __FILE__
