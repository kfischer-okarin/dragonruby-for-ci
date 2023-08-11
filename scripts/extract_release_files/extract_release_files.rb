#!/usr/bin/env ruby

require_relative 'vendor/bundle/bundler/setup'
require 'pathname'
require 'zip'

def main
  folder = ARGV.shift
  raise 'No folder given' unless folder

  folder = Pathname(folder)
  %w[windows-amd64 macos linux-amd64].each do |platform|
    zip = DragonrubyZip.new(folder / "dragonruby-gtk-#{platform}.zip")
    zip.extract_ci_zip(folder)

    zip = DragonrubyZip.new(folder / "dragonruby-pro-#{platform}.zip")
    zip.extract_ci_zip(folder)
  end
end

class DragonrubyZip
  attr_reader :platform

  def initialize(filename)
    @zip = Zip::File.open(filename)
    determine_platform
    determine_version
  end

  def extract_ci_zip(target_dir)
    target_zip_name = File.join(target_dir, "dragonruby-for-ci-#{@version}-#{@license_type}-#{@platform}.zip")
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

main if $PROGRAM_NAME == __FILE__
