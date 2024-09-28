#!/usr/bin/env ruby

require_relative 'lib/susi.rb'

if ARGV[0] == 'init'
  Susi::init

elsif ARGV[0] == 'start'
  Susi::start

elsif ARGV[0] == 'rm'
  # quit vm and remove disk
  Susi::VM.quit(Susi::current_vm_name)
  Susi::rm

# create a disk
elsif ARGV[0] == 'disk' && ARGV[1] == 'create' &&
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

# open SSH
elsif ARGV[0] == 'ssh'
  if ARGV[1].is_a?(String)
    vm_name = ARGV[1]
    Susi::SSH.open(vm_name)
  else
    Susi::SSH.open(Susi::current_vm_name)
  end

# download Debian netinstall ISO
elsif ARGV[0] == 'iso' && ARGV[1] == 'download'
  Susi::Disk.download_debian_netinstall

else
  puts <<-EOF
Invalid command

Usage: 
  Init susi setting
  susi init

  Start VM from current folder 
  susi start

  Clean up disks
  susi rm

  Create a VM disk
  susi disk create <disk_name> <disk_size>

  Clone a VM disk
  susi disk clone <disk_name> <new_disk_name>

  Start a VM
  susi vm start <vm_name>

  Install a VM
  susi vm install <vm_name> <iso>

  Quit a VM
  susi vm quit <vm_name>

  List VMs
  susi ls
  susi vm ls

  Open VNC
  susi vnc <vm_name>

  Open SSH
  susi ssh <vm_name>

  Download Debian netinstall ISO
  susi iso download

susi (v#{Susi::VERSION}) - Simple User System Interface

author:  Daniel Bovensiepen
contact: oss@bovi.li
www:     https://github.com/bovi/susi
EOF

exit 1

end
