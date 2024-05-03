#!/usr/bin/env ruby

require_relative 'lib/susi.rb'

# create a disk
if ARGV[0] == 'disk' && ARGV[1] == 'create' &&
    ARGV[2].is_a?(String) && ARGV[3].to_i > 0
  disk_name = ARGV[2]
  disk_size = ARGV[3].to_i
  Susi::Disk.create(disk_name, disk_size)

# clone a disk
elsif ARGV[0] == 'disk' && ARGV[1] == 'clone' &&
    ARGV[2].is_a?(String) && ARGV[3].is_a?(String) &&
    File.exist?("#{ARGV[2]}.qcow2") &&
    !File.exist?("#{ARGV[3]}.qcow2")
  disk_name = ARGV[2]
  new_disk_name = ARGV[3]
  Susi::Disk.clone(disk_name, new_disk_name)

else
  puts 'Invalid command'
  exit 1
end
