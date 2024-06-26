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

# start VM
elsif ARGV[0] == 'vm' && ARGV[1] == 'start' &&
    ARGV[2].is_a?(String) && File.exist?("#{ARGV[2]}.qcow2")
  vm_name = ARGV[2]
  Susi::VM.start(vm_name, vm_name)

# install VM
elsif ARGV[0] == 'vm' && ARGV[1] == 'install' &&
  ARGV[2].is_a?(String) && File.exist?("#{ARGV[2]}.qcow2") &&
    ARGV[3].is_a?(String) && File.exist?(ARGV[3])
  vm_name = ARGV[2]
  iso = ARGV[3]
  Susi::VM.install(vm_name, vm_name, iso)

# quit VM
elsif ARGV[0] == 'vm' && ARGV[1] == 'quit' &&
    ARGV[2].is_a?(String)
  vm_name = ARGV[2]
  Susi::VM.quit(vm_name)

# list VMs
elsif ARGV[0] == 'vm' && ARGV[1] == 'ls'
  Susi::VM.ls
elsif ARGV[0] == 'ls'
  Susi::VM.ls

# open VNC
elsif ARGV[0] == 'vnc' &&
    ARGV[1].is_a?(String)
  vm_name = ARGV[2]
  Susi::VNC.open(vm_name)

else
  puts <<-EOF
Invalid command

Usage: 
  Create a VM disk
  susi disk create <disk_name> <disk_size>

  Clone a VM disk
  susi disk clone <disk_name> <new_disk_name>

  Start a VM
  susi vm start <vm_name>

  Quit a VM
  susi vm quit <vm_name>

  List VMs
  susi ls
  susi vm ls

  Open VNC
  susi vnc <vm_name>

susi (v0.1.0) - Simple User System Interface

author:  Daniel Bovensiepen
contact: oss@bovi.li
www:     https://github.com/bovi/susi
EOF

  exit 1
end
