#!/usr/bin/env ruby

require_relative 'vendor/bundle/bundler/setup'
require 'pathname'
require 'zip'

def main
  folder = ARGV.shift || './downloads'

  folder = Pathname(folder)

  DragonrubyZip.clean_folder(folder)

  zips = %w[windows-amd64 macos linux-amd64].flat_map { |platform|
    [
      DragonrubyZip.new(folder / "dragonruby-gtk-#{platform}.zip"),
      DragonrubyZip.new(folder / "dragonruby-pro-#{platform}.zip")
    ]
  }

  zips.each do |zip|
    zip.extract_ci_zip(folder)
  end

  output_version_to_file(folder, zips)
end

class DragonrubyZip
  OUTPUT_PREFIX = 'dragonruby-for-ci'.freeze

  attr_reader :platform, :version

  def self.clean_folder(folder)
    folder.glob("#{OUTPUT_PREFIX}-*.zip").each(&:delete)
  end

  def initialize(filename)
    puts "Reading #{filename}..."
    @zip = Zip::File.open(filename)
    determine_platform
    determine_version
  end

  def extract_ci_zip(target_dir)
    target_zip_name = File.join(target_dir, "#{OUTPUT_PREFIX}-#{@version}-#{@license_type}-#{@platform}.zip")
    Zip::File.open(target_zip_name, Zip::File::CREATE) do |zip_file|
      entries_to_copy = [
        "dragonruby-#{@platform}/#{binary_filename}",
        "dragonruby-#{@platform}/font.ttf"
      ]
      if @license_type == :pro
        # all entries in include/
        entries_to_copy += @zip.glob("dragonruby-#{@platform}/include/**/*").map(&:name)
      end

      prefix_length = "dragonruby-#{@platform}/".length
      entries_to_copy.each do |filename|
        entry = @zip.find_entry(filename)
        next if entry.directory?
        next if entry.name =~ /DS_Store/

        target_filename = filename[prefix_length..]
        puts "Adding #{target_filename}..."
        zip_file.get_output_stream(target_filename) { |f|
          f.write entry.get_input_stream.read
        }
      end
    end
    target_zip_name
  end

  private

  def determine_platform
    @platform = %w[windows-amd64 macos linux-amd64].find { |platform|
      @zip.find_entry("dragonruby-#{platform}/")
    }
    raise 'Unknown platform' unless @platform

    @license_type = @zip.find_entry("dragonruby-#{platform}/include/") ? :pro : :standard
  end

  def determine_version
    changelog_file = @zip.find_entry("dragonruby-#{@platform}/CHANGELOG-CURR.txt")
    first_version_line = changelog_file.get_input_stream.read.lines.find { |line|
      line.start_with? '* '
    }.strip
    @version = first_version_line.split(' ')[1]
  end

  def binary_filename
    case @platform
    when 'windows-amd64'
      'dragonruby.exe'
    else
      'dragonruby'
    end
  end
end

def output_version_to_file(folder, zips)
  version = zips.first.version
  File.write(folder / '.version', version)
end

main if $PROGRAM_NAME == __FILE__
